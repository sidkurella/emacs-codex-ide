#!/usr/bin/env python3
"""Minimal MCP bridge that proxies tool calls into a running Emacs instance."""

from __future__ import annotations

import argparse
import ast
import base64
import json
import subprocess
import sys
from typing import Any


PROTOCOL_VERSION = "2024-11-05"
SERVER_INFO = {"name": "codex-ide-emacs-bridge", "version": "0.1.0"}


def json_dumps(value: Any) -> bytes:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=True).encode("utf-8")


def read_message() -> dict[str, Any] | None:
    headers: dict[str, str] = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break
        key, _, value = line.decode("utf-8").partition(":")
        headers[key.strip().lower()] = value.strip()
    length = int(headers.get("content-length", "0"))
    if length <= 0:
        return None
    body = sys.stdin.buffer.read(length)
    if not body:
        return None
    return json.loads(body.decode("utf-8"))


def write_message(payload: dict[str, Any]) -> None:
    body = json_dumps(payload)
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


class EmacsProxy:
    def __init__(self, emacsclient: str, server_name: str | None) -> None:
        self.emacsclient = emacsclient
        self.server_name = server_name

    def _eval(self, expression: str) -> str:
        command = [self.emacsclient]
        if self.server_name:
            command.extend(["-s", self.server_name])
        command.extend(["--eval", expression])
        completed = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
        )
        output = completed.stdout.strip()
        if not output:
            raise RuntimeError("emacsclient returned no output")
        try:
            return ast.literal_eval(output)
        except Exception as exc:  # pragma: no cover - defensive parse guard
            raise RuntimeError(f"unexpected emacsclient response: {output}") from exc

    def dispatch(self, action: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        request = {"action": action, "params": params or {}}
        payload = base64.b64encode(json_dumps(request)).decode("ascii")
        expression = (
            f'(let* ((payload (base64-decode-string "{payload}"))'
            '        (result (codex-ide-bridge-dispatch-json payload)))'
            '   (base64-encode-string result t))'
        )
        encoded = self._eval(expression)
        response = json.loads(base64.b64decode(encoded).decode("utf-8"))
        if not response.get("ok"):
            raise RuntimeError(response.get("error", "bridge request failed"))
        return response["result"]


def text_result(text: str, *, is_error: bool = False) -> dict[str, Any]:
    result: dict[str, Any] = {"content": [{"type": "text", "text": text}]}
    if is_error:
        result["isError"] = True
    return result


def schema_for_tools(metadata: dict[str, Any]) -> list[dict[str, Any]]:
    allowed_commands = metadata.get("allowedCommands") or []
    tools = [
        {
            "name": "emacs_get_context",
            "description": "Read the current Emacs file/buffer context.",
            "inputSchema": {
                "type": "object",
                "properties": {},
                "additionalProperties": False,
            },
        },
        {
            "name": "emacs_open_file",
            "description": "Open a file in Emacs and optionally jump to line and column.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "line": {"type": "integer", "minimum": 1},
                    "column": {"type": "integer", "minimum": 1},
                },
                "required": ["path"],
                "additionalProperties": False,
            },
        },
    ]
    if allowed_commands:
        tools.append(
            {
                "name": "emacs_run_command",
                "description": "Run an allowed interactive Emacs command.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "command": {
                            "type": "string",
                            "enum": allowed_commands,
                        }
                    },
                    "required": ["command"],
                    "additionalProperties": False,
                },
            }
        )
    if metadata.get("allowEval"):
        tools.append(
            {
                "name": "emacs_eval",
                "description": "Evaluate an Emacs Lisp expression in the running Emacs instance.",
                "inputSchema": {
                    "type": "object",
                    "properties": {"expression": {"type": "string"}},
                    "required": ["expression"],
                    "additionalProperties": False,
                },
            }
        )
    return tools


def handle_tool_call(proxy: EmacsProxy, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name == "emacs_get_context":
        result = proxy.dispatch("get_context")
    elif name == "emacs_open_file":
        result = proxy.dispatch("open_file", arguments)
    elif name == "emacs_run_command":
        result = proxy.dispatch("run_command", arguments)
    elif name == "emacs_eval":
        result = proxy.dispatch("eval", arguments)
    else:
        return text_result(f"Unknown tool: {name}", is_error=True)
    return text_result(json.dumps(result, indent=2, sort_keys=True))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--emacsclient", default="emacsclient")
    parser.add_argument("--server-name", default=None)
    args = parser.parse_args()

    proxy = EmacsProxy(args.emacsclient, args.server_name)
    try:
        metadata = proxy.dispatch("describe")
    except Exception as exc:
        sys.stderr.write(f"Failed to initialize Emacs bridge: {exc}\n")
        sys.stderr.flush()
        return 1

    while True:
        message = read_message()
        if message is None:
            return 0
        method = message.get("method")
        request_id = message.get("id")
        params = message.get("params") or {}

        try:
            if method == "initialize":
                write_message(
                    {
                        "jsonrpc": "2.0",
                        "id": request_id,
                        "result": {
                            "protocolVersion": PROTOCOL_VERSION,
                            "serverInfo": SERVER_INFO,
                            "capabilities": {"tools": {}},
                        },
                    }
                )
            elif method == "notifications/initialized":
                continue
            elif method == "ping":
                write_message({"jsonrpc": "2.0", "id": request_id, "result": {}})
            elif method == "tools/list":
                metadata = proxy.dispatch("describe")
                write_message(
                    {
                        "jsonrpc": "2.0",
                        "id": request_id,
                        "result": {"tools": schema_for_tools(metadata)},
                    }
                )
            elif method == "tools/call":
                write_message(
                    {
                        "jsonrpc": "2.0",
                        "id": request_id,
                        "result": handle_tool_call(
                            proxy,
                            params.get("name", ""),
                            params.get("arguments") or {},
                        ),
                    }
                )
            else:
                write_message(
                    {
                        "jsonrpc": "2.0",
                        "id": request_id,
                        "error": {
                            "code": -32601,
                            "message": f"Method not found: {method}",
                        },
                    }
                )
        except subprocess.CalledProcessError as exc:
            stderr = exc.stderr.strip() if exc.stderr else str(exc)
            write_message(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": text_result(stderr, is_error=True),
                }
            )
        except Exception as exc:  # pragma: no cover - protocol safety net
            write_message(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": text_result(str(exc), is_error=True),
                }
            )


if __name__ == "__main__":
    raise SystemExit(main())

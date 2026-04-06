#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/bin/generate-autoloads.sh"
"$ROOT_DIR/bin/run-tests.sh"

exec emacs -Q --batch \
  --eval "(setq load-prefer-newer t)" \
  -L "$ROOT_DIR" \
  --eval "(require 'codex-ide-autoloads)" \
  --eval "(require 'codex-ide)" \
  --eval "(princ \"codex-ide loaded successfully\n\")"

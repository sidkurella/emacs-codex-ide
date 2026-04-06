#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec emacs -Q \
  --eval "(setq load-prefer-newer t)" \
  --eval "(setq load-suffixes '(\".el\"))" \
  -L "$ROOT_DIR" \
  --eval "(require 'codex-ide)"

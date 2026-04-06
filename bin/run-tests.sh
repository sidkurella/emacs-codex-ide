#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec emacs -Q --batch \
  --eval "(setq load-prefer-newer t)" \
  --eval "(setq load-suffixes '(\".el\"))" \
  -L "$ROOT_DIR" \
  -L "$ROOT_DIR/tests" \
  -l "$ROOT_DIR/tests/codex-ide-tests.el" \
  -f ert-run-tests-batch-and-exit

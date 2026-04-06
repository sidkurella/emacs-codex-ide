#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec emacs -Q --batch \
  --eval "(require 'package)" \
  --eval "(setq load-prefer-newer t)" \
  --eval "(let ((default-directory \"$ROOT_DIR/\"))
             (package-generate-autoloads \"codex-ide\" default-directory))"

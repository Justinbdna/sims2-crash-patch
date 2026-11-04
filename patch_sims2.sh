#!/bin/bash
set -e

# patch_sims2.sh
# Lanceur avec sudo pour patcher The Sims 2: Super Collection sur macOS Apple Silicon

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/patch_sims2.py"

echo "=== The Sims 2: Super Collection - Patch ProMotion 120 Hz ==="
if [ "$EUID" -ne 0 ]; then
    echo "Privilèges administrateur requis. Demande de mot de passe sudo :"
    exec sudo python3 "$PYTHON_SCRIPT"
else
    python3 "$PYTHON_SCRIPT"
fi

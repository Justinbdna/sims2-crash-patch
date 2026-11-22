#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

clang -arch x86_64 -mmacosx-version-min=10.13 -dynamiclib -O2 -fobjc-arc -framework Cocoa -framework Carbon -framework CoreGraphics -framework OpenGL -install_name "@executable_path/libsims2_trackpad.dylib" -o trackpad_mod/libsims2_trackpad.dylib trackpad_mod/sims2_trackpad.m
codesign --force --sign - trackpad_mod/libsims2_trackpad.dylib

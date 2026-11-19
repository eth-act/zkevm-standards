#!/usr/bin/env bash
# Recreate reference/build/sail-riscv/ from the pinned submodule and apply sail-riscv.patch.
set -euo pipefail
REF="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$REF/build"
rm -rf "$REF/build/sail-riscv"
rsync -a --delete --exclude .git "$REF/sail-riscv/" "$REF/build/sail-riscv/"
if [ -s "$REF/sail-riscv.patch" ]; then
  (cd "$REF/build/sail-riscv" && patch -p1 --forward < ../../sail-riscv.patch)
fi

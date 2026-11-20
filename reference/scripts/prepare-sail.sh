#!/usr/bin/env bash
# Recreate reference/build/sail-riscv/ from the pinned submodule, apply sail/hooks.patch,
# and add the zkVM modules (sail/zkvm/*.sail) as model/zkvm/.
set -euo pipefail
REF="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$REF/build"
rm -rf "$REF/build/sail-riscv"
rsync -a --delete --exclude .git "$REF/sail-riscv/" "$REF/build/sail-riscv/"
if [ -s "$REF/sail/hooks.patch" ]; then
  (cd "$REF/build/sail-riscv" && patch -p1 --forward < ../../sail/hooks.patch)
fi
mkdir -p "$REF/build/sail-riscv/model/zkvm"
cp "$REF/sail/zkvm/"*.sail "$REF/build/sail-riscv/model/zkvm/"

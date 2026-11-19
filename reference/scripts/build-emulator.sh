#!/usr/bin/env bash
# Build the patched sail-riscv C++ emulator into reference/build/emu/.
set -euo pipefail
REF="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$REF/scripts/fetch-sail.sh"
export PATH="$REF/build/sail-0.20.2/sail/bin:$PATH"
"$REF/scripts/prepare-sail.sh"
cmake -S "$REF/build/sail-riscv" -B "$REF/build/emu" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DENABLE_RISCV_TESTS=ON
cmake --build "$REF/build/emu" -j"$(nproc)" --target sail_riscv_sim

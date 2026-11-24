#!/usr/bin/env bash
# Generate the Lean model of the zkVM reference machine (the pinned, unmodified sail-riscv plus
# the zkVM modules declared in sail/zkvm.sail_project) with the configuration from
# scripts/make-config.py, then build it and the zkvm-ref Lean package.
#
# Module subset. The target standard is riscv64im_zicclsm. Its instructions are all in the I and
# M instruction modules; Zicclsm adds no instructions, only the guarantee that misaligned loads
# and stores to main memory succeed, which is configuration (see config/README.md). So the model
# is generated from I_insts, M_insts, postlude (with everything it requires) and the zkVM
# modules, and the configuration enables no other instruction extension; their encodings decode
# as illegal instructions. Generating every module is not possible: sail-riscv's full
# `instruction` type has 355 constructors, but Lean objects store the constructor index in 8
# bits (LeanMaxCtorTag = 243 in lean.h), so `execute` cannot be compiled; elaborating the full
# 32-bit decoder also does not finish in hours.
set -euo pipefail
REF="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$REF/scripts/fetch-sail.sh"
python3 "$REF/scripts/make-config.py" "$REF/build/config/zkvm.json"
export PATH="$REF/build/sail-0.20.2/sail/bin:$PATH"
mkdir -p "$REF/build/lean"
(
  cd "$REF/sail-riscv/model"
  sail --strict-var --strict-bitvector --strict-exponentials --require-version 0.20.2 \
    --memo-z3-path "$REF/build/lean/sail_smt_cache" \
    --config "$REF/build/config/zkvm.json" \
    --lean --memo-z3 --lean-output-dir "$REF/build/lean" --lean-force-output \
    --lean-non-beq-type instruction --lean-non-beq-type ExecutionResult --lean-non-beq-type Step \
    --lean-import-file ../handwritten_support/RiscvExtrasExecutable.lean \
    -o Lean_RV64D_executable riscv.sail_project "$REF/sail/zkvm.sail_project" \
    I_insts M_insts postlude zkvm_extension_fallback zkvm_machine
)
GEN="$REF/build/lean/Lean_RV64D_executable"
# Sail 0.20.2's Lean backend does not wrap the generated definitions in a `<Module>.Defs`
# namespace, which sail-riscv's handwritten support file opens; drop that `open`.
sed -i '/^open LeanRV64DExecutable\.Defs$/d' "$GEN/LeanRV64DExecutable/RiscvExtrasExecutable.lean"
# `reset` calls `cancel_reservation`, which the handwritten support file leaves as
# `panic "TODO"`. Reservations only exist for the A extension, which is not in this model,
# so cancelling one is a no-op.
sed -i 's/^def cancel_reservation : Unit → SailM Unit := λ _ => panic "TODO"$/def cancel_reservation : Unit → SailM Unit := λ _ => pure ()/' \
  "$GEN/LeanRV64DExecutable/RiscvExtrasExecutable.lean"
grep -q '^def cancel_reservation : Unit → SailM Unit := λ _ => pure ()$' \
  "$GEN/LeanRV64DExecutable/RiscvExtrasExecutable.lean"
cp "$GEN/lean-toolchain" "$REF/lean/lean-toolchain"
toolchain="$(cat "$REF/lean/lean-toolchain")"
elan toolchain list | grep -q "^${toolchain}" || elan toolchain install "$toolchain"
(cd "$GEN" && lake update && lake build)
(cd "$REF/lean" && lake build)

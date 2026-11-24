# Instruction Address Misaligned Exception Semantics

This proposal standardizes the handling of instruction-address-misaligned exceptions. The specification establishes the required effect when the underlying ISA would raise an instruction-address-misaligned exception, enabling consistent proof verification behavior and stronger correctness and security guarantees.

## Motivation

* **Consistent program behavior**
  Developers targeting multiple zkVM must be able to rely on consistent, predictable behavior when their program encounters a fault. Without a standard, the effect of an instruction-address-misaligned exception varies across implementations.

* **Proof system integrity**
  Without a standard, the effect of such a fault on the proof is undefined, which risks allowing a valid proof to be produced for an execution that did not reach a valid completion state.

* **Developer experience**
  Explicit and consistent fault semantics simplify portability and debugging across zkVM backends.

## Relationship to Other Standards

This standard applies to any zkVM whose underlying ISA can raise an instruction-address-misaligned exception. This includes, but is not limited to, the `riscv64im_zicclsm-unknown-none-elf` target defined in the RISC-V target standard, where the absence of the C extension means IALIGN=32 and any jump to a non-4-byte-aligned address raises such an exception. zkVMs supporting additional extensions — such as the C extension, which reduces IALIGN to 16 — will raise this exception under a narrower set of conditions, but the required effect when the exception does occur is the same.

The required effect of an instruction-address-misaligned exception is abnormal termination as defined by the execution termination semantics standard.

Note that the `Zicclsm` extension, which mandates transparent handling of misaligned *data* memory accesses, has no bearing on instruction fetch alignment. `Zicclsm` applies exclusively to load and store operations. A zkVM implementing `Zicclsm` must still apply this standard when an instruction-address-misaligned exception would be raised.

## Specification

### Instruction-Address-Misaligned Exception

When the underlying ISA would raise an instruction-address-misaligned exception, the zkVM must trigger abnormal termination as defined by the execution termination semantics standard.

No recovery or continuation strategy — including but not limited to rounding the target address down to the nearest aligned address — is permitted.

### Rationale

A misaligned instruction address is not a recoverable or expected condition in any well-functioning program. Regardless of whether a zkVM exposes an exception handling mechanism, the observable behavior of the program must be consistent across implementations: the program must terminate abnormally.

### Verification

Verification behavior follows directly from the execution termination semantics standard. For a Type 1 verifier, verification fails for any proof of an execution that terminated due to an instruction-address-misaligned exception. For a Type 2 verifier, the exception may translate to a non-zero exit code, and verification can succeed only if the verifier explicitly accepts that exit code.

## Normative requirements

Each requirement has an ID. "Checked by" names where it is enforced or tested: `Sail` (the reference in `reference/sail/`), `Lean` (a statement in `reference/lean/ZkvmRef/`), `monitor` (a guest test in eth-act/zkevm-test-monitor), `monitor-static` (a static check there), or `not tested` with the reason.

| ID | Requirement | Applies to | Checked by |
| --- | --- | --- | --- |
| IAM1 | When the underlying ISA would raise an instruction-address-misaligned exception, the zkVM must trigger abnormal termination as defined by the execution termination semantics standard. | zkVM | Sail, monitor |
| IAM2 | No recovery or continuation strategy, including rounding the target address down to the nearest aligned address, is permitted. | zkVM | Sail, monitor |
| IAM3 | A zkVM implementing `Zicclsm` must still apply this standard when an instruction-address-misaligned exception would be raised. | zkVM | Sail, monitor |
| IAM4 | For a Type 1 verifier, verification fails for any proof of an execution that terminated due to an instruction-address-misaligned exception. | verifier | Lean, monitor |
| IAM5 | For a Type 2 verifier, the exception may translate to a non-zero exit code, and verification can succeed only if the verifier explicitly accepts that exit code. | verifier | Lean, not tested: no harness exposes Type 2 verify (eth-act/zkevm-test-monitor#73) |

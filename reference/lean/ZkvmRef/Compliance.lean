/-
Statements of compliance with the merged zkvm-standards, relative to the reference machine:
what a zkVM (`Compliant` and its parts) and a vendor static library (`StaticLibraryConforms`,
`ImplementsHost`) must satisfy. Definitions only; nothing here is proved. Statements about the
reference loader itself are in ZkvmRef/LoaderSpec.lean.
-/
import ZkvmRef.Loader
import ZkvmRef.Machine
import ZkvmRef.Run
import ZkvmRef.StaticLibrary

open LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- The library code at `entry` implements host function `f`: from any call of it, running
the code natively returns to `ra` with the callee-saved registers, `a0`, the public output and
all memory outside the stack reserve as the host function leaves them, and faults whenever the
host function faults. `a0` must equal the reference value exactly (for `memcmp`, -1, 0 or 1).

Meaningful for functions that return to `ra` and are implementable in RV64IM: the memory
operations. The I/O functions additionally need a vendor I/O mechanism, which this machine does
not have. Not for `_start` (it does not return) or accelerators (unspecified semantics). [MEM3] -/
def ImplementsHost (f : zkvm_library_fn) (entry : Nat) : Prop :=
  ∀ s s', AtEntry s entry → runM (zkvm_host_call f) s = .ok ((), s') →
    (haltOf s' = none →
      ∃ t, CallReturns (native s) t ∧ CalleeSaved s t ∧ xreg t 10 = xreg s' 10 ∧
        outputRev t = outputRev s' ∧
        ∀ x, ¬ InRange ((xreg s 2).toNat - stackReserve) stackReserve x →
          t.mem.get? x = s'.mem.get? x) ∧
    (haltOf s' = some (.ZKVM_Fault ()) → ∃ n, (run n (native s)).outcome = .fault)

end ZkvmRef

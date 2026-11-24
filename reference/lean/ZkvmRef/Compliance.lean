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

/-- The reference machine loads `elf` under `p`, runs it on `input`, and halts with `o`,
whatever the initial values of `x1`…`x31`, which the standards leave unspecified: a program
whose observation depends on them halts with no particular `o`, and the statements below make no
claim about it. Runs that reach an accelerator end in `unspecified`, which is not terminal, so
the statements make no claim about them either. -/
def Halts (p : MemoryProfile) (elf input : ByteArray) (o : Observation) : Prop :=
  ∀ gprs, ∃ s n, boot p elf input gprs = .ok s ∧ run n s = o ∧ Terminal o.outcome

/-- The reference loader rejects `elf` under `p`. -/
def Rejects (p : MemoryProfile) (elf : ByteArray) : Prop :=
  ∃ m, validate p elf = .error m

/-- An abstract zkVM: setup (loading), execution, and two kinds of verifiers.
`verify1` checks proofs of successful runs with a given output; `verify2` checks proofs of
runs with a given output and exit code. `failureCode d` is the code the zkVM reports when
`main` returns `d ≠ 0`: the termination standard mandates only the distinction between zero
and non-zero, and "the range of error codes a zkVM preserves is vendor-defined". -/
structure ZkVM where
  Program : Type
  Proof : Type
  setup : ByteArray → Option Program
  execute : Program → ByteArray → Option Observation
  verify1 : Program → List UInt8 → Proof → Bool
  verify2 : Program → List UInt8 → UInt32 → Proof → Bool
  failureCode : UInt32 → UInt32

/-- A non-zero return value of `main` is reported as a non-zero code. [TER11] -/
def FailureCodesNonZero (z : ZkVM) : Prop :=
  ∀ d, d ≠ 0 → z.failureCode d ≠ 0

/-- A reference outcome as the zkVM reports it: `failure d` becomes `failure (failureCode d)`. -/
def ZkVM.reported (z : ZkVM) : Outcome → Outcome
  | .failure d => .failure (z.failureCode d)
  | o => o

/-- A claimed exit code agrees with a reference outcome. Fault codes are vendor-defined
(instruction-address-misaligned standard: a fault "may translate to a non-zero exit code"),
so any non-zero code matches `fault`. -/
def CodeMatches (z : ZkVM) : UInt32 → Outcome → Prop
  | c, .success => c = 0
  | c, .failure d => c ≠ 0 ∧ c = z.failureCode d
  | c, .fault => c ≠ 0
  | _, _ => False

/-- A vendor observation agrees with the reference one: same output, same outcome as the zkVM
reports it (`ZkVM.reported`), except that a reference `fault` may be reported as any non-zero
vendor failure code. -/
def ObsMatches (z : ZkVM) (vendor reference : Observation) : Prop :=
  vendor.output = reference.output ∧
    (vendor.outcome = z.reported reference.outcome ∨
      (reference.outcome = .fault ∧ ∃ c, c ≠ 0 ∧ vendor.outcome = .failure c))

/-- The zkVM accepts exactly the ELFs the reference loader accepts. -/
def LoaderConforms (z : ZkVM) (p : MemoryProfile) : Prop :=
  ∀ elf, z.setup elf = none ↔ Rejects p elf

/-- Whenever the reference halts, the zkVM's execution produces a matching observation. -/
def ExecutionConforms (z : ZkVM) (p : MemoryProfile) : Prop :=
  ∀ elf prog input o, z.setup elf = some prog → Halts p elf input o →
    ∃ o', z.execute prog input = some o' ∧ ObsMatches z o' o

/-- Type 1 soundness: an accepted proof of output `out` implies some input makes the
reference succeed with output `out`. Quantifies over every proof `π`, not only the honest
prover's. [TER7][TER9][IAM4] -/
def Type1Sound (z : ZkVM) (p : MemoryProfile) : Prop :=
  ∀ elf prog out π, z.setup elf = some prog → z.verify1 prog out π = true →
    ∃ input, Halts p elf input ⟨.success, out⟩

/-- Type 2 soundness: an accepted proof of `(out, c)` implies some input makes the reference
halt with output `out` and an outcome matching `c`. Quantifies over every proof `π`.
[TER8][TER9][IAM5] -/
def Type2Sound (z : ZkVM) (p : MemoryProfile) : Prop :=
  ∀ elf prog out c π, z.setup elf = some prog → z.verify2 prog out c π = true →
    ∃ input o, Halts p elf input o ∧ o.output = out ∧ CodeMatches z c o.outcome

/-- Type 1 completeness: every successful reference run has an accepted proof. -/
def Type1Complete (z : ZkVM) (p : MemoryProfile) : Prop :=
  ∀ elf prog input out, z.setup elf = some prog → Halts p elf input ⟨.success, out⟩ →
    ∃ π, z.verify1 prog out π = true

/-- A compliant zkVM reports failures with non-zero codes, conforms in loading and execution,
and is sound for one proof type. [TER6] -/
def Compliant (z : ZkVM) (p : MemoryProfile) : Prop :=
  FailureCodesNonZero z ∧ LoaderConforms z p ∧ ExecutionConforms z p ∧
    (Type1Sound z p ∨ Type2Sound z p)

-- Static library

/-- A linked guest carries a conforming static library and linker script: all required
symbols are defined and the ELF entry point is `_start`. [LIB2][LIB3][LIB4][LIB5][LIB15] -/
def StaticLibraryConforms (elf : zkvm_elf) : Prop :=
  (∀ n ∈ requiredExports ++ linkerScriptSymbols, Exports elf n) ∧
    zkvm_symbol_value elf.symbols (zkvm_library_symbol zkvm_library .ZKVM_START) =
      some (BitVec.ofInt 64 elf.entry)

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

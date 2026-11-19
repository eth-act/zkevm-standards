/-
Statements of zkVM compliance with the merged zkvm-standards, relative to the
reference machine. Definitions only; nothing here is proved.
-/
import ZkvmRef.Loader
import ZkvmRef.Machine
import ZkvmRef.Run

namespace ZkvmRef

/-- The reference machine loads `elf` under `p`, runs it on `input`, and halts with `o`. -/
def Halts (p : Profile) (elf input : ByteArray) (o : Observation) : Prop :=
  ∃ img s n, load p elf = .ok img ∧ initialState p img input = .ok s ∧ run n s = o ∧
    Terminal o.outcome

/-- The reference loader rejects `elf` under `p`. -/
def Rejects (p : Profile) (elf : ByteArray) : Prop :=
  ∃ m, load p elf = .error m

/-- A claimed exit code agrees with a reference outcome. Fault codes are vendor-defined
(instruction-address-misaligned standard: a fault "may translate to a non-zero exit code"),
so any non-zero code matches `fault`. -/
def CodeMatches : UInt32 → Outcome → Prop
  | c, .success => c = 0
  | c, .failure d => c ≠ 0 ∧ c = d
  | c, .fault => c ≠ 0
  | _, _ => False

/-- A vendor observation agrees with the reference one: same output, same outcome, except
that a reference `fault` may be reported as any non-zero vendor failure code. -/
def ObsMatches (vendor reference : Observation) : Prop :=
  vendor.output = reference.output ∧
    (vendor.outcome = reference.outcome ∨
      (reference.outcome = .fault ∧ ∃ c, c ≠ 0 ∧ vendor.outcome = .failure c))

/-- An abstract zkVM: setup (loading), execution, and two kinds of verifiers.
`verify1` checks proofs of successful runs with a given output; `verify2` checks proofs of
runs with a given output and exit code. -/
structure ZkVM where
  Program : Type
  Proof : Type
  setup : ByteArray → Option Program
  execute : Program → ByteArray → Option Observation
  verify1 : Program → List UInt8 → Proof → Bool
  verify2 : Program → List UInt8 → UInt32 → Proof → Bool

/-- The zkVM accepts exactly the ELFs the reference loader accepts. -/
def LoaderConforms (z : ZkVM) (p : Profile) : Prop :=
  ∀ elf, z.setup elf = none ↔ Rejects p elf

/-- Whenever the reference halts, the zkVM's execution produces a matching observation. -/
def ExecutionConforms (z : ZkVM) (p : Profile) : Prop :=
  ∀ elf prog input o, z.setup elf = some prog → Halts p elf input o →
    ∃ o', z.execute prog input = some o' ∧ ObsMatches o' o

/-- Type 1 soundness: an accepted proof of output `out` implies some input makes the
reference succeed with output `out`. -/
def Type1Sound (z : ZkVM) (p : Profile) : Prop :=
  ∀ elf prog out π, z.setup elf = some prog → z.verify1 prog out π = true →
    ∃ input, Halts p elf input ⟨.success, out⟩

/-- Type 2 soundness: an accepted proof of `(out, c)` implies some input makes the reference
halt with output `out` and an outcome matching `c`. -/
def Type2Sound (z : ZkVM) (p : Profile) : Prop :=
  ∀ elf prog out c π, z.setup elf = some prog → z.verify2 prog out c π = true →
    ∃ input o, Halts p elf input o ∧ o.output = out ∧ CodeMatches c o.outcome

/-- Type 1 completeness: every successful reference run has an accepted proof. -/
def Type1Complete (z : ZkVM) (p : Profile) : Prop :=
  ∀ elf prog input out, z.setup elf = some prog → Halts p elf input ⟨.success, out⟩ →
    ∃ π, z.verify1 prog out π = true

/-- A compliant zkVM conforms in loading and execution and is sound for one proof type. -/
def Compliant (z : ZkVM) (p : Profile) : Prop :=
  LoaderConforms z p ∧ ExecutionConforms z p ∧ (Type1Sound z p ∨ Type2Sound z p)

end ZkvmRef

/-
Running the reference machine and its observations (standard termination semantics). The step
itself is Sail's `zkvm_step` (reference/sail/zkvm/zkvm_step.sail); this file iterates it.
-/
import ZkvmRef.Machine

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- One machine step (`zkvm_step`): the host function bound to the PC if there is one, else one
instruction. `.error` if the model is stuck, for example on a read of a register or memory byte
that has no value, or on a step after the run has halted (a Sail assertion). -/
def step (s : MState) : Except String MState :=
  (·.2) <$> runM (zkvm_step ()) s

/-- How a run ended. `leanOutOfFuel` is not an outcome of the standards: the Lean run loop must
terminate, so it stops after a given number of steps; the statements only consider runs that
halt within some number of steps. -/
inductive Outcome
  | success
  | failure (code : UInt32)
  | fault
  | unspecified (name : String)
  | leanOutOfFuel
  | stuck (msg : String)
  deriving DecidableEq, Repr

/-- The externally visible result of a run: its outcome and the public output. -/
structure Observation where
  outcome : Outcome
  output : List UInt8
  deriving DecidableEq, Repr

/-- The outcome of a halted machine (Sail's `zkvm_outcome`). -/
def Outcome.ofHalt : zkvm_outcome → Outcome
  | .ZKVM_Success () => .success
  | .ZKVM_Failure c => .failure (UInt32.ofNat c.toNat)
  | .ZKVM_Fault () => .fault
  | .ZKVM_Unspecified n => .unspecified n

/-- Step until the run halts or is stuck, or `fuel` steps have run; returns the observation and
the final state. -/
def runFinal : Nat → MState → Observation × MState
  | fuel, s =>
    match haltOf s with
    | some o => (⟨.ofHalt o, output s⟩, s)
    | none =>
      match fuel with
      | 0 => (⟨.leanOutOfFuel, output s⟩, s)
      | n + 1 =>
        match step s with
        | .ok s' => runFinal n s'
        | .error msg => (⟨.stuck msg, output s⟩, s)

def run (fuel : Nat) (s : MState) : Observation := (runFinal fuel s).1

/-- Outcomes that end a run on the guest's behalf. `unspecified` is not one: the standards do
not say what an accelerator call does. -/
def Terminal : Outcome → Prop
  | .success => True
  | .failure _ => True
  | .fault => True
  | _ => False

end ZkvmRef

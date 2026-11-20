/-
Running the reference machine and its observations (standard termination semantics).
-/
import ZkvmRef.Machine
import ZkvmRef.Host

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- Result of one machine step. -/
inductive StepResult
  | next (s : MState)
  | unspecified (name : String)
  | stuck (msg : String)

/-- One step: the host function bound to the PC if there is one, else one instruction
(`zkvm_step`, reference/sail/zkvm/zkvm_step.sail). -/
def step (s : MState) : StepResult :=
  match runM (do zkvm_host_at (← readReg Register.PC)) s with
  | .error m => .stuck m
  | .ok (some f, _) =>
    match Host.exec f s with
    | .next s' => .next s'
    | .unspecified n => .unspecified n
    | .error m => .stuck m
  | .ok (none, _) =>
    match runM (zkvm_step ()) s with
    | .ok (_, s') => .next s'
    | .error m => .stuck m

/-- How a run ended. `unspecified` names an accelerator the run called. `leanOutOfFuel` is not
an outcome of the standards: the Lean run loop must terminate, so it stops after a given number
of steps; the statements only consider runs that halt within some number of steps. -/
inductive Outcome
  | success
  | failure (code : UInt32)
  | fault
  | leanOutOfFuel
  | stuck (msg : String)
  | unspecified (name : String)
  deriving DecidableEq, Repr

/-- The externally visible result of a run: its outcome and the public output. -/
structure Observation where
  outcome : Outcome
  output : List UInt8
  deriving DecidableEq, Repr

/-- Step until the run halts, a step is stuck or unspecified, or `fuel` steps have run;
returns the observation and the final state. -/
def runFinal : Nat → MState → Observation × MState
  | fuel, s =>
    match haltOf s with
    | some (.ZKVM_Exit c) => (⟨if c = 0 then .success else .failure (UInt32.ofNat c.toNat), output s⟩, s)
    | some (.ZKVM_Fault ()) => (⟨.fault, output s⟩, s)
    | none =>
      match fuel with
      | 0 => (⟨.leanOutOfFuel, output s⟩, s)
      | n + 1 =>
        match step s with
        | .next s' => runFinal n s'
        | .unspecified name => (⟨.unspecified name, output s⟩, s)
        | .stuck msg => (⟨.stuck msg, output s⟩, s)

def run (fuel : Nat) (s : MState) : Observation := (runFinal fuel s).1

/-- Outcomes that end a run on the guest's behalf. -/
def Terminal : Outcome → Prop
  | .success => True
  | .failure _ => True
  | .fault => True
  | _ => False

end ZkvmRef

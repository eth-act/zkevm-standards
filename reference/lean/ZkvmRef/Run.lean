/-
Running the reference machine and its observations (standard termination semantics).
-/
import ZkvmRef.Machine

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- One instruction step of the model. -/
def step (s : MState) : Except String MState :=
  (·.2) <$> runM (try_step 0 true) s

/-- How a run ended. `fault` is the reference runtime's trap exit (HTIF code 2^32). -/
inductive Outcome
  | success
  | failure (code : UInt32)
  | fault
  | badExit (code : Nat)
  | outOfFuel
  | stuck (msg : String)
  deriving DecidableEq, Repr

/-- The externally visible result of a run: its outcome and the public output. -/
structure Observation where
  outcome : Outcome
  output : List UInt8
  deriving DecidableEq, Repr

/-- Outcome of an HTIF exit code. -/
def decodeExit (c : Nat) : Outcome :=
  if c = 0 then .success
  else if c < 2 ^ 32 then .failure (UInt32.ofNat c)
  else if c = 2 ^ 32 then .fault
  else .badExit c

def regOr {α : Type} (s : MState) (r : Register) (d : α) (h : RegisterType r = α) : α :=
  match s.regs.get? r with
  | some v => h ▸ v
  | none => d

def htifDone (s : MState) : Bool := regOr s Register.htif_done false rfl
def htifExitCode (s : MState) : BitVec 64 := regOr s Register.htif_exit_code 0 rfl
def outputRev (s : MState) : List (BitVec 8) := regOr s Register.zkvm_output_rev [] rfl

/-- Public output so far, in order. -/
def output (s : MState) : List UInt8 := (outputRev s).reverse.map (·.toNat.toUInt8)

/-- Step until HTIF signals completion, a step throws, or `fuel` steps have run. -/
def run : Nat → MState → Observation
  | fuel, s =>
    if htifDone s then ⟨decodeExit (htifExitCode s).toNat, output s⟩
    else match fuel with
      | 0 => ⟨.outOfFuel, output s⟩
      | n + 1 =>
        match step s with
        | .ok s' => run n s'
        | .error msg => ⟨.stuck msg, output s⟩

/-- Outcomes that end a run on the guest's behalf. -/
def Terminal : Outcome → Prop
  | .success => True
  | .failure _ => True
  | .fault => True
  | _ => False

end ZkvmRef

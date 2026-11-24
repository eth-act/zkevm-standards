/-
The reference machine state: the Sail-generated RISC-V model with the zkVM state of
reference/sail/zkvm/, and how Lean runs and inspects it.
-/
import LeanRV64DExecutable
-- The generated root module imports only what zkvm_step.sail (the last Sail file) depends on;
-- `init_model` and `reset` live in Model.
import LeanRV64DExecutable.Model
import LeanRV64DExecutable.ZkvmStep
-- The loader and machine initialisation, which zkvm_step.sail need not depend on.
import LeanRV64DExecutable.ZkvmInstall

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- State of the Sail-generated RV64 model. -/
abbrev MState := PreSail.SequentialState RegisterType Sail.trivialChoiceSource

/-- Run a model computation on a state; a thrown Sail error becomes `.error`. -/
def runM {α : Type} (m : SailM α) (s : MState) : Except String (α × MState) :=
  match m.run s with
  | .ok a s' => .ok (a, s')
  | .error e _ => .error e.print

/-- Initial values of the integer registers `x1`…`x31` (`x0` is always 0). The standards fix no
initial register state besides the PC, so the statements quantify over every choice. -/
abbrev Gprs := Fin 31 → BitVec 64

/-- All integer registers 0. -/
def Gprs.zero : Gprs := fun _ => 0

/-- A distinct nonzero pattern per register, to detect runs that depend on initial values. -/
def Gprs.canary : Gprs := fun i => 0xa5a5_a5a5_a5a5_a500 + BitVec.ofNat 64 (i.val + 1)

/-- The machine after Sail's model initialisation, with `x1`…`x31` set to `gprs`, before
anything is loaded. Registers without a Sail initialiser stay unset: in Sail their initial value
is unspecified, and the generated model throws when one is read, so a run that depends on one is
`stuck` instead of silently using an arbitrary value. `zkvm_reset` (Sail) gives the control
registers sail-riscv reads before writing them their zkVM values. -/
def initial (gprs : Gprs) : Except String MState :=
  (·.2) <$> runM (do
    sail_model_init ()
    for i in List.finRange 31 do
      wX (regno.Regno (i.val + 1)) (gprs i)) default

/-- `len` bytes at `a`, if all of them have been written. -/
def readMem (s : MState) (a len : Nat) : Option ByteArray :=
  (List.range len).foldlM (fun acc i => (s.mem.get? (a + i)).map (fun v => acc.push (UInt8.ofNat v.toNat))) .empty

/-- General-purpose register `i` (`x0` reads as 0). -/
def xreg (s : MState) (i : Fin 32) : BitVec 64 :=
  match runM (rX (regno.Regno i.val)) s with
  | .ok (v, _) => v
  | .error _ => 0

def pc (s : MState) : BitVec 64 :=
  match runM (readReg Register.PC) s with
  | .ok (v, _) => v
  | .error _ => 0

/-- Little-endian value of the `n` bytes at `a`, if all have been written. -/
def readLE (s : MState) (a n : Nat) : Option Nat :=
  (readMem s a n).map fun b => (List.range n).foldr (fun i acc => acc * 256 + (b.get! i).toNat) 0

/-- Value of register `r`, or `d` if it has none. -/
def regOr {α : Type} (s : MState) (r : Register) (d : α) (h : RegisterType r = α) : α :=
  match s.regs.get? r with
  | some v => h ▸ v
  | none => d

/-- How the run halted, if it has. -/
def haltOf (s : MState) : Option zkvm_outcome := regOr s Register.zkvm_halt none rfl

/-- Public output so far, most recent byte first. -/
def outputRev (s : MState) : List (BitVec 8) := regOr s Register.zkvm_output_rev [] rfl

/-- Public output so far, in order. -/
def output (s : MState) : List UInt8 := (outputRev s).reverse.map (·.toNat.toUInt8)

/-- Misaligned data accesses so far. -/
def misalignedCount (s : MState) : Nat := (regOr s Register.zkvm_misaligned_accesses 0 rfl).toNat

/-- Host-function symbol addresses installed by the loader. -/
def hostTable (s : MState) : List zkvm_host_binding := regOr s Register.zkvm_host_table [] rfl

/-- Current PMA regions of the machine. -/
def pmaRegions (s : MState) : List PMA_Region := regOr s Register.pma_regions [] rfl

/-- `a ∈ [base, base + len)`. -/
def InRange (base len a : Nat) : Prop := base ≤ a ∧ a < base + len

end ZkvmRef

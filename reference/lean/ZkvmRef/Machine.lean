/-
The reference machine state: the Sail-generated RISC-V model with the zkVM state of
reference/sail/zkvm/.
-/
import LeanRV64DExecutable
-- The generated root module imports only what zkvm_host.sail (the last Sail file) depends on;
-- `init_model` and `reset` live in Model, `zkvm_reset` and `zkvm_step` in ZkvmStep.
import LeanRV64DExecutable.Model
import LeanRV64DExecutable.ZkvmStep
import ZkvmRef.RegisterDefaults

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- State of the Sail-generated RV64 model. -/
abbrev MState := PreSail.SequentialState RegisterType Sail.trivialChoiceSource

/-- Run a model computation on a state; a thrown Sail error becomes `.error`. -/
def runM {α : Type} (m : SailM α) (s : MState) : Except String (α × MState) :=
  match m.run s with
  | .ok a s' => .ok (a, s')
  | .error e _ => .error e.print

/-- Give every register that has no value yet its zero value. The generated model only stores
registers that have a Sail initialiser or have been written; Sail leaves the initial value of the
others unspecified, but sail-riscv reads some of them before writing them (`init_model` throws
without them). Zero is the value sail-riscv's C emulator uses. -/
def fillRegisters : SailM Unit :=
  modify fun s =>
    let regs := allRegisters.foldl
      (fun m r => if m.contains r then m else m.insert r (registerDefault r)) s.regs
    { s with regs }

/-- The machine after Sail's model initialisation, before anything is loaded. -/
def initial : Except String MState :=
  (·.2) <$> runM (do sail_model_init (); fillRegisters) default

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

end ZkvmRef

/-
The reference machine state: the Sail-generated RISC-V model, initialised from a loaded image.
-/
import LeanRV64DExecutable
import ZkvmRef.Loader
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

/-- The generated PMA region for a loader region (same attributes as `toSailRegion`). -/
def toPmaRegion (r : Region) : PMA_Region :=
  let main := r.perm == .rw
  let (readable, writable, executable) := match r.perm with
    | .r => (true, false, false)
    | .rw => (true, true, false)
    | .x => (false, false, true)
    | .rx => (true, false, true)
    | .io => (true, true, false)
  { base := BitVec.ofNat 64 r.base
    size := BitVec.ofNat 64 r.size
    attributes := {
      mem_type := if main then .MainMemory else .IOMemory
      cacheable := true
      coherent := main
      executable, readable, writable
      read_idempotent := true
      write_idempotent := true
      misaligned_exceptions := { load_store := none, vector := none, amo := .AccessFault }
      atomic_support := .AMONone
      reservability := .RsrvNone
      supports_cbo_zero := false
      supports_pte_read := false
      supports_pte_write := false }
    include_in_device_tree := false }

/-- Write `bytes` to memory starting at `addr`. -/
def writeBytesAt (addr : Nat) (bytes : ByteArray) : SailM Unit := do
  for i in [0:bytes.size] do
    writeByte (addr + i) (bytes.get! i).toBitVec

/-- Give every register that has no value yet its zero value. The generated model only
stores registers that have a Sail initialiser or have been written; the C++ emulator starts
the others at zero. -/
def fillRegisters : SailM Unit :=
  modify fun s =>
    let regs := allRegisters.foldl
      (fun m r => if m.contains r then m else m.insert r (registerDefault r)) s.regs
    { s with regs }

/-- The state in which a loaded image starts executing, with `input` in the input region. -/
def initialState (p : Profile) (img : Image) (input : ByteArray) : Except String MState := do
  let m : SailM Unit := do
    sail_model_init ()
    fillRegisters
    set_pc_reset_address (BitVec.ofNat 64 img.elf.entry.toNat)
    if let some tohost := img.elf.symbol? "tohost" then
      enable_htif tohost.toBitVec
    writeReg Register.pma_regions (img.regions.map toPmaRegion)
    init_model ""
    init_boot_requirements ()
    writeReg Register.mtvec (Mk_Mtvec (BitVec.ofNat 64 p.trapVector))
    for (addr, bytes) in img.segments do
      writeBytesAt addr bytes
    writeBytesAt p.input.base (inputBlob input)
  return (← runM m default).2

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

end ZkvmRef

/-
The loader, as the Lean side calls it. ELF parsing and validation are Sail's `zkvm_validate`
(reference/sail/zkvm/zkvm_loader.sail); installing the image and the input are Sail's
`zkvm_install` and `zkvm_provide_input` (zkvm_install.sail). This file passes the file bytes in
and maps the results.
-/
import ZkvmRef.MemoryProfile
import ZkvmRef.Machine

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- File bytes as the Sail byte vector. -/
def byteVector (b : ByteArray) : Vector (BitVec 8) b.size :=
  ⟨b.data.map (·.toBitVec), Array.size_map ..⟩

/-- A validated program: its parsed ELF and its memory map (Sail's `zkvm_image`). -/
abbrev Image := zkvm_image

/-- Validate an ELF against a profile (Sail's `zkvm_validate`): the image, or the first failing
check's message. -/
def validate (p : MemoryProfile) (bytes : ByteArray) : Except String Image :=
  match zkvm_validate p (byteVector bytes) with
  | .Ok img => .ok img
  | .Err m => .error m

/-- Install a validated image with Sail's `zkvm_install`. -/
def install (p : MemoryProfile) (img : Image) (bytes : ByteArray) (m : MState) :
    Except String MState :=
  (·.2) <$> runM (zkvm_install p img (byteVector bytes)) m

/-- Validate `bytes` under `p` and install it in `m`. -/
def load (p : MemoryProfile) (bytes : ByteArray) (m : MState) : Except String MState := do
  install p (← validate p bytes) bytes m

/-- Place the private input with Sail's `zkvm_provide_input`. -/
def provideInput (input : ByteArray) (m : MState) : Except String MState := do
  let (fits, s) ← runM (zkvm_provide_input (byteVector input)) m
  if fits then return s else throw "input larger than the input region"

/-- The machine ready to run `elf` under `p` on `input`, with integer registers `x1`…`x31`
initially `gprs` (the standards leave them unspecified). -/
def boot (p : MemoryProfile) (elf input : ByteArray) (gprs : Gprs) : Except String MState := do
  provideInput input (← load p elf (← initial gprs))

end ZkvmRef

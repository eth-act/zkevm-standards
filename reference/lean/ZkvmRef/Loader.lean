/-
ELF loading and validation (standards/elf-loading-and-validation) against a profile, and the
loader: validation followed by installing the image, the host-function bindings and the input
in the reference machine.
-/
import Std.Data.HashMap
import ZkvmRef.Elf
import ZkvmRef.MemoryProfile
import ZkvmRef.Machine

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- Permission of a memory region. -/
inductive Perm
  | r
  | rw
  | x
  | rx
  deriving Repr, DecidableEq, Inhabited

structure Region where
  base : Nat
  size : Nat
  perm : Perm
  deriving Repr, DecidableEq, Inhabited

/-- A validated program: its ELF, the memory map, and the bytes to place at each `PT_LOAD` vaddr. -/
structure Image where
  elf : Elf
  regions : List Region
  segments : List (Nat × ByteArray)

/-- `0x` followed by lowercase hex digits. -/
def hex (n : Nat) : String := "0x" ++ String.ofList (Nat.toDigits 16 n)

def pageSize : Nat := 0x1000

namespace Loader

def PT_LOAD : UInt32 := 1
def PF_X : UInt32 := 1
def PF_W : UInt32 := 2
def PF_R : UInt32 := 4

/-- Who last painted a page during loading. -/
inductive Painter
  | input
  | ram
  | stack
  | segment
  deriving DecidableEq

/-- Permission given to a page holding a segment with these flags. -/
def segPerm (flags : UInt32) : Perm :=
  if flags &&& PF_X != 0 then
    if flags &&& PF_R != 0 then .rx else .x
  else if flags &&& PF_W != 0 then .rw
  else .r

def isExec (ph : Phdr) : Bool := ph.flags &&& PF_X != 0

def segContains (ph : Phdr) (a : Nat) : Bool :=
  ph.vaddr.toNat ≤ a && a < ph.vaddr.toNat + ph.memsz.toNat

/-- Pages `[base / 4K, ceil((base + size) / 4K))` touched by a non-empty range. -/
def pagesOf (base size : Nat) : List Nat :=
  if size = 0 then [] else
  let first := base / pageSize
  let last := (base + size - 1) / pageSize
  List.range' first (last + 1 - first)

abbrev PageMap := Std.HashMap Nat (Perm × Painter)

def paint (m : PageMap) (r : Range) (perm : Perm) (who : Painter) : PageMap :=
  (pagesOf r.base r.size).foldl (fun m pg => m.insert pg (perm, who)) m

/-- Merge sorted `(page, perm)` pairs into maximal runs of adjacent equal-permission pages. -/
def runs (pages : List (Nat × Perm)) : List Region :=
  let step := fun (acc : List Region) ((pg, perm) : Nat × Perm) =>
    match acc with
    | r :: rs =>
      if r.perm = perm ∧ r.base + r.size = pg * pageSize then
        { r with size := r.size + pageSize } :: rs
      else ⟨pg * pageSize, pageSize, perm⟩ :: acc
    | [] => [⟨pg * pageSize, pageSize, perm⟩]
  (pages.foldl step []).reverse

/-- First pair `(a, b)` with `a` before `b` in the list satisfying `f`. -/
def firstPair {α : Type} (f : α → α → Bool) : List α → Option (α × α)
  | [] => none
  | a :: rest =>
    match rest.find? (f a) with
    | some b => some (a, b)
    | none => firstPair f rest

end Loader

open Loader in
/-- Validate an ELF against a profile and build its memory image. The checks run in a
fixed order; the first failure is reported. -/
def validate (p : MemoryProfile) (bytes : ByteArray) : Except String Image := do
  let b := bytes
  let byte := fun (i : Nat) => b.get! i
  unless b.size ≥ 64 && byte 0 == 0x7f && byte 1 == 0x45 && byte 2 == 0x4c && byte 3 == 0x46 do
    throw "bad magic"
  unless byte 4 == 2 do throw "class is not ELFCLASS64"
  unless byte 5 == 1 do throw "not ELFDATA2LSB"
  unless (← Elf.le b 18 2) == 243 do throw "e_machine is not EM_RISCV"
  unless (← Elf.le b 16 2) == 2 do throw "e_type is not ET_EXEC"
  let phoff ← Elf.le b 32 8
  let phentsize ← Elf.le b 54 2
  let phnum ← Elf.le b 56 2
  unless phentsize == 56 && phoff + phnum * 56 ≤ b.size do
    throw "program headers outside the file"
  let elf ← Elf.parse b
  let loads := elf.phdrs.toList.filter (·.ptype == PT_LOAD)
  -- Per-segment checks, in program-header order.
  for ph in loads do
    let v := ph.vaddr.toNat
    let h := hex v
    unless ph.filesz ≤ ph.memsz do throw s!"segment {h}: p_filesz > p_memsz"
    unless ph.offset.toNat + ph.filesz.toNat ≤ b.size do
      throw s!"segment {h}: file data outside the file"
    unless ph.paddr == ph.vaddr do throw s!"segment {h}: p_paddr differs from p_vaddr"
    unless v % 4 == 0 do throw s!"segment {h}: p_vaddr not 4-byte aligned"
    unless p.addressSpace.contains v ph.memsz.toNat do
      throw s!"segment {h}: outside the addressable space"
    if ph.flags &&& PF_W != 0 && ph.flags &&& PF_X != 0 then
      throw s!"segment {h}: W^X violated"
    if isExec ph then
      let want := match p.execPerm with
        | .x => PF_X
        | .rx => PF_X ||| PF_R
      unless ph.flags &&& (PF_X ||| PF_R) == want do
        throw s!"segment {h}: executable flags do not match profile"
  -- Overlap of non-empty segments, lower vaddr first.
  let nonEmpty := (loads.filter (·.memsz != 0)).mergeSort (fun a c => a.vaddr ≤ c.vaddr)
  let overlaps := fun (a c : Phdr) => decide (c.vaddr.toNat < a.vaddr.toNat + a.memsz.toNat)
  if let some (a, c) := firstPair overlaps nonEmpty then
    throw s!"segments {hex a.vaddr.toNat} and {hex c.vaddr.toNat} overlap"
  -- Entry point.
  let entry := elf.entry.toNat
  unless entry % 4 == 0 do throw "e_entry not 4-byte aligned"
  let execs := loads.filter isExec
  unless execs.any (segContains · entry) do throw "e_entry not inside an executable segment"
  if let some boot := p.bootAddr then
    unless entry == boot do throw "e_entry differs from the fixed boot address"
  -- Paint pages.
  let mut pages : PageMap := {}
  pages := paint pages p.input .r .input
  pages := paint pages p.ram .rw .ram
  pages := paint pages p.stack .rw .stack
  for ph in loads do
    if ph.memsz == 0 then continue
    let perm := segPerm ph.flags
    for pg in pagesOf ph.vaddr.toNat ph.memsz.toNat do
      match pages.get? pg with
      | some (_, .ram) => pages := pages.insert pg (perm, .segment)
      | some (q, .segment) =>
        unless q == perm do
          throw s!"page {hex (pg * pageSize)} shared by segments with different permissions"
      | _ => throw s!"segment page {hex (pg * pageSize)} outside ram"
  let mapped := pages.toList.map (·.1)
  if mapped.any (fun pg => nullPage.contains (pg * pageSize) pageSize) then
    throw "null page is mapped"
  if mapped.any (fun pg => p.guard.contains (pg * pageSize) pageSize) then
    throw "stack guard page is mapped"
  -- Symbols the loader binds: the library entry point and I/O functions, and `main`.
  for n in ["_start", "main", "read_input", "write_output"] do
    if elf.symbol? n = none then throw s!"missing symbol {n}"
  let sorted := (pages.toList.map (fun (pg, perm, _) => (pg, perm))).mergeSort
    (fun a c => a.1 ≤ c.1)
  let regions := runs sorted
  let segments := loads.map (fun ph => (ph.vaddr.toNat, Elf.segmentBytes b ph))
  return { elf, regions, segments }

/-- The generated PMA region for a loader region. Only read-write regions are main memory. -/
def toPmaRegion (r : Region) : PMA_Region :=
  let main := r.perm == .rw
  let (readable, writable, executable) := match r.perm with
    | .r => (true, false, false)
    | .rw => (true, true, false)
    | .x => (false, false, true)
    | .rx => (true, false, true)
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

/-- Install a validated image: memory map, PC at the entry point, segment contents (file
bytes, then zeros up to `p_memsz`), the host-function bindings of the static library, and
what `_start` needs to call `main`. No other register state is standardized. -/
def install (p : MemoryProfile) (img : Image) (m : MState) : Except String MState := do
  let sym := fun (n : String) => (img.elf.symbol? n).map (fun v => BitVec.ofNat 64 v.toNat)
  let prog : SailM Unit := do
    writeReg Register.pma_regions (img.regions.map toPmaRegion)
    set_pc_reset_address (BitVec.ofNat 64 img.elf.entry.toNat)
    init_model ""
    zkvm_reset ()
    for (addr, bytes) in img.segments do
      writeBytesAt addr bytes
    writeReg Register.zkvm_host_table
      (zkvm_host_fns.filterMap fun f => (sym (zkvm_host_symbol f)).map ({ addr := ·, func := f }))
    writeReg Register.zkvm_main ((sym "main").getD 0)
    writeReg Register.zkvm_gp (sym "__global_pointer$")
    writeReg Register.zkvm_stack_top (BitVec.ofNat 64 (p.stack.base + p.stack.size))
    writeReg Register.zkvm_started false
  return (← runM prog m).2

/-- Validate `bytes` under `p` and install it in `m`. -/
def load (p : MemoryProfile) (bytes : ByteArray) (m : MState) : Except String MState := do
  install p (← validate p bytes) m

/-- Place the private input at the start of the input region and record its address and size
for `read_input`. -/
def provideInput (p : MemoryProfile) (input : ByteArray) (m : MState) : Except String MState := do
  if input.size > p.input.size then throw "input larger than the input region"
  let prog : SailM Unit := do
    writeBytesAt p.input.base input
    writeReg Register.zkvm_input_base (BitVec.ofNat 64 p.input.base)
    writeReg Register.zkvm_input_size (BitVec.ofNat 64 input.size)
  return (← runM prog m).2

/-- The machine ready to run `elf` under `p` on `input`. -/
def boot (p : MemoryProfile) (elf input : ByteArray) : Except String MState := do
  provideInput p input (← load p elf (← initial))

end ZkvmRef

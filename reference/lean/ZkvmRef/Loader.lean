/-
ELF loading and validation (standards/elf-loading-and-validation) against the zkVM's memory
profile. `validate` decides which ELFs are accepted and computes what to install; Sail's
`zkvm_install` and `zkvm_provide_input` (reference/sail/zkvm/zkvm_install.sail) put it into
machine state.
-/
import Std.Data.HashMap
import ZkvmRef.Elf
import ZkvmRef.MemoryProfile
import ZkvmRef.Machine

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- Permission of a memory region (Sail's `zkvm_perm`). -/
abbrev Perm := zkvm_perm

/-- A memory region (Sail's `zkvm_region`). -/
abbrev Region := zkvm_region

/-- A validated program: its ELF, the memory map, and the bytes to place at each `PT_LOAD` vaddr. -/
structure Image where
  elf : Elf
  regions : List Region
  segments : List (Nat × ByteArray)

/-- `0x` followed by lowercase hex digits. -/
def hex (n : Nat) : String := "0x" ++ String.ofList (Nat.toDigits 16 n)

/-- Granularity of memory permissions (Sail's `zkvm_page_size`). -/
def pageSize : Nat := zkvm_page_size.toNat

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
    if flags &&& PF_R != 0 then .ZKVM_PERM_RX else .ZKVM_PERM_X
  else if flags &&& PF_W != 0 then .ZKVM_PERM_RW
  else .ZKVM_PERM_R

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

def paint (m : PageMap) (r : zkvm_range) (perm : Perm) (who : Painter) : PageMap :=
  (pagesOf r.base.toNat r.size.toNat).foldl (fun m pg => m.insert pg (perm, who)) m

/-- Merge sorted `(page, perm)` pairs into maximal runs of adjacent equal-permission pages. -/
def runs (pages : List (Nat × Perm)) : List Region :=
  let step := fun (acc : List Region) ((pg, perm) : Nat × Perm) =>
    let fresh : Region := { base := BitVec.ofNat 64 (pg * pageSize), size := BitVec.ofNat 64 pageSize, perm }
    match acc with
    | r :: rs =>
      if r.perm == perm && r.base.toNat + r.size.toNat == pg * pageSize then
        { r with size := r.size + BitVec.ofNat 64 pageSize } :: rs
      else fresh :: acc
    | [] => [fresh]
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
    unless p.address_space.contains v ph.memsz.toNat do
      throw s!"segment {h}: outside the addressable space"
    if ph.flags &&& PF_W != 0 && ph.flags &&& PF_X != 0 then
      throw s!"segment {h}: W^X violated"
    if isExec ph then
      let want := match p.exec_perm with
        | .ZKVM_EXEC_X => PF_X
        | .ZKVM_EXEC_RX => PF_X ||| PF_R
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
  if let some boot := p.boot_addr then
    unless entry == boot.toNat do throw "e_entry differs from the fixed boot address"
  -- Paint pages.
  let mut pages : PageMap := {}
  pages := paint pages p.input .ZKVM_PERM_R .input
  pages := paint pages p.ram .ZKVM_PERM_RW .ram
  pages := paint pages p.stack .ZKVM_PERM_RW .stack
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
  if mapped.any (fun pg => zkvm_null_page.contains (pg * pageSize) pageSize) then
    throw "null page is mapped"
  if mapped.any (fun pg => (zkvm_stack_guard p).contains (pg * pageSize) pageSize) then
    throw "stack guard page is mapped"
  -- Symbols the loader binds: the library entry point and I/O functions (named by Sail's
  -- `zkvm_host_symbol`) and the guest's `main`.
  let sym := zkvm_host_symbol
  for n in [sym .ZKVM_START, "main", sym .ZKVM_READ_INPUT, sym .ZKVM_WRITE_OUTPUT] do
    if elf.symbol? n = none then throw s!"missing symbol {n}"
  let sorted := (pages.toList.map (fun (pg, perm, _) => (pg, perm))).mergeSort
    (fun a c => a.1 ≤ c.1)
  let regions := runs sorted
  let segments := loads.map (fun ph => (ph.vaddr.toNat, Elf.segmentBytes b ph))
  return { elf, regions, segments }

/-- The bytes of a `ByteArray` as Sail bytes. -/
def sailBytes (b : ByteArray) : List (BitVec 8) := b.toList.map (·.toBitVec)

/-- Install a validated image with Sail's `zkvm_install`. -/
def install (p : MemoryProfile) (img : Image) (m : MState) : Except String MState := do
  let sym := fun (n : String) => (img.elf.symbol? n).map (fun v => BitVec.ofNat 64 v.toNat)
  let segments := img.segments.map fun (a, bs) =>
    ({ vaddr := BitVec.ofNat 64 a, bytes := sailBytes bs } : zkvm_segment)
  let table := zkvm_host_fns.filterMap fun f =>
    (sym (zkvm_host_symbol f)).map ({ addr := ·, func := f } : BitVec 64 → zkvm_host_binding)
  let prog := zkvm_install p img.regions segments (BitVec.ofNat 64 img.elf.entry.toNat) table
    ((sym "main").getD 0) (sym "__global_pointer$")
  return (← runM prog m).2

/-- Validate `bytes` under `p` and install it in `m`. -/
def load (p : MemoryProfile) (bytes : ByteArray) (m : MState) : Except String MState := do
  install p (← validate p bytes) m

/-- Place the private input with Sail's `zkvm_provide_input`. -/
def provideInput (input : ByteArray) (m : MState) : Except String MState := do
  let (fits, s) ← runM (zkvm_provide_input (sailBytes input)) m
  if fits then return s else throw "input larger than the input region"

/-- The machine ready to run `elf` under `p` on `input`, with integer registers `x1`…`x31`
initially `gprs` (the standards leave them unspecified). -/
def boot (p : MemoryProfile) (elf input : ByteArray) (gprs : Gprs) : Except String MState := do
  provideInput input (← load p elf (← initial gprs))

end ZkvmRef

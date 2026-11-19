/-
ELF loading and validation (standards/elf-loading-and-validation) against a profile.
-/
import Lean.Data.Json
import Std.Data.HashMap
import ZkvmRef.Elf
import ZkvmRef.Profile

namespace ZkvmRef

/-- Permission of a memory region. `io` is the zkVM I/O device page. -/
inductive Perm
  | r
  | rw
  | x
  | rx
  | io
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
def load (p : Profile) (bytes : ByteArray) : Except String Image := do
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
  -- Entry point and trap vector.
  let entry := elf.entry.toNat
  unless entry % 4 == 0 do throw "e_entry not 4-byte aligned"
  let execs := loads.filter isExec
  unless execs.any (segContains · entry) do throw "e_entry not inside an executable segment"
  if let some boot := p.bootAddr then
    unless entry == boot do throw "e_entry differs from the fixed boot address"
  unless execs.any (segContains · p.trapVector) do
    throw "trap vector not inside an executable segment"
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
  let sorted := (pages.toList.map (fun (pg, perm, _) => (pg, perm))).mergeSort
    (fun a c => a.1 ≤ c.1)
  let regions := (runs sorted ++ [Region.mk zkvmIoBase pageSize .io]).mergeSort
    (fun a c => a.base ≤ c.base)
  let segments := loads.map (fun ph => (ph.vaddr.toNat, Elf.segmentBytes b ph))
  return { elf, regions, segments }

open Lean

/-- A `bits(64)` configuration value. -/
def bits64Json (n : Nat) : Json := Json.mkObj [("len", 64), ("value", Json.str (hex n))]

/-- The sail-riscv `memory.regions` entry for a region. -/
def toSailRegion (r : Region) : Json :=
  let main := r.perm == .rw
  let (readable, writable, executable) := match r.perm with
    | .r => (true, false, false)
    | .rw => (true, true, false)
    | .x => (false, false, true)
    | .rx => (true, false, true)
    | .io => (true, true, false)
  let noneJ := Json.mkObj [("None", Json.null)]
  Json.mkObj [
    ("base", bits64Json r.base),
    ("size", bits64Json r.size),
    ("attributes", Json.mkObj [
      ("mem_type", Json.str (if main then "MainMemory" else "IOMemory")),
      ("cacheable", true),
      ("coherent", Json.bool main),
      ("executable", Json.bool executable),
      ("readable", Json.bool readable),
      ("writable", Json.bool writable),
      ("read_idempotent", true),
      ("write_idempotent", true),
      ("misaligned_exceptions", Json.mkObj [
        ("load_store", noneJ), ("vector", noneJ), ("amo", "AccessFault")]),
      ("atomic_support", "AMONone"),
      ("reservability", "RsrvNone"),
      ("supports_cbo_zero", false),
      ("supports_pte_read", false),
      ("supports_pte_write", false)]),
    ("include_in_device_tree", false)]

/-- Replace the value at a path of object keys. -/
partial def setPath (j : Json) : List String → Json → Json
  | [], v => v
  | k :: ks, v => j.setObjVal! k (setPath (j.getObjValD k) ks v)

/-- The sail-riscv configuration for running an image under a profile. -/
def sailConfig (base : Json) (p : Profile) (img : Image) : Json :=
  let j := setPath base ["memory", "regions"] (Json.arr (img.regions.map toSailRegion).toArray)
  setPath j ["base", "mtvec", "reset_value"] (Json.num p.trapVector)

/-- Little-endian encoding of `n` in `k` bytes. -/
def leBytes (n k : Nat) : ByteArray :=
  ⟨((List.range k).map (fun i => UInt8.ofNat (n / 256 ^ i % 256))).toArray⟩

/-- The contents of the input region: `u64 len ‖ input`. -/
def inputBlob (input : ByteArray) : ByteArray := leBytes input.size 8 ++ input

/-- A minimal ELF64 `ET_EXEC` with one `PF_R` `PT_LOAD` at the input region holding the input blob. -/
def inputElf (p : Profile) (input : ByteArray) : Except String ByteArray := do
  if input.size + 8 > p.input.size then throw "input larger than the input region"
  let blob := inputBlob input
  let ehdr :=
    ⟨#[0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]⟩ ++
    leBytes 2 2 ++ leBytes 243 2 ++ leBytes 1 4 ++   -- e_type, e_machine, e_version
    leBytes 0 8 ++ leBytes 64 8 ++ leBytes 0 8 ++    -- e_entry, e_phoff, e_shoff
    leBytes 0 4 ++ leBytes 64 2 ++ leBytes 56 2 ++   -- e_flags, e_ehsize, e_phentsize
    leBytes 1 2 ++ leBytes 0 2 ++ leBytes 0 2 ++ leBytes 0 2
  let phdr :=
    leBytes 1 4 ++ leBytes 4 4 ++ leBytes 120 8 ++   -- PT_LOAD, PF_R, p_offset
    leBytes p.input.base 8 ++ leBytes p.input.base 8 ++
    leBytes blob.size 8 ++ leBytes blob.size 8 ++ leBytes 8 8
  return ehdr ++ phdr ++ blob

end ZkvmRef

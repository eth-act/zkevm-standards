/-
ELF64 little-endian parser: header, program headers and (non-normative) symbols.
-/

namespace ZkvmRef

/-- An ELF64 program header. -/
structure Phdr where
  ptype : UInt32
  flags : UInt32
  offset : UInt64
  vaddr : UInt64
  paddr : UInt64
  filesz : UInt64
  memsz : UInt64
  deriving Repr, Inhabited, DecidableEq

/-- The parts of an ELF64 file that loading and running depend on. -/
structure Elf where
  entry : UInt64
  etype : UInt16
  machine : UInt16
  phdrs : Array Phdr
  /-- Symbols of the first `SHT_SYMTAB`; non-normative (used by contracts and tests). -/
  symbols : Array (String × UInt64)
  deriving Inhabited

namespace Elf

/-- Little-endian unsigned integer of `n` bytes at offset `o`. -/
def le (b : ByteArray) (o n : Nat) : Except String Nat :=
  if o + n ≤ b.size then
    .ok <| (List.range n).foldr (fun i acc => acc * 256 + (b.get! (o + i)).toNat) 0
  else
    .error s!"read of {n} bytes at offset {o} is outside the file"

def u16 (b : ByteArray) (o : Nat) : Except String UInt16 := UInt16.ofNat <$> le b o 2
def u32 (b : ByteArray) (o : Nat) : Except String UInt32 := UInt32.ofNat <$> le b o 4
def u64 (b : ByteArray) (o : Nat) : Except String UInt64 := UInt64.ofNat <$> le b o 8

/-- Program header at file offset `o`. -/
def parsePhdr (b : ByteArray) (o : Nat) : Except String Phdr := do
  return {
    ptype := ← u32 b o
    flags := ← u32 b (o + 4)
    offset := ← u64 b (o + 8)
    vaddr := ← u64 b (o + 16)
    paddr := ← u64 b (o + 24)
    filesz := ← u64 b (o + 32)
    memsz := ← u64 b (o + 40)
  }

/-- NUL-terminated string starting at offset `o`. -/
def cstring (b : ByteArray) (o : Nat) : String := Id.run do
  let mut e := o
  while e < b.size && b.get! e != 0 do
    e := e + 1
  return (String.fromUTF8? (b.extract o e)).getD ""

/-- Named symbols of the first `SHT_SYMTAB` section with its linked string table. -/
def parseSymbols (b : ByteArray) : Except String (Array (String × UInt64)) := do
  let shoff ← le b 40 8
  let shentsize ← le b 58 2
  let shnum ← le b 60 2
  if shoff == 0 || shnum == 0 || shentsize != 64 then return #[]
  let sec := fun (i : Nat) => shoff + i * shentsize
  let some symtab := (List.range shnum).find? (fun i => (le b (sec i + 4) 4).toOption == some 2)
    | return #[]
  let sh := sec symtab
  let link ← le b (sh + 40) 4
  let off ← le b (sh + 24) 8
  let size ← le b (sh + 32) 8
  let strOff ← le b (sec link + 24) 8
  let mut syms := #[]
  for i in List.range (size / 24) do
    let e := off + i * 24
    let name ← le b e 4
    let value ← u64 b (e + 8)
    let s := cstring b (strOff + name)
    if s != "" then syms := syms.push (s, value)
  return syms

/-- Parse an ELF64 file whose identification bytes have already been checked. -/
def parse (b : ByteArray) : Except String Elf := do
  let etype ← u16 b 16
  let machine ← u16 b 18
  let entry ← u64 b 24
  let phoff ← le b 32 8
  let phentsize ← le b 54 2
  let phnum ← le b 56 2
  if phentsize != 56 then throw "program headers outside the file"
  let phdrs ← (List.range phnum).toArray.mapM (fun i => parsePhdr b (phoff + i * 56))
  let symbols := (parseSymbols b).toOption.getD #[]
  return { entry, etype, machine, phdrs, symbols }

/-- Memory image of a segment: its file bytes followed by `memsz - filesz` zero bytes. -/
def segmentBytes (b : ByteArray) (ph : Phdr) : ByteArray :=
  let off := ph.offset.toNat
  b.extract off (off + ph.filesz.toNat) ++ ⟨Array.replicate (ph.memsz.toNat - ph.filesz.toNat) 0⟩

/-- Value of a symbol, if present. -/
def symbol? (e : Elf) (name : String) : Option UInt64 :=
  (e.symbols.find? (·.1 == name)).map (·.2)

end Elf
end ZkvmRef

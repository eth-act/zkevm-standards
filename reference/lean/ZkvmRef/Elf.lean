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

/-- An ELF64 file as the loader sees it. Omitted, because no standard depends on them:
`e_ident` beyond magic, class and data encoding (checked on the raw bytes by
`ZkvmRef.validate`), `e_version`, `e_flags` (left unchecked by the ELF standard), section
headers other than the symbol table, and each symbol's size, type, binding and section. -/
structure Elf where
  entry : UInt64
  etype : UInt16
  machine : UInt16
  phdrs : Array Phdr
  /-- Named symbols of the first `SHT_SYMTAB`; non-normative (used by contracts and tests). -/
  symbols : Array (String × UInt64)
  deriving Inhabited

namespace Elf

/-- Size in bytes of an ELF64 program header, section header and symbol table entry. -/
def phdrSize : Nat := 56
def shdrSize : Nat := 64
def symSize : Nat := 24

def SHT_SYMTAB : Nat := 2

/-- The unsigned integer stored little-endian (`ELFDATA2LSB`) in the `n` bytes
`b[o], …, b[o + n - 1]`, as a `Nat`: `b[o] + 256 * b[o + 1] + … + 256^(n-1) * b[o + n - 1]`.
Every multi-byte ELF field is read through this function, so a field that extends past the end
of the file is an `.error` naming the offset and width, never a silent zero. -/
def le (b : ByteArray) (o n : Nat) : Except String Nat :=
  if o + n ≤ b.size then
    .ok <| (List.range n).foldr (fun i acc => acc * 256 + (b.get! (o + i)).toNat) 0
  else
    .error s!"read of {n} bytes at offset {o} is outside the file"

def u16 (b : ByteArray) (o : Nat) : Except String UInt16 := UInt16.ofNat <$> le b o 2
def u32 (b : ByteArray) (o : Nat) : Except String UInt32 := UInt32.ofNat <$> le b o 4
def u64 (b : ByteArray) (o : Nat) : Except String UInt64 := UInt64.ofNat <$> le b o 8

/-- Program header at file offset `o` (`Elf64_Phdr`). -/
def parsePhdr (b : ByteArray) (o : Nat) : Except String Phdr :=
  return {
    ptype := ← u32 b o
    flags := ← u32 b (o + 4)
    offset := ← u64 b (o + 8)
    vaddr := ← u64 b (o + 16)
    paddr := ← u64 b (o + 24)
    filesz := ← u64 b (o + 32)
    memsz := ← u64 b (o + 40)
  }

/-- NUL-terminated UTF-8 string starting at offset `o` (empty if not valid UTF-8). -/
def cstring (b : ByteArray) (o : Nat) : String :=
  let bytes := (b.extract o b.size).toList.takeWhile (· ≠ 0)
  (String.fromUTF8? ⟨bytes.toArray⟩).getD ""

/-- Named symbols of the first `SHT_SYMTAB` section, resolved through its linked string table.
No section headers, or no symbol table, gives no symbols. -/
def parseSymbols (b : ByteArray) : Except String (Array (String × UInt64)) := do
  let shoff ← le b 40 8
  let shentsize ← le b 58 2
  let shnum ← le b 60 2
  if shoff == 0 || shnum == 0 || shentsize != shdrSize then return #[]
  let shdr := fun (i : Nat) => shoff + i * shdrSize
  let isSymtab := fun (i : Nat) => (le b (shdr i + 4) 4).toOption == some SHT_SYMTAB
  let some symtab := (List.range shnum).find? isSymtab | return #[]
  let off ← le b (shdr symtab + 24) 8
  let size ← le b (shdr symtab + 32) 8
  let strtab ← le b (shdr (← le b (shdr symtab + 40) 4) + 24) 8
  let sym := fun (i : Nat) => do
    let e := off + i * symSize
    return (cstring b (strtab + (← le b e 4)), ← u64 b (e + 8))
  let syms ← (List.range (size / symSize)).mapM sym
  return (syms.filter (·.1 != "")).toArray

/-- Parse an ELF64 file whose identification bytes have already been checked. -/
def parse (b : ByteArray) : Except String Elf := do
  let phoff ← le b 32 8
  let phnum ← le b 56 2
  if (← le b 54 2) != phdrSize then throw "program headers outside the file"
  return {
    etype := ← u16 b 16
    machine := ← u16 b 18
    entry := ← u64 b 24
    phdrs := ← (List.range phnum).toArray.mapM fun i => parsePhdr b (phoff + i * phdrSize)
    symbols := (parseSymbols b).toOption.getD #[]
  }

/-- Memory image of a segment: its file bytes followed by `memsz - filesz` zero bytes. -/
def segmentBytes (b : ByteArray) (ph : Phdr) : ByteArray :=
  let off := ph.offset.toNat
  b.extract off (off + ph.filesz.toNat) ++ ⟨Array.replicate (ph.memsz.toNat - ph.filesz.toNat) 0⟩

/-- Value of a symbol, if present. -/
def symbol? (e : Elf) (name : String) : Option UInt64 :=
  (e.symbols.find? (·.1 == name)).map (·.2)

end Elf
end ZkvmRef

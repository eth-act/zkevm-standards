/-
Properties the loader must establish (standards/elf-loading-and-validation,
standards/memory-layout-restrictions, standards/memory-safety-guard-regions), stated over the
machine state `load` produces. Definitions only; nothing here is proved.
-/
import ZkvmRef.Loader
import ZkvmRef.StaticLibrary

open LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- The memory image of a segment: its `p_filesz` file bytes followed by `p_memsz - p_filesz`
zero bytes. -/
def segmentBytes (b : ByteArray) (ph : zkvm_phdr) : ByteArray :=
  let off := ph.offset.toNat
  b.extract off (off + ph.filesz.toNat) ++ ⟨Array.replicate (ph.memsz.toNat - ph.filesz.toNat) 0⟩

/-- Every non-empty `PT_LOAD` segment is in memory at `p_vaddr`: its file bytes followed by
`p_memsz - p_filesz` zeros (bss zeroing). [ELF11][ELF12][ELF28] -/
def SegmentsLoaded (bytes : ByteArray) (img : Image) (s : MState) : Prop :=
  ∀ ph ∈ img.elf.phdrs, ph.ptype = ZKVM_PT_LOAD → ph.memsz ≠ 0 →
    readMem s ph.vaddr.toNat ph.memsz.toNat = some (segmentBytes bytes ph)

/-- Execution starts at `e_entry`. -/
def PcAtEntry (img : Image) (s : MState) : Prop := pc s = BitVec.ofInt 64 img.elf.entry

/-- No memory region contains a byte of the null page or of the stack guard page. [GUA3][GUA8] -/
def GuardsUnmapped (p : MemoryProfile) (s : MState) : Prop :=
  ∀ r ∈ pmaRegions s, ∀ x,
    (InRange zkvm_null_page.base.toNat zkvm_null_page.size.toNat x ∨
      InRange (zkvm_stack_guard p).base.toNat (zkvm_stack_guard p).size.toNat x) →
      ¬ InRange r.base.toNat r.size.toNat x

/-- No memory region is both writable and executable. [ELF17] -/
def WXRespected (s : MState) : Prop :=
  ∀ r ∈ pmaRegions s, ¬ (r.attributes.writable = true ∧ r.attributes.executable = true)

/-- Executable memory is readable exactly under a read+execute profile. [ELF21][ELF22] -/
def ExecMatchesProfile (p : MemoryProfile) (s : MState) : Prop :=
  ∀ r ∈ pmaRegions s, r.attributes.executable = true →
    (r.attributes.readable = true ↔ p.exec_perm = .ZKVM_EXEC_RX)

/-- Whenever the loader accepts an ELF, the resulting machine satisfies all of the above. -/
def LoaderCorrect (p : MemoryProfile) : Prop :=
  ∀ bytes m s img, validate p bytes = .ok img → load p bytes m = .ok s →
    SegmentsLoaded bytes img s ∧ PcAtEntry img s ∧ GuardsUnmapped p s ∧ WXRespected s ∧
      ExecMatchesProfile p s

end ZkvmRef

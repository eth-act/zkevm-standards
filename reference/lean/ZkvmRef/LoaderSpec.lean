/-
Properties the loader must establish (standards/elf-loading-and-validation,
standards/memory-layout-restrictions, standards/memory-safety-guard-regions), stated over the
machine state `load` produces. Definitions only; nothing here is proved.
-/
import ZkvmRef.Loader
import ZkvmRef.StaticLibrary

open LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- Every non-empty `PT_LOAD` segment is in memory at `p_vaddr`: its file bytes followed by
`p_memsz - p_filesz` zeros (bss zeroing). -/
def SegmentsLoaded (bytes : ByteArray) (elf : Elf) (s : MState) : Prop :=
  ∀ ph ∈ elf.phdrs.toList, ph.ptype = Loader.PT_LOAD → ph.memsz ≠ 0 →
    readMem s ph.vaddr.toNat ph.memsz.toNat = some (Elf.segmentBytes bytes ph)

/-- Execution starts at `e_entry`. -/
def PcAtEntry (elf : Elf) (s : MState) : Prop := pc s = BitVec.ofNat 64 elf.entry.toNat

/-- No memory region contains a byte of the null page or of the stack guard page. -/
def GuardsUnmapped (p : MemoryProfile) (s : MState) : Prop :=
  ∀ r ∈ pmaRegions s, ∀ x,
    (InRange zkvm_null_page.base.toNat zkvm_null_page.size.toNat x ∨
      InRange (zkvm_stack_guard p).base.toNat (zkvm_stack_guard p).size.toNat x) →
      ¬ InRange r.base.toNat r.size.toNat x

/-- No memory region is both writable and executable. -/
def WXRespected (s : MState) : Prop :=
  ∀ r ∈ pmaRegions s, ¬ (r.attributes.writable = true ∧ r.attributes.executable = true)

/-- Executable memory is readable exactly under a read+execute profile. -/
def ExecMatchesProfile (p : MemoryProfile) (s : MState) : Prop :=
  ∀ r ∈ pmaRegions s, r.attributes.executable = true →
    (r.attributes.readable = true ↔ p.exec_perm = .ZKVM_EXEC_RX)

/-- Whenever the loader accepts an ELF, the resulting machine satisfies all of the above. -/
def LoaderCorrect (p : MemoryProfile) : Prop :=
  ∀ bytes m s elf, load p bytes m = .ok s → Elf.parse bytes = .ok elf →
    SegmentsLoaded bytes elf s ∧ PcAtEntry elf s ∧ GuardsUnmapped p s ∧ WXRespected s ∧
      ExecMatchesProfile p s

end ZkvmRef

/-
The zkVM static library (standards/static-library-and-linker-script, standards/io-interface,
standards/accelerated-memory-operations, standards/c-interface-accelerators): which symbols an
ELF must export, and when real library code implements a host function of the reference
machine. Definitions only; nothing here is proved.
-/
import ZkvmRef.Elf
import ZkvmRef.Run

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- The ELF's symbol table defines `name`. -/
def Exports (elf : Elf) (name : String) : Prop := ∃ v, elf.symbol? name = some v

/-- Symbols the static library must export: the entry point, the I/O functions and every
accelerator. -/
def requiredExports : List String :=
  ["_start", "read_input", "write_output"] ++
    ((zkvm_host_fns.filter zkvm_host_is_accelerator).map zkvm_host_symbol)

/-- Symbols the linker script must define. -/
def linkerScriptSymbols : List String := ["_heap_start", "_heap_end"]

/-- Symbols the static library may export (accelerated memory operations). -/
def optionalExports : List String := ["memcpy", "memmove", "memset", "memcmp"]

/-- A linked guest carries a conforming static library and linker script: all required
symbols are defined and the ELF entry point is `_start`. -/
def StaticLibraryConforms (elf : Elf) : Prop :=
  (∀ n ∈ requiredExports ++ linkerScriptSymbols, Exports elf n) ∧
    elf.symbol? "_start" = some elf.entry

/-- Exactly `n` steps, if each of them is an ordinary step. -/
def stepN : Nat → MState → Option MState
  | 0, s => some s
  | n + 1, s =>
    match step s with
    | .next s' => stepN n s'
    | _ => none

/-- Running from `s` first reaches the return address `ra` of `s` in state `s'`. -/
def CallReturns (s s' : MState) : Prop :=
  ∃ n, stepN n s = some s' ∧ pc s' = xreg s 1 ∧
    ∀ m < n, ∀ t, stepN m s = some t → pc t ≠ xreg s 1

/-- Callee-saved registers of the RISC-V psABI: `sp`, `gp`, `tp`, `s0`–`s11`. -/
def calleeSavedRegs : List (Fin 32) := [2, 3, 4, 8, 9, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]

def CalleeSaved (s s' : MState) : Prop :=
  ∀ i ∈ calleeSavedRegs, xreg s' i = xreg s i

/-- Bytes of stack below `sp` a library function may use. -/
def stackReserve : Nat := 1024

/-- `a ∈ [base, base + len)`. -/
def InRange (base len a : Nat) : Prop := base ≤ a ∧ a < base + len

def Disjoint (a la b lb : Nat) : Prop := a + la ≤ b ∨ b + lb ≤ a

/-- Every byte of `[a, a + len)` lies in a region with the given attribute. -/
def Covered (attr : PMA → Bool) (s : MState) (a len : Nat) : Prop :=
  ∀ x, InRange a len x → ∃ r ∈ pmaRegions s, attr r.attributes = true ∧
    InRange r.base.toNat r.size.toNat x

def Readable (s : MState) (a len : Nat) : Prop :=
  Covered (·.readable) s a len ∧ (readMem s a len).isSome

def Writable (s : MState) (a len : Nat) : Prop := Covered (·.writable) s a len

/-- The stack has `stackReserve` writable bytes below `sp`. -/
def StackOk (s : MState) : Prop :=
  stackReserve ≤ (xreg s 2).toNat ∧ Writable s ((xreg s 2).toNat - stackReserve) stackReserve

/-- A call is about to start at `entry` with a usable stack. -/
def AtEntry (s : MState) (entry : Nat) : Prop := pc s = BitVec.ofNat 64 entry ∧ StackOk s

/-- `s` with no host-function bindings: the code at every symbol runs as instructions. -/
def native (s : MState) : MState :=
  { s with regs := s.regs.insert Register.zkvm_host_table ([] : List zkvm_host_binding) }

/-- The library code at `entry` implements host function `f`: from any call of it, running
the code natively returns to `ra` with the callee-saved registers, `a0`, the public output and
all memory outside the stack reserve as the host function leaves them, and faults whenever the
host function faults. `a0` must equal the reference value exactly (for `memcmp`, -1, 0 or 1).

Meaningful for functions that return to `ra` and are implementable in RV64IM: the memory
operations. The I/O functions additionally need a vendor I/O mechanism, which this machine does
not have. Not for `_start` (it does not return) or accelerators (unspecified semantics). -/
def ImplementsHost (f : zkvm_host_fn) (entry : Nat) : Prop :=
  ∀ s s', AtEntry s entry → Host.exec f s = .next s' →
    (haltOf s' = none →
      ∃ t, CallReturns (native s) t ∧ CalleeSaved s t ∧ xreg t 10 = xreg s' 10 ∧
        outputRev t = outputRev s' ∧
        ∀ x, ¬ InRange ((xreg s 2).toNat - stackReserve) stackReserve x →
          t.mem.get? x = s'.mem.get? x) ∧
    (haltOf s' = some (.ZKVM_Fault ()) → ∃ n, (run n (native s)).outcome = .fault)

end ZkvmRef

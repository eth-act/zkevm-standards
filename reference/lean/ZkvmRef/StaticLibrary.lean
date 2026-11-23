/-
Vocabulary for the zkVM static library (standards/static-library-and-linker-script,
standards/io-interface, standards/accelerated-memory-operations,
standards/c-interface-accelerators): exported symbols, calls and returns, the psABI register
rules, and memory permissions. The statements built from them are in ZkvmRef/Compliance.lean.
-/
import ZkvmRef.Run

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- The ELF's symbol table (as parsed by Sail's `zkvm_validate`) defines `name`. -/
def Exports (elf : zkvm_elf) (name : String) : Prop := ∃ v, zkvm_symbol_value elf.symbols name = some v

/-- Symbols the static library must export: the entry point, the I/O functions and every
accelerator. -/
def requiredExports : List String :=
  ([zkvm_host_fn.ZKVM_START, .ZKVM_READ_INPUT, .ZKVM_WRITE_OUTPUT].map zkvm_host_symbol) ++
    ((zkvm_host_fns.filter zkvm_host_is_accelerator).map zkvm_host_symbol)

/-- Symbols the linker script must define. -/
def linkerScriptSymbols : List String := ["_heap_start", "_heap_end"]

/-- Symbols the static library may export (accelerated memory operations). -/
def optionalExports : List String :=
  [zkvm_host_fn.ZKVM_MEMCPY, .ZKVM_MEMMOVE, .ZKVM_MEMSET, .ZKVM_MEMCMP].map zkvm_host_symbol

/-- Exactly `n` steps, if none of them is stuck. -/
def stepN : Nat → MState → Option MState
  | 0, s => some s
  | n + 1, s =>
    match step s with
    | .ok s' => stepN n s'
    | .error _ => none

/-- Running from `s` first reaches the return address `ra` of `s` in state `s'`. -/
def CallReturns (s s' : MState) : Prop :=
  ∃ n, stepN n s = some s' ∧ pc s' = xreg s 1 ∧
    ∀ m < n, ∀ t, stepN m s = some t → pc t ≠ xreg s 1

/-- Registers a call must leave unchanged under the RISC-V psABI: the callee-saved `sp` and
`s0`–`s11`, and the fixed `gp` and `tp`. Register convention:
https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/56561cb3e7330fe99a98fd27457229707b2786ae/riscv-cc.adoc?plain=1#L9-L27;
procedure calling convention:
https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/56561cb3e7330fe99a98fd27457229707b2786ae/riscv-cc.adoc?plain=1#L157-L168. -/
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

end ZkvmRef

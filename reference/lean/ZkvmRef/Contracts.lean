/-
Contracts of the functions a zkVM static library provides (standards/io-interface,
standards/accelerated-memory-operations, standards/static-library-and-linker-script),
stated over the reference machine state. Definitions only; nothing here is proved.

Calling convention assumptions shared by all contracts: the call starts with `pc` at the
function's entry, the return address in `ra` (`x1`), arguments in `a0`… (`x10`…), and at
least `stackReserve` writable bytes below `sp` (`x2`). The function may clobber those stack
bytes and caller-saved registers; nothing else.
-/
import ZkvmRef.Run

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef

/-- Exactly `n` steps, if none of them throws. -/
def stepN : Nat → MState → Except String MState
  | 0, s => .ok s
  | n + 1, s => step s >>= stepN n

/-- Running from `s` first reaches the return address `ra` of `s` in state `s'`. -/
def CallReturns (s s' : MState) : Prop :=
  ∃ n, stepN n s = .ok s' ∧ pc s' = xreg s 1 ∧
    ∀ m < n, ∀ t, stepN m s = .ok t → pc t ≠ xreg s 1

/-- Callee-saved registers of the RISC-V psABI: `sp`, `gp`, `tp`, `s0`–`s11`. -/
def calleeSavedRegs : List (Fin 32) := [2, 3, 4, 8, 9, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]

def CalleeSaved (s s' : MState) : Prop :=
  ∀ i ∈ calleeSavedRegs, xreg s' i = xreg s i

/-- Bytes of stack below `sp` a library function may use. -/
def stackReserve : Nat := 1024

/-- `a ∈ [base, base + len)`. -/
def InRange (base len a : Nat) : Prop := base ≤ a ∧ a < base + len

def Disjoint (a la b lb : Nat) : Prop := a + la ≤ b ∨ b + lb ≤ a

/-- Current PMA regions of the machine. -/
def pmaRegions (s : MState) : List PMA_Region := regOr s Register.pma_regions [] rfl

/-- Every byte of `[a, a + len)` lies in a region with the given attribute, other than the
zkVM I/O device page. -/
def Covered (attr : PMA → Bool) (s : MState) (a len : Nat) : Prop :=
  ∀ x, InRange a len x → ∃ r ∈ pmaRegions s, attr r.attributes = true ∧
    r.base.toNat ≠ zkvmIoBase ∧ InRange r.base.toNat r.size.toNat x

def Readable (s : MState) (a len : Nat) : Prop :=
  Covered (·.readable) s a len ∧ (readMem s a len).isSome

def Writable (s : MState) (a len : Nat) : Prop := Covered (·.writable) s a len

/-- The stack has `stackReserve` writable bytes below `sp`. -/
def StackOk (s : MState) : Prop :=
  stackReserve ≤ (xreg s 2).toNat ∧ Writable s ((xreg s 2).toNat - stackReserve) stackReserve

/-- Memory of `s'` equals that of `s` outside `[a, a + len)` and the stack reserve of `s`. -/
def MemUnchangedExcept (s s' : MState) (a len : Nat) : Prop :=
  ∀ x, ¬ InRange a len x → ¬ InRange ((xreg s 2).toNat - stackReserve) stackReserve x →
    s'.mem.get? x = s.mem.get? x

/-- Common postcondition: returned to `ra`, callee-saved registers and public output
preserved, memory changed at most in `[a, a + len)` and the stack reserve. -/
def ReturnsPreserving (s s' : MState) (a len : Nat) : Prop :=
  CallReturns s s' ∧ CalleeSaved s s' ∧ outputRev s' = outputRev s ∧ MemUnchangedExcept s s' a len

def AtEntry (s : MState) (entry : Nat) : Prop := pc s = BitVec.ofNat 64 entry ∧ StackOk s

def arg (s : MState) (i : Nat) : Nat := (xreg s ⟨10 + i % 8, by omega⟩).toNat

/-- `read_input(const uint8_t **buf_ptr, size_t *buf_size)` for a machine whose input region
holds `input`: stores the input's address and size and changes nothing else. Since the
results depend only on `p` and `input`, and the input region is unchanged, repeated calls
return the same values (idempotence). -/
def ReadInput (p : Profile) (input : ByteArray) (entry : Nat) : Prop :=
  ∀ s, AtEntry s entry →
    readMem s p.input.base (8 + input.size) = some (inputBlob input) →
    Writable s (arg s 0) 8 → Writable s (arg s 1) 8 → Disjoint (arg s 0) 8 (arg s 1) 8 →
    ∃ s', CallReturns s s' ∧ CalleeSaved s s' ∧ outputRev s' = outputRev s ∧
      readLE s' (arg s 0) 8 = some (p.input.base + 8) ∧
      readLE s' (arg s 1) 8 = some input.size ∧
      ∀ x, ¬ InRange (arg s 0) 8 x → ¬ InRange (arg s 1) 8 x →
        ¬ InRange ((xreg s 2).toNat - stackReserve) stackReserve x →
        s'.mem.get? x = s.mem.get? x

/-- `write_output(const uint8_t *output, size_t size)`: appends the bytes to the public
output; if any byte is not readable the run faults. -/
def WriteOutput (entry : Nat) : Prop :=
  ∀ s, AtEntry s entry →
    (∀ bytes, readMem s (arg s 0) (arg s 1) = some bytes → Readable s (arg s 0) (arg s 1) →
      ∃ s', CallReturns s s' ∧ CalleeSaved s s' ∧ MemUnchangedExcept s s' 0 0 ∧
        outputRev s' = (bytes.toList.map (·.toBitVec)).reverse ++ outputRev s) ∧
    (¬ Readable s (arg s 0) (arg s 1) → ∃ n, (run n s).outcome = .fault)

/-- `void *memcpy(void *dest, const void *src, size_t n)` for disjoint regions. -/
def Memcpy (entry : Nat) : Prop :=
  ∀ s bytes, AtEntry s entry →
    let dest := arg s 0; let src := arg s 1; let n := arg s 2
    Writable s dest n → Readable s src n → Disjoint dest n src n →
    readMem s src n = some bytes →
    ∃ s', ReturnsPreserving s s' dest n ∧ xreg s' 10 = xreg s 10 ∧ readMem s' dest n = some bytes

/-- `void *memmove(void *dest, const void *src, size_t n)`: as if copied through a
temporary buffer, so the regions may overlap. -/
def Memmove (entry : Nat) : Prop :=
  ∀ s bytes, AtEntry s entry →
    let dest := arg s 0; let src := arg s 1; let n := arg s 2
    Writable s dest n → Readable s src n →
    readMem s src n = some bytes →
    ∃ s', ReturnsPreserving s s' dest n ∧ xreg s' 10 = xreg s 10 ∧ readMem s' dest n = some bytes

/-- `void *memset(void *dest, int c, size_t n)`: fills with `c & 0xff`. -/
def Memset (entry : Nat) : Prop :=
  ∀ s, AtEntry s entry →
    let dest := arg s 0; let c := arg s 1; let n := arg s 2
    Writable s dest n →
    ∃ s', ReturnsPreserving s s' dest n ∧ xreg s' 10 = xreg s 10 ∧
      readMem s' dest n = some ⟨Array.replicate n (UInt8.ofNat (c % 256))⟩

/-- Sign of the first differing pair of unsigned bytes; 0 if none. -/
def cmpSign : List UInt8 → List UInt8 → Int
  | a :: as, b :: bs => if a < b then -1 else if b < a then 1 else cmpSign as bs
  | _, _ => 0

/-- `int memcmp(const void *s1, const void *s2, size_t n)`: the result (the low 32 bits of
`a0`, signed) has the sign of the first differing pair of bytes, 0 if none. -/
def Memcmp (entry : Nat) : Prop :=
  ∀ s b1 b2, AtEntry s entry →
    let s1 := arg s 0; let s2 := arg s 1; let n := arg s 2
    Readable s s1 n → Readable s s2 n →
    readMem s s1 n = some b1 → readMem s s2 n = some b2 →
    ∃ s', ReturnsPreserving s s' 0 0 ∧
      Int.sign ((xreg s' 10).setWidth 32).toInt = cmpSign b1.toList b2.toList

/-- `_start`: from the initial state, execution reaches `main` (entry `mainEntry`) with a
16-byte aligned `sp` and `gp = __global_pointer$`; when `main` returns with `a0 = c`, the run
halts with exit code `(uint32_t)c` and the output produced so far. -/
def StartMain (p : Profile) (img : Image) (input : ByteArray) (mainEntry gp : Nat) : Prop :=
  ∀ s, initialState p img input = .ok s →
    ∃ n t, stepN n s = .ok t ∧ pc t = BitVec.ofNat 64 mainEntry ∧
      (∀ m < n, ∀ u, stepN m s = .ok u → pc u ≠ BitVec.ofNat 64 mainEntry) ∧
      (xreg t 2).toNat % 16 = 0 ∧ xreg t 3 = BitVec.ofNat 64 gp ∧
      ∀ t', CallReturns t t' →
        ∃ m, run m t' = ⟨decodeExit ((xreg t' 10).toNat % 2 ^ 32), output t'⟩

end ZkvmRef

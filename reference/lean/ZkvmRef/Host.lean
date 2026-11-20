/-
Semantics of the host functions declared in reference/sail/zkvm/zkvm_host.sail: what the
machine does when the PC reaches the address of a static-library symbol.

Calling convention (RISC-V psABI): arguments in `a0`…`a2` (`x10`…`x12`), return value in `a0`,
return address in `ra` (`x1`). Address arithmetic wraps at 64 bits and sizes are full 64-bit
register values. Memory is accessed byte by byte with the guest's permissions
(`zkvm_load_byte`, `zkvm_store_byte`); the first failing access ends the run with a fault and
the function does not return.
-/
import ZkvmRef.Machine

open PreSail LeanRV64DExecutable.Functions

namespace ZkvmRef
namespace Host

/-- Result of performing a host function. -/
inductive HostResult
  | next (s : MState)
  | unspecified (name : String)
  | error (msg : String)

def ra : regno := .Regno 1
def sp : regno := .Regno 2
def gp : regno := .Regno 3
def a0 : regno := .Regno 10
def a1 : regno := .Regno 11
def a2 : regno := .Regno 12

/-- Return to the caller: continue at `ra`. -/
def ret : SailM Unit := do
  set_next_pc (← rX ra)
  tick_pc ()

/-- The `n` bytes at `a` in increasing address order, or `none` at the first failing load. -/
def loadBytes (a n : BitVec 64) : SailM (Option (Array (BitVec 8))) := do
  let mut out := #[]
  for i in [0:n.toNat] do
    match ← zkvm_load_byte (a + BitVec.ofNat 64 i) with
    | some b => out := out.push b
    | none => return none
  return some out

/-- Store `bs` at `a` in increasing address order; `false` at the first failing store. -/
def storeBytes (a : BitVec 64) (bs : Array (BitVec 8)) : SailM Bool := do
  for h : i in [0:bs.size] do
    unless ← zkvm_store_byte (a + BitVec.ofNat 64 i) bs[i] do return false
  return true

/-- The 8 little-endian bytes of `v`. -/
def le64 (v : BitVec 64) : Array (BitVec 8) :=
  (Array.range 8).map fun i => v.extractLsb' (8 * i) 8

/-- `_start`: the first time, set up `sp` (top of the stack region), `gp`
(`__global_pointer$`, if defined) and `ra` (`_start` itself) and call `main`. Reaching
`_start` again is `main` returning: the run halts with exit code `(uint32_t)a0`. -/
def start : SailM Unit := do
  if ← readReg Register.zkvm_started then
    zkvm_exit ((← rX a0).setWidth 32)
  else
    wX sp (← readReg Register.zkvm_stack_top)
    if let some g ← readReg Register.zkvm_gp then wX gp g
    wX ra (← readReg Register.PC)
    writeReg Register.zkvm_started true
    set_next_pc (← readReg Register.zkvm_main)
    tick_pc ()

/-- `read_input(buf_ptr, buf_size)`: `*buf_ptr` := input address, `*buf_size` := input size. -/
def readInput : SailM Unit := do
  let base ← readReg Register.zkvm_input_base
  let size ← readReg Register.zkvm_input_size
  unless ← storeBytes (← rX a0) (le64 base) do return ← zkvm_host_fault ()
  unless ← storeBytes (← rX a1) (le64 size) do return ← zkvm_host_fault ()
  ret

/-- `write_output(output, size)`: append the `size` bytes at `output` to the public output;
if any of them is unreadable, fault without appending anything. -/
def writeOutput : SailM Unit := do
  let some bs ← loadBytes (← rX a0) (← rX a1) | zkvm_host_fault ()
  let rev ← readReg Register.zkvm_output_rev
  writeReg Register.zkvm_output_rev (bs.toList.reverse ++ rev)
  ret

/-- `memcpy(dest, src, n)`: for each `i < n` in increasing order, copy byte `src + i` to
`dest + i`. Returns `dest` (`a0` unchanged). -/
def memcpy : SailM Unit := do
  let dest ← rX a0
  let src ← rX a1
  let n ← rX a2
  for i in [0:n.toNat] do
    let off := BitVec.ofNat 64 i
    let some b ← zkvm_load_byte (src + off) | return ← zkvm_host_fault ()
    unless ← zkvm_store_byte (dest + off) b do return ← zkvm_host_fault ()
  ret

/-- `memmove(dest, src, n)`: read all `n` source bytes, then write them to `dest`, so the
regions may overlap. Returns `dest`. -/
def memmove : SailM Unit := do
  let some bs ← loadBytes (← rX a1) (← rX a2) | zkvm_host_fault ()
  unless ← storeBytes (← rX a0) bs do return ← zkvm_host_fault ()
  ret

/-- `memset(dest, c, n)`: store `c & 0xff` at `dest + i` for each `i < n`. Returns `dest`. -/
def memset : SailM Unit := do
  let dest ← rX a0
  let c := (← rX a1).setWidth 8
  for i in [0:(← rX a2).toNat] do
    unless ← zkvm_store_byte (dest + BitVec.ofNat 64 i) c do return ← zkvm_host_fault ()
  ret

/-- `memcmp(lhs, rhs, n)`: compare unsigned bytes in increasing order up to the first
difference; `a0` := -1, 1 or 0. -/
def memcmp : SailM Unit := do
  let lhs ← rX a0
  let rhs ← rX a1
  let mut r : BitVec 64 := 0
  for i in [0:(← rX a2).toNat] do
    let off := BitVec.ofNat 64 i
    let some x ← zkvm_load_byte (lhs + off) | return ← zkvm_host_fault ()
    let some y ← zkvm_load_byte (rhs + off) | return ← zkvm_host_fault ()
    if x < y then
      r := BitVec.allOnes 64
      break
    if y < x then
      r := 1
      break
  wX a0 r
  ret

/-- The machine program of a non-accelerator host function. -/
def perform : zkvm_host_fn → SailM Unit
  | .ZKVM_START => start
  | .ZKVM_READ_INPUT => readInput
  | .ZKVM_WRITE_OUTPUT => writeOutput
  | .ZKVM_MEMCPY => memcpy
  | .ZKVM_MEMMOVE => memmove
  | .ZKVM_MEMSET => memset
  | .ZKVM_MEMCMP => memcmp
  | _ => pure ()

/-- Perform host function `f` in state `s`. Accelerator semantics are unspecified. -/
def exec (f : zkvm_host_fn) (s : MState) : HostResult :=
  if zkvm_host_is_accelerator f then .unspecified (zkvm_host_symbol f)
  else match runM (perform f) s with
    | .ok (_, s') => .next s'
    | .error e => .error e

end Host
end ZkvmRef

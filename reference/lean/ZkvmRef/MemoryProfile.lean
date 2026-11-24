/-
Memory profile files (`reference/memory-profiles/*.json`). The profile's type and meaning are
Sail's `zkvm_memory_profile` (reference/sail/zkvm/zkvm_state.sail); this file only decodes the
JSON, with Lean's `Lean.Data.Json` parser.
-/
import Lean.Data.Json
import LeanRV64DExecutable

namespace ZkvmRef

/-- The Sail memory profile. -/
abbrev MemoryProfile := zkvm_memory_profile

/-- `[a, a + len)` lies inside the range. -/
def _root_.zkvm_range.contains (r : zkvm_range) (a len : Nat) : Bool :=
  r.base.toNat ≤ a && a + len ≤ r.base.toNat + r.size.toNat

/-- Parse a `"0x…"` hexadecimal string. JSON has no hexadecimal numbers. -/
def parseHex (s : String) : Except String Nat := do
  let some digits := s.dropPrefix? "0x" | throw s!"expected a 0x-prefixed hex string, got '{s}'"
  if digits.isEmpty then throw s!"empty hex string '{s}'"
  digits.toString.foldl (fun acc c => do
    let n ← acc
    let d ← if '0' ≤ c && c ≤ '9' then pure (c.toNat - '0'.toNat)
      else if 'a' ≤ c && c ≤ 'f' then pure (c.toNat - 'a'.toNat + 10)
      else if 'A' ≤ c && c ≤ 'F' then pure (c.toNat - 'A'.toNat + 10)
      else throw s!"bad hex digit in '{s}'"
    pure (n * 16 + d)) (pure 0)

open Lean in
def MemoryProfile.fromJson (j : Json) : Except String MemoryProfile := do
  let bits := fun (s : String) => do
    let n ← parseHex s
    unless n < 2 ^ 64 do throw s!"'{s}' does not fit in 64 bits"
    return BitVec.ofNat 64 n
  let hexField := fun (o : Json) (k : String) => do bits (← o.getObjValAs? String k)
  let rangeOf := fun (o : Json) => do
    return ({ base := ← hexField o "base", size := ← hexField o "size" } : zkvm_range)
  let range := fun (k : String) => do rangeOf (← j.getObjVal? k)
  let rs ← match j.getObjValAs? (Array Json) "memory" with
    | .ok rs => pure rs
    | .error _ => throw "memory must be a non-empty array"
  if rs.isEmpty then throw "memory must be a non-empty array"
  let memory ← rs.toList.mapM rangeOf
  let exec_perm ← match ← j.getObjValAs? String "exec_perm" with
    | "x" => pure zkvm_exec_perm.ZKVM_EXEC_X
    | "rx" => pure zkvm_exec_perm.ZKVM_EXEC_RX
    | s => throw s!"unknown exec_perm '{s}'"
  let boot_addr ← match ← j.getObjVal? "boot_addr" with
    | .null => pure none
    | .str s => some <$> bits s
    | _ => throw "boot_addr must be null or a hex string"
  return {
    exec_perm
    address_space := ← range "address_space"
    boot_addr
    input := ← range "input"
    memory
    stack := ← range "stack"
  }

end ZkvmRef

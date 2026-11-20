/-
zkVM memory profiles (ELF Loading standard, memory layout restrictions).
-/
import Lean.Data.Json

namespace ZkvmRef

/-- Permission of executable segments the profile accepts: execute-only or read+execute. -/
inductive ExecPerm
  | x
  | rx
  deriving Repr, DecidableEq, Inhabited

/-- Half-open address range `[base, base + size)`. -/
structure Range where
  base : Nat
  size : Nat
  deriving Repr, DecidableEq, Inhabited

/-- `[a, a + len)` lies inside the range. -/
def Range.contains (r : Range) (a len : Nat) : Bool :=
  r.base ≤ a && a + len ≤ r.base + r.size

structure Profile where
  name : String
  execPerm : ExecPerm
  addressSpace : Range
  bootAddr : Option Nat
  input : Range
  ram : Range
  stack : Range
  deriving Repr, Inhabited

/-- The page at address 0 that must never be mapped. -/
def nullPage : Range := ⟨0, 0x1000⟩

/-- The guard page directly below the stack. -/
def Profile.guard (p : Profile) : Range := ⟨p.stack.base - 0x1000, 0x1000⟩

/-- Parse a `"0x…"` hexadecimal string. -/
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
def Profile.fromJson (j : Json) : Except String Profile := do
  let hexField := fun (o : Json) (k : String) => do parseHex (← o.getObjValAs? String k)
  let range := fun (k : String) => do
    let o ← j.getObjVal? k
    return Range.mk (← hexField o "base") (← hexField o "size")
  let execPerm ← match ← j.getObjValAs? String "exec_perm" with
    | "x" => pure ExecPerm.x
    | "rx" => pure ExecPerm.rx
    | s => throw s!"unknown exec_perm '{s}'"
  let bootAddr ← match ← j.getObjVal? "boot_addr" with
    | .null => pure none
    | .str s => some <$> parseHex s
    | _ => throw "boot_addr must be null or a hex string"
  return {
    name := ← j.getObjValAs? String "name"
    execPerm
    addressSpace := ← range "address_space"
    bootAddr
    input := ← range "input"
    ram := ← range "ram"
    stack := ← range "stack"
  }

end ZkvmRef

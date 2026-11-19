/-
zkvm-run PROFILE ELF INPUT [FUEL]

Loads ELF under PROFILE, runs it on INPUT in the reference machine and prints
`outcome=<…> output=<hex>`. Exit codes: 0 ran, 2 rejected (prints `REJECT <message>`),
1 other errors.
-/
import ZkvmRef

open ZkvmRef

def outcomeString : Outcome → String
  | .success => "success"
  | .failure c => s!"failure:{c}"
  | .fault => "fault"
  | .badExit c => s!"badexit:{c}"
  | .outOfFuel => "outoffuel"
  | .stuck m => s!"stuck:{m}"

def hexByte (b : UInt8) : String :=
  let d := Nat.toDigits 16 b.toNat
  String.ofList (if d.length < 2 then '0' :: d else d)

def main (args : List String) : IO UInt32 := do
  let (profilePath, elfPath, inputPath, fuelArg) ← match args with
    | [p, e, i] => pure (p, e, i, "50000000")
    | [p, e, i, f] => pure (p, e, i, f)
    | _ => IO.eprintln "usage: zkvm-run PROFILE ELF INPUT [FUEL]"; return 1
  let some fuel := fuelArg.toNat?
    | IO.eprintln s!"bad FUEL '{fuelArg}'"; return 1
  try
    let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile profilePath))
    let p ← IO.ofExcept (Profile.fromJson j)
    let elf ← IO.FS.readBinFile elfPath
    let input ← IO.FS.readBinFile inputPath
    match load p elf with
    | .error m => IO.println s!"REJECT {m}"; return 2
    | .ok img =>
      if input.size + 8 > p.input.size then
        IO.println "REJECT input larger than the input region"
        return (2 : UInt32)
      else
        let s ← IO.ofExcept (initialState p img input)
        let o := ZkvmRef.run fuel s
        IO.println s!"outcome={outcomeString o.outcome} output={String.join (o.output.map hexByte)}"
        return (0 : UInt32)
  catch e =>
    IO.eprintln s!"error: {e}"
    return 1

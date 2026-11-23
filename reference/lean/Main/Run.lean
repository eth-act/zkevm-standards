/-
zkvm-run [--canary] PROFILE ELF INPUT [FUEL]

Loads ELF under PROFILE, runs it on INPUT in the reference machine and prints
`outcome=<…> output=<hex> misaligned=<count>`. Integer registers x1…x31 start at 0, or at a
distinct nonzero pattern with `--canary` (the standards leave them unspecified, so a conforming
guest's observation must not change). Exit codes: 0 ran, 2 rejected (prints `REJECT <message>`),
1 other errors.
-/
import ZkvmRef

open ZkvmRef

def outcomeString : Outcome → String
  | .success => "success"
  | .failure c => s!"failure:{c}"
  | .fault => "fault"
  | .leanOutOfFuel => "lean_out_of_fuel"
  | .stuck m => s!"stuck:{m}"
  | .unspecified n => s!"unspecified:{n}"

def hexByte (b : UInt8) : String :=
  let d := Nat.toDigits 16 b.toNat
  String.ofList (if d.length < 2 then '0' :: d else d)

def main (args : List String) : IO UInt32 := do
  let (gprs, args) := if args.head? == some "--canary" then (Gprs.canary, args.tail)
    else (Gprs.zero, args)
  let (profilePath, elfPath, inputPath, fuelArg) ← match args with
    | [p, e, i] => pure (p, e, i, "50000000")
    | [p, e, i, f] => pure (p, e, i, f)
    | _ => IO.eprintln "usage: zkvm-run [--canary] PROFILE ELF INPUT [FUEL]"; return 1
  let some fuel := fuelArg.toNat?
    | IO.eprintln s!"bad FUEL '{fuelArg}'"; return 1
  try
    let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile profilePath))
    let p ← IO.ofExcept (MemoryProfile.fromJson j)
    let elf ← IO.FS.readBinFile elfPath
    let input ← IO.FS.readBinFile inputPath
    if let .error m := validate p elf then
      IO.println s!"REJECT {m}"
      return (2 : UInt32)
    match boot p elf input gprs with
    | .error "input larger than the input region" =>
      IO.println "REJECT input larger than the input region"
      return (2 : UInt32)
    | .error m =>
      IO.eprintln s!"error: {m}"
      return (1 : UInt32)
    | .ok s =>
      let (o, final) := ZkvmRef.runFinal fuel s
      IO.println s!"outcome={outcomeString o.outcome} output={String.join (o.output.map hexByte)} misaligned={misalignedCount final}"
      return (0 : UInt32)
  catch e =>
    IO.eprintln s!"error: {e}"
    return 1

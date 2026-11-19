/-
zkvm-load PROFILE BASE_CONFIG ELF INPUT OUTDIR

Validates ELF under PROFILE and writes OUTDIR/config.json (the sail-riscv configuration)
and OUTDIR/input.elf (the input region as an ELF). Exit codes: 0 loaded, 2 rejected
(prints `REJECT <message>`), 1 other errors.
-/
import ZkvmRef

open ZkvmRef

def readProfile (path : System.FilePath) : IO Profile := do
  let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
  IO.ofExcept (Profile.fromJson j)

def main (args : List String) : IO UInt32 := do
  let [profilePath, basePath, elfPath, inputPath, outDir] := args
    | IO.eprintln "usage: zkvm-load PROFILE BASE_CONFIG ELF INPUT OUTDIR"; return 1
  try
    let p ← readProfile profilePath
    let base ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile basePath))
    let elf ← IO.FS.readBinFile elfPath
    let input ← IO.FS.readBinFile inputPath
    let result := do
      let img ← load p elf
      let inElf ← inputElf p input
      return (img, inElf)
    match result with
    | .error m => IO.println s!"REJECT {m}"; return 2
    | .ok (img, inElf) =>
      IO.FS.createDirAll outDir
      IO.FS.writeFile (System.FilePath.mk outDir / "config.json") ((sailConfig base p img).pretty ++ "\n")
      IO.FS.writeBinFile (System.FilePath.mk outDir / "input.elf") inElf
      return 0
  catch e =>
    IO.eprintln s!"error: {e}"
    return 1

# Lean reference

Package `zkvm-ref`, depending on the Lean model generated from Sail
(`../build/lean/Lean_RV64D_executable`, see `../scripts/build-lean.sh`).

| Module | Contents |
|---|---|
| `ZkvmRef/Elf.lean` | ELF64 parsing: header, program headers, symbol table, segment bytes |
| `ZkvmRef/Profile.lean` | memory profiles (`../profiles/`) |
| `ZkvmRef/RegisterDefaults.lean` | generated: every register of the model with its zero value |
| `ZkvmRef/Machine.lean` | machine state `MState`, `runM`, `initial`, accessors (`haltOf`, `output`, `misalignedCount`, `hostTable`, `pmaRegions`, …) |
| `ZkvmRef/Loader.lean` | `validate` (the checks of the ELF standard, first failure reported), `install`, `load : Profile → ByteArray → MState → Except String MState`, `provideInput`, `boot` |
| `ZkvmRef/Host.lean` | semantics of every non-accelerator host function (`_start`, `read_input`, `write_output`, `memcpy`, `memmove`, `memset`, `memcmp`); accelerators are `unspecified` |
| `ZkvmRef/Run.lean` | `step` (host function at the PC, else one instruction), `runFinal`, `run`, `Outcome`, `Observation`, `Terminal` |
| `ZkvmRef/StaticLibrary.lean` | statements: `Exports`, `StaticLibraryConforms`, `ImplementsHost` and their helpers |
| `ZkvmRef/LoaderSpec.lean` | statements: `SegmentsLoaded`, `PcAtEntry`, `GuardsUnmapped`, `WXRespected`, `ExecMatchesProfile`, `LoaderCorrect` |
| `ZkvmRef/Spec.lean` | statements: `Halts`, `Rejects`, `ZkVM`, `LoaderConforms`, `ExecutionConforms`, `Type1Sound`, `Type2Sound`, `Type1Complete`, `Compliant` |
| `Main/Run.lean` | executable `zkvm-run` |

Statements are definitions of type `Prop`; nothing is proved and there are no axioms.

`zkvm-run PROFILE ELF INPUT [FUEL]` (default fuel 50000000 steps) validates and boots the ELF,
runs it and prints `outcome=<success|failure:N|fault|outoffuel|stuck:MSG|unspecified:NAME>
output=<hex> misaligned=<N>` (exit 0), or `REJECT <message>` (exit 2) when the loader rejects
the ELF or the input does not fit the input region; other errors exit 1.

Build with `../scripts/build-lean.sh`, or `lake build` here once the model is generated.

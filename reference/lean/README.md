# Lean reference

Package `zkvm-ref`, depending on the Lean model generated from Sail
(`../build/lean/Lean_RV64D_executable`, see `../scripts/build-lean.sh`).

| Module                          | Contents                                                     |
| ------------------------------- | ------------------------------------------------------------ |
| `ZkvmRef/Elf.lean`              | ELF64 parsing: header, program headers, symbol table,        |
|                                 | segment bytes                                                |
| `ZkvmRef/MemoryProfile.lean`    | memory profiles (`../memory-profiles/`)                      |
| `ZkvmRef/RegisterDefaults.lean` | generated: every register of the model with its zero value   |
| `ZkvmRef/Machine.lean`          | machine state `MState`, `runM`, `initial`, accessors         |
|                                 | (`haltOf`, `output`, `misalignedCount`, `hostTable`,         |
|                                 | `pmaRegions`, …)                                             |
| `ZkvmRef/Loader.lean`           | `validate` (the checks of the ELF standard, first failure    |
|                                 | reported), `install`, `load : MemoryProfile → ByteArray →    |
|                                 | MState → Except String MState`, `provideInput`, `boot`       |
| `ZkvmRef/Host.lean`             | semantics of every non-accelerator host function (`_start`,  |
|                                 | `read_input`, `write_output`, `memcpy`, `memmove`, `memset`, |
|                                 | `memcmp`); accelerators are `unspecified` at the moment to   |
|                                 | keep protoyping scope small                                  |
| `ZkvmRef/Run.lean`              | `step` (host function at the PC, else `zkvm_step`),          |
|                                 | `runFinal`, `run`, `Outcome` (including `leanOutOfFuel`,     |
|                                 | which is not a standard outcome), `Observation`, `Terminal`  |
| `ZkvmRef/StaticLibrary.lean`    | vocabulary for library statements: `Exports`, required and   |
|                                 | optional exports, `stepN`, `CallReturns`, psABI callee-saved |
|                                 | registers, `Readable`/`Writable`, `AtEntry`, `native`        |
| `ZkvmRef/LoaderSpec.lean`       | statements about the reference loader: `SegmentsLoaded`,     |
|                                 | `PcAtEntry`, `GuardsUnmapped`, `WXRespected`,                |
|                                 | `ExecMatchesProfile`, `LoaderCorrect`                        |
| `ZkvmRef/Compliance.lean`       | every compliance statement: for zkVMs `Halts`, `Rejects`,    |
|                                 | `ZkVM`, `LoaderConforms`, `ExecutionConforms`, `Type1Sound`, |
|                                 | `Type2Sound`, `Type1Complete`, `Compliant`; for vendor       |
|                                 | static libraries `StaticLibraryConforms`, `ImplementsHost`   |
| `Main/Run.lean`                 | executable `zkvm-run` (arguments: PROFILE, ELF, INPUT,       |
|                                 | optional FUEL): validates, boots and runs one guest, then    |
|                                 | prints one line `outcome=<…>` `output=<hex>`                 |
|                                 | `misaligned=<N>` and exits 0; if the loader rejects the ELF, |
|                                 | prints `REJECT` and the message and exits 2                  |

Statements are definitions of type `Prop`; nothing is proved and there are no axioms.

`zkvm-run PROFILE ELF INPUT [FUEL]` (default fuel 50000000 steps) validates and boots the ELF, runs
it and prints
`outcome=<success|failure:N|fault|lean_out_of_fuel|stuck:MSG|unspecified:NAME> output=<hex> misaligned=<N>`
(exit 0), or `REJECT <message>` (exit 2) when the loader rejects the ELF or the input does not fit
the input region; other errors exit 1.

Build with `../scripts/build-lean.sh`, or `lake build` here once the model is generated.

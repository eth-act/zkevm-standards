# Lean reference

Package `zkvm-ref`, depending on the Lean model generated from Sail
(`../build/lean/Lean_RV64D_executable`, see `../scripts/build-lean.sh`). The machine, including
host-function semantics and machine initialisation, is Sail (`../sail`); this package holds what is
not machine behaviour: ELF parsing and validation, decoding profile files, the run loop, the
statements and the executable. See [`../README.md`](../README.md) for the placement rule.

| Module                       | Contents                                                     |
| ---------------------------- | ------------------------------------------------------------ |
| `ZkvmRef/Elf.lean`           | ELF64 parsing: header, program headers, symbol table,        |
|                              | segment bytes                                                |
| `ZkvmRef/MemoryProfile.lean` | decodes `../memory-profiles/*.json` into Sail's              |
|                              | `zkvm_memory_profile` (with Lean's `Lean.Data.Json`)         |
| `ZkvmRef/Machine.lean`       | machine state `MState`, `runM`, initial integer registers    |
|                              | `Gprs` (`zero`, `canary`), `initial`, accessors (`haltOf`,   |
|                              | `output`, `misalignedCount`, `hostTable`, `pmaRegions`, …)   |
| `ZkvmRef/Loader.lean`        | `validate` (the checks of the ELF standard, first failure    |
|                              | reported; computes the memory map, segments and host         |
|                              | bindings), `install` and `provideInput` (call Sail's         |
|                              | `zkvm_install` and `zkvm_provide_input`), `load`, `boot`     |
| `ZkvmRef/Run.lean`           | `step` (Sail's `zkvm_step`), `runFinal`, `run`, `Outcome`    |
|                              | (including `leanOutOfFuel`, which is not a standard          |
|                              | outcome), `Observation`, `Terminal`                          |
| `ZkvmRef/StaticLibrary.lean` | vocabulary for library statements: `Exports`, required and   |
|                              | optional exports, `stepN`, `CallReturns`, psABI callee-saved |
|                              | registers, `Readable`/`Writable`, `AtEntry`, `native`        |
| `ZkvmRef/LoaderSpec.lean`    | statements about the reference loader: `SegmentsLoaded`,     |
|                              | `PcAtEntry`, `GuardsUnmapped`, `WXRespected`,                |
|                              | `ExecMatchesProfile`, `LoaderCorrect`                        |
| `ZkvmRef/Compliance.lean`    | every compliance statement: for zkVMs `Halts`, `Rejects`,    |
|                              | `ZkVM`, `LoaderConforms`, `ExecutionConforms`, `Type1Sound`, |
|                              | `Type2Sound`, `Type1Complete`, `Compliant`; for vendor       |
|                              | static libraries `StaticLibraryConforms`, `ImplementsHost`   |
| `Main/Run.lean`              | executable `zkvm-run` (arguments: optional `--canary`,       |
|                              | PROFILE, ELF, INPUT, optional FUEL): validates, boots and    |
|                              | runs one guest, then prints one line `outcome=<…>`           |
|                              | `output=<hex>` `misaligned=<N>` and exits 0; if the loader   |
|                              | rejects the ELF, prints `REJECT` and the message and exits 2 |

Statements are definitions of type `Prop`; nothing is proved and there are no axioms.

`zkvm-run [--canary] PROFILE ELF INPUT [FUEL]` (default fuel 50000000 steps) validates and boots the
ELF, runs it and prints
`outcome=<success|failure:N|fault|unspecified:NAME|lean_out_of_fuel|stuck:MSG> output=<hex> misaligned=<N>`
(exit 0), or `REJECT <message>` (exit 2) when the loader rejects the ELF or the input does not fit
the input region; other errors exit 1. Integer registers `x1`…`x31` start at 0, or at a distinct
nonzero pattern with `--canary`.

Build with `../scripts/build-lean.sh`, or `lake build` here once the model is generated.

# Sail: the zkVM platform

The reference platform is the pinned sail-riscv model (`../sail-riscv`, unmodified) plus the modules
declared in `zkvm.sail_project`. `../scripts/build-lean.sh` passes both project files to Sail:
`sail … riscv.sail_project reference/sail/zkvm.sail_project <modules>`. Sail resolves `requires`,
`after` and `before` across project files, so nothing in sail-riscv is patched.

The platform is defined here: state, termination, the step (instructions and host functions),
host-function semantics, the memory profile, the loader (ELF parsing and validation) and machine
initialisation. Lean (`../lean`) decodes input files, runs the step, and holds the statements. See
[`../README.md`](../README.md) for the placement rule.

## Modules (`zkvm.sail_project`, files in `zkvm/`)

| Module                    | File                           | Contents                                                     |
| ------------------------- | ------------------------------ | ------------------------------------------------------------ |
| `zkvm_core`               | `zkvm_state.sail`              | memory profile (`zkvm_memory_profile`, register              |
|                           |                                | `zkvm_profile`, `zkvm_page_size`, `zkvm_null_page`,          |
|                           |                                | `zkvm_stack_guard`); `zkvm_outcome` (`ZKVM_Success`,         |
|                           |                                | `ZKVM_Failure(code)`, `ZKVM_Fault`,                          |
|                           |                                | `ZKVM_Unspecified(symbol)`); registers `zkvm_halt`,          |
|                           |                                | `zkvm_output_rev` (public output, newest byte first),        |
|                           |                                | `zkvm_input_size`, `zkvm_misaligned_accesses`; termination   |
|                           |                                | `zkvm_halt_with` (asserts the run has not halted),           |
|                           |                                | `zkvm_exit`, `zkvm_host_fault`                               |
| `zkvm_extension_fallback` | `zkvm_extension_fallback.sail` | last clause of `currentlyEnabled`: extensions whose module   |
|                           |                                | is not built are disabled (asserts the configuration does    |
|                           |                                | not claim them). Ordered `after extensions, mops` and        |
|                           |                                | `before postlude`, so the built extensions' clauses match    |
|                           |                                | first and the clause precedes `end currentlyEnabled` in      |
|                           |                                | `postlude/insts_end.sail`                                    |
| `zkvm_machine`            | `zkvm_host.sail`               | `zkvm_library`: the static library, every function once      |
|                           |                                | (symbol, `zkvm_host_kind`, whether it must be exported, its  |
|                           |                                | C prototype); everything else about the library (bindings,   |
|                           |                                | required and optional exports, the test stub library) is     |
|                           |                                | derived from it. Loader-installed registers                  |
|                           |                                | `zkvm_host_table`, `zkvm_main`, `zkvm_gp`, `zkvm_started`;   |
|                           |                                | `zkvm_host_at(pc)`; checked byte access `zkvm_load_byte`,    |
|                           |                                | `zkvm_store_byte`; the semantics of `_start`, `read_input`,  |
|                           |                                | `write_output`, `memcpy`, `memmove`, `memset`, `memcmp`      |
|                           |                                | (`zkvm_host_call`, by kind); an accelerator call halts with  |
|                           |                                | `ZKVM_Unspecified(symbol)`                                   |
| `zkvm_machine`            | `zkvm_loader.sail`             | the loader: ELF parsing from a byte vector (`zkvm_rd`,       |
|                           |                                | program headers, the symbol table), `zkvm_validate` (the     |
|                           |                                | checks of the ELF standard and the memory-profile checks,    |
|                           |                                | first failure reported as a message), the memory map as page |
|                           |                                | runs (`zkvm_paint`, `zkvm_regions_of`);                      |
|                           |                                | `zkvm_exec_undecodable` (the first word of an execute-only   |
|                           |                                | segment that does not decode as RV64IM)                      |
| `zkvm_machine`            | `zkvm_install.sail`            | machine initialisation: `zkvm_install` (profile, memory map  |
|                           |                                | with its PMA attributes, PC, reset, segment bytes, host      |
|                           |                                | bindings), `zkvm_provide_input`, `zkvm_reset` (zkVM values   |
|                           |                                | for the control registers sail-riscv reads before writing,   |
|                           |                                | and the trap vector `zkvm_trap_vector`, address 0 in the     |
|                           |                                | never-mapped null page)                                      |
| `zkvm_machine`            | `zkvm_step.sail`               | `zkvm_step`: asserts the run has not halted; then the host   |
|                           |                                | function bound to the PC, or one instruction via             |
|                           |                                | sail-riscv's `try_step`, counting a misaligned data access   |
|                           |                                | first and halting with `ZKVM_Fault()` if the instruction     |
|                           |                                | trapped                                                      |

`zkvm_load_byte`/`zkvm_store_byte` go through sail-riscv's `vmem_read_addr`/`vmem_write_addr`, so
host functions access memory with the same permission checks as guest loads and stores.

## How the zkVM behaviour is attached without patching sail-riscv

- **Every trap is a fault.** sail-riscv's trap handler jumps to `mtvec`. `zkvm_reset` points `mtvec`
  at address 0, which lies in the null page the loader never maps, and `zkvm_step` halts with
  `ZKVM_Fault()` whenever PC is 0 after an instruction. A jump to 0 is also reported as a fault,
  which is what fetching from the unmapped null page would produce.
- **Misaligned-access count.** In RV64IM the only data accesses are `LOAD` and `STORE`. Before each
  instruction, `zkvm_step` decodes it with sail-riscv's `ext_decode` and counts it if its effective
  address `X(rs1) + imm` is misaligned for its width, the same address and test
  `vmem_read_addr`/`vmem_write_addr` use. This must be extended if the build gains instructions with
  other data accesses (A, F/D, C, V).
- **Extensions outside the build.** `zkvm_extension_fallback` is ordered into the scattered
  `currentlyEnabled` with `before postlude`.

## Registers without an initial value

Most sail-riscv registers have no Sail initialiser: their initial value is unspecified, and the
generated Lean model has no value for them until they are written; reading one makes the run
`stuck`. They stay that way, except:

- the control registers sail-riscv reads before its own reset writes them (`mtvec`, `stvec`,
  `medeleg`, `mideleg`, `mie`, `mip`, `mcountinhibit`, `minstret`, `minstretcfg`, `pmpcfg_n`,
  `vtype`, `vcsr`), which `zkvm_reset` sets to their zkVM values: no interrupts, no delegation, no
  PMP, no vector unit, counters at zero;
- the integer registers `x1`…`x31`, which the standards leave unspecified: the Lean side sets them
  from a parameter, and the statements quantify over every choice.

Register use for per-program state (`zkvm_host_table`, `zkvm_main`, `zkvm_gp`, `zkvm_profile`)
follows sail-riscv's own convention for state its harness installs, such as `pc_reset_address`
(`set_pc_reset_address`) and `htif_tohost_base` (`enable_htif`).

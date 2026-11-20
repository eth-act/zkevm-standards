# Sail: zkVM modules

The reference machine is the pinned sail-riscv model (`../sail-riscv`, unmodified) plus the modules
declared in `zkvm.sail_project`. `../scripts/build-lean.sh` passes both project files to Sail:
`sail … riscv.sail_project reference/sail/zkvm.sail_project <modules>`. Sail resolves `requires`,
`after` and `before` across project files, so nothing in sail-riscv is patched.

## Modules (`zkvm.sail_project`, files in `zkvm/`)

| Module                    | File                           | Contents                                                     |
| ------------------------- | ------------------------------ | ------------------------------------------------------------ |
| `zkvm_core`               | `zkvm_state.sail`              | `zkvm_outcome` (`ZKVM_Exit(code)`, `ZKVM_Fault()`);          |
|                           |                                | registers `zkvm_halt`, `zkvm_output_rev` (public output,     |
|                           |                                | newest byte first), `zkvm_input_base`/`zkvm_input_size`,     |
|                           |                                | `zkvm_misaligned_accesses`; the termination mechanism        |
|                           |                                | `zkvm_halt_with` (first outcome wins), `zkvm_exit`,          |
|                           |                                | `zkvm_host_fault`                                            |
| `zkvm_extension_fallback` | `zkvm_extension_fallback.sail` | last clause of `currentlyEnabled`: extensions whose module   |
|                           |                                | is not built are disabled (asserts the configuration does    |
|                           |                                | not claim them). Ordered `after extensions, mops` and        |
|                           |                                | `before postlude`, so the built extensions' clauses match    |
|                           |                                | first and the clause precedes `end currentlyEnabled` in      |
|                           |                                | `postlude/insts_end.sail`                                    |
| `zkvm_machine`            | `zkvm_step.sail`               | `zkvm_step`: one instruction via sail-riscv's `try_step`,    |
|                           |                                | counting a misaligned data access first and ending the run   |
|                           |                                | with a fault if the instruction trapped; `zkvm_reset`        |
|                           |                                | installs the trap vector `zkvm_trap_vector` (address 0, in   |
|                           |                                | the never-mapped null page)                                  |
| `zkvm_machine`            | `zkvm_host.sail`               | `zkvm_host_fn` (26 library functions, each with its C        |
|                           |                                | prototype), `zkvm_host_fns`, `zkvm_host_symbol`,             |
|                           |                                | `zkvm_host_is_accelerator`; loader-installed registers       |
|                           |                                | `zkvm_host_table`, `zkvm_main`, `zkvm_gp`, `zkvm_stack_top`, |
|                           |                                | `zkvm_started`; `zkvm_host_at(pc)`; checked byte access      |
|                           |                                | `zkvm_load_byte`, `zkvm_store_byte`                          |

The host functions' semantics are in `../lean/ZkvmRef/Host.lean`. A call is the PC reaching an
address in `zkvm_host_table`; the Lean run loop then performs the function instead of calling
`zkvm_step`. `zkvm_load_byte`/`zkvm_store_byte` go through sail-riscv's
`vmem_read_addr`/`vmem_write_addr`, so host functions access memory with the same permission checks
as guest loads and stores.

## How the zkVM behaviour is attached without patching sail-riscv

- **Every trap is a fault.** sail-riscv's trap handler jumps to `mtvec`. `zkvm_reset` points `mtvec`
  at address 0, which lies in the null page the loader never maps, and `zkvm_step` halts with
  `ZKVM_Fault()` whenever PC is 0 after a step. A jump to 0 is also reported as a fault, which is
  what fetching from the unmapped null page would produce.
- **Misaligned-access count.** In RV64IM the only data accesses are `LOAD` and `STORE`. Before each
  step, `zkvm_step` decodes the instruction at PC with sail-riscv's `ext_decode` and counts it if
  its effective address `X(rs1) + imm` is misaligned for its width, the same address and test
  `vmem_read_addr`/`vmem_write_addr` use. This must be extended if the build gains instructions with
  other data accesses (A, F/D, C, V).
- **Extensions outside the build.** `zkvm_extension_fallback` is ordered into the scattered
  `currentlyEnabled` with `before postlude`.

Register use follows sail-riscv's own convention for state its harness installs per program, such as
`pc_reset_address` (`set_pc_reset_address`) and `htif_tohost_base` (`enable_htif`).

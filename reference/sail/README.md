# Sail: zkVM modules and sail-riscv hooks

The reference machine is the pinned sail-riscv model (`../sail-riscv`, unmodified) plus the
files here. `../scripts/prepare-sail.sh` copies sail-riscv to `../build/sail-riscv`, applies
`hooks.patch` and copies `zkvm/*.sail` to `model/zkvm/`.

## Modules (`zkvm/`)

| Module | File | Contents |
|---|---|---|
| `zkvm_core` | `zkvm_state.sail` | `zkvm_outcome` (`ZKVM_Exit(code)`, `ZKVM_Fault()`); registers `zkvm_halt`, `zkvm_output_rev` (public output, newest byte first), `zkvm_input_base`/`zkvm_input_size`, `zkvm_misaligned_accesses`; `zkvm_halt_with` (first outcome wins) |
| `zkvm_core` | `zkvm_termination.sail` | `zkvm_exit`, `zkvm_host_fault`, and `handle_trap_extension`, which halts with a fault on every trap |
| `zkvm_extension_fallback` | `zkvm_extension_fallback.sail` | last clause of `currentlyEnabled`: extensions whose module is not built are disabled (asserts the configuration does not claim them) |
| `zkvm_host` | `zkvm_host.sail` | `zkvm_host_fn` (26 library functions, each with its C prototype), `zkvm_host_fns`, `zkvm_host_symbol`, `zkvm_host_is_accelerator`; loader-installed registers `zkvm_host_table`, `zkvm_main`, `zkvm_gp`, `zkvm_stack_top`, `zkvm_started`; `zkvm_host_at(pc)`; checked byte access `zkvm_load_byte`, `zkvm_store_byte` |

The host functions' semantics are in `../lean/ZkvmRef/Host.lean`. A call is the PC reaching an
address in `zkvm_host_table`; the Lean run loop then performs the function instead of fetching.
`zkvm_load_byte`/`zkvm_store_byte` go through sail-riscv's `vmem_read_addr`/`vmem_write_addr`,
so host functions access memory with the same permission checks as guest loads and stores.

## `hooks.patch`

Three edits to sail-riscv, each needed because the hook point is not reachable from a separate
module:

1. `model/riscv.sail_project`: declares the three modules. `sys` requires `zkvm_core` (the trap
   handler calls `handle_trap_extension`, the vmem functions update the misaligned count);
   `postlude` requires `zkvm_extension_fallback`, which comes after all extension modules so
   their `currentlyEnabled` clauses match first; `zkvm_host` comes after `postlude`.
2. `model/exceptions/sys_exceptions.sail`: deletes sail-riscv's no-op `handle_trap_extension`,
   so `zkvm_termination.sail` can define it. `trap_handler` calls it for every synchronous
   exception and interrupt, after writing `mcause`, `mtval` and `mepc`.
3. `model/sys/vmem_utils.sail`: increments `zkvm_misaligned_accesses` in the misaligned branch
   of `vmem_read_addr` and `vmem_write_addr` (riscv-target: zkVMs expose this count).

To change the patch: write an empty `hooks.patch`, run `../scripts/prepare-sail.sh`, run
`git init -q && git add -A && git commit -qm base` in `../build/sail-riscv`, make the edits, and
save `git diff -- model/riscv.sail_project model/exceptions/sys_exceptions.sail model/sys/vmem_utils.sail`
as `hooks.patch`.

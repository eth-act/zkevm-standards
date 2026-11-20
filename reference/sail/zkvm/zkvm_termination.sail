// Standard termination semantics: a run ends with main's return value or with a fault.

function zkvm_exit(code : bits(32)) -> unit = zkvm_halt_with(ZKVM_Exit(code))

function zkvm_host_fault() -> unit = zkvm_halt_with(ZKVM_Fault())

// Replaces sail-riscv's no-op hook (deleted by hooks.patch): every trap ends the run with a
// fault. trap_handler calls it after writing mcause, mtval and mepc.
function handle_trap_extension(_p : Privilege, _pc : xlenbits, _u : option(unit)) -> unit =
  zkvm_halt_with(ZKVM_Fault())

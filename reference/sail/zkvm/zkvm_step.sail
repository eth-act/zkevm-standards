// One step of the zkVM: a host function if the PC is at a bound library symbol, otherwise one
// instruction through sail-riscv's try_step. Expressed without modifying sail-riscv.

// One instruction.
function zkvm_instruction_step() -> unit = {
  let _ : bool = try_step(0, true);
}

// One step. The run must not have halted already.
function zkvm_step() -> unit = {
  match zkvm_halt {
    None() => (),
    Some(_) => assert(false, "zkvm_step: the run has already halted"),
  };
  match zkvm_host_at(PC) {
    Some(f) => zkvm_host_call(f),
    None() => zkvm_instruction_step(),
  }
}

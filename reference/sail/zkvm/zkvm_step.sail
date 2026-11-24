// One step of the zkVM: a host function if the PC is at a bound library symbol, otherwise one
// instruction through sail-riscv's try_step. Expressed without modifying sail-riscv.

// One instruction: execute, and end the run with a fault if the instruction trapped
// (standards/standard-termination-semantics: every trap is abnormal termination).
function zkvm_instruction_step() -> unit = {
  let _ : bool = try_step(0, true);
  // [TER4][IAM1][IAM2][IAM3] an instruction-address-misaligned exception (a jump to a target
  // that is not 4-byte aligned: no C extension, IALIGN=32) is a trap like any other, raised by
  // sail-riscv whether or not Zicclsm is supported, and ends the run here; nothing resumes it.
  if PC == zkvm_trap_vector then zkvm_halt_with(ZKVM_Fault())
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

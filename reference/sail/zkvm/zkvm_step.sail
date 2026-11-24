// One step of the zkVM: a host function if the PC is at a bound library symbol, otherwise one
// instruction through sail-riscv's try_step. Expressed without modifying sail-riscv.

// The instruction at PC accesses data at a misaligned address. In this build (RV64IM, no A,
// F, D, C or V) the only data accesses are LOAD and STORE, and their address is
// X(rs1) + imm, the address vmem_read_addr/vmem_write_addr check for alignment. A fetch that
// would fail is no access: try_step traps instead.
function zkvm_misaligned_data_access() -> bool =
  if PC[1 .. 0] != 0b00 then false
  else match vmem_read_addr(Virtaddr(PC), 4, InstructionFetch(), false, false, false) {
    Err(_) => false,
    Ok(w) => match ext_decode(w) {
      LOAD(imm, rs1, _, _, width) => not(is_aligned_addr(Virtaddr(X(rs1) + sign_extend(imm)), width)),
      STORE(imm, _, rs1, width) => not(is_aligned_addr(Virtaddr(X(rs1) + sign_extend(imm)), width)),
      _ => false,
    },
  }

// One instruction: count a misaligned data access, execute, and end the run with a fault if
// the instruction trapped (standards/standard-termination-semantics: every trap is abnormal
// termination).
function zkvm_instruction_step() -> unit = {
  // [TGT7][TGT8]
  if zkvm_misaligned_data_access() then
    zkvm_misaligned_accesses = zkvm_misaligned_accesses + 1;
  let _ : bool = try_step(0, true);
  // [TER4][IAM1][IAM2][IAM3][TGT3] Every trap ends the run here; nothing resumes it. That
  // includes ecall (there is no environment) and an instruction-address-misaligned exception (a
  // jump to a target that is not 4-byte aligned: no C extension, IALIGN=32), which sail-riscv
  // raises whether or not Zicclsm is supported.
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

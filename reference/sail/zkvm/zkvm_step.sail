// One instruction step of the zkVM: sail-riscv's try_step plus the zkVM's two additions,
// expressed without modifying sail-riscv.

// Trap vector installed by zkvm_reset. It lies in the null page, which the loader never maps,
// so no guest instruction executes there: PC reaches it only through a trap, or through a jump
// to it, whose fetch would fault anyway.
let zkvm_trap_vector : xlenbits = zeros()

// Called by the loader after sail-riscv's init_model.
function zkvm_reset() -> unit = mtvec = Mk_Mtvec(zkvm_trap_vector)

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
function zkvm_step() -> unit = {
  if zkvm_misaligned_data_access() then
    zkvm_misaligned_accesses = zkvm_misaligned_accesses + 1;
  let _ : bool = try_step(0, true);
  if PC == zkvm_trap_vector then zkvm_halt_with(ZKVM_Fault())
}

// zkVM state carried alongside the RISC-V machine state.

// Outcome of a halted zkVM run.
union zkvm_outcome = {
  ZKVM_Exit  : bits(32),  // main returned this value; 0 is success
  ZKVM_Fault : unit,      // abnormal termination: a trap or a faulting host call
}

// Set once the run has halted; the run loop stops stepping.
register zkvm_halt : option(zkvm_outcome) = None()

// Public output, most recent byte first.
register zkvm_output_rev : list(bits(8)) = [||]

// Private input: placed in memory by the loader at zkvm_input_base.
register zkvm_input_base : xlenbits = zeros()
register zkvm_input_size : xlenbits = zeros()

// Misaligned data accesses so far (riscv-target: zkVMs expose this count).
register zkvm_misaligned_accesses : bits(64) = zeros()

// Record the outcome unless the run has already halted. (This file must define a function:
// Sail 0.20.2's Lean backend crashes on a file that defines registers but no function.)
function zkvm_halt_with(o : zkvm_outcome) -> unit =
  match zkvm_halt { None() => zkvm_halt = Some(o), Some(_) => () }

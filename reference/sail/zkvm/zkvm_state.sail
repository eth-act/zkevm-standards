// zkVM state carried alongside the RISC-V machine state, the zkVM's memory profile, and the
// termination mechanism (standards/standard-termination-semantics).

// ---------------------------------------------------------------------------------------------
// Memory profile: the memory layout this zkVM offers (memory-layout-restrictions,
// memory-safety-guard-regions, elf-loading-and-validation). A property of the zkVM, installed by
// the loader from a profile file.

// Half-open address range [base, base + size).
struct zkvm_range = {
  base : xlenbits,
  size : xlenbits,
}

// Permission of executable segments the zkVM accepts: execute-only or read+execute.
enum zkvm_exec_perm = { ZKVM_EXEC_X, ZKVM_EXEC_RX }

struct zkvm_memory_profile = {
  exec_perm     : zkvm_exec_perm,
  address_space : zkvm_range,           // every segment lies in it
  boot_addr     : option(xlenbits),     // fixed entry address, if the zkVM has one
  input         : zkvm_range,           // read-only; holds the private input from its base
  ram           : zkvm_range,           // read-write; segments lie in it
  stack         : zkvm_range,           // read-write; _start sets sp to its top
}

// Empty until zkvm_install writes the zkVM's profile.
register zkvm_profile : zkvm_memory_profile = struct {
  exec_perm = ZKVM_EXEC_X,
  address_space = struct { base = zeros(), size = zeros() },
  boot_addr = None(),
  input = struct { base = zeros(), size = zeros() },
  ram = struct { base = zeros(), size = zeros() },
  stack = struct { base = zeros(), size = zeros() },
}

// Granularity of memory permissions.
let zkvm_page_size : xlenbits = zero_extend(0x1000)

// The null-pointer trap region: never mapped, so any access to it faults.
let zkvm_null_page : zkvm_range = struct { base = zeros(), size = zkvm_page_size }

// The stack guard region directly below the stack: never mapped.
function zkvm_stack_guard(p : zkvm_memory_profile) -> zkvm_range =
  struct { base = p.stack.base - zkvm_page_size, size = zkvm_page_size }

// ---------------------------------------------------------------------------------------------
// Run state.

// Outcome of a halted run.
union zkvm_outcome = {
  ZKVM_Success     : unit,      // main returned 0
  ZKVM_Failure     : bits(32),  // main returned this non-zero error code
  ZKVM_Fault       : unit,      // abnormal termination: a trap or a faulting host call
  ZKVM_Unspecified : string,    // the guest called this accelerator, whose semantics are not given
}

// Set once the run has halted; zkvm_step does nothing afterwards.
register zkvm_halt : option(zkvm_outcome) = None()

// Public output, most recent byte first.
register zkvm_output_rev : list(bits(8)) = [||]

// Size of the private input, which the loader places at the start of zkvm_profile.input.
register zkvm_input_size : xlenbits = zeros()

// Misaligned data accesses so far (riscv-target: zkVMs expose this count).
register zkvm_misaligned_accesses : bits(64) = zeros()

// Record the outcome unless the run has already halted.
function zkvm_halt_with(o : zkvm_outcome) -> unit =
  match zkvm_halt { None() => zkvm_halt = Some(o), Some(_) => () }

// main returned `code` to _start: 0 is success, anything else failure with that error code.
function zkvm_exit(code : bits(32)) -> unit =
  zkvm_halt_with(if code == zeros() then ZKVM_Success() else ZKVM_Failure(code))

// A host function hit an inaccessible byte.
function zkvm_host_fault() -> unit = zkvm_halt_with(ZKVM_Fault())

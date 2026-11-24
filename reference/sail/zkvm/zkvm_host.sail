// Host functions: the functions of the zkVM static library
// (standards/static-library-and-linker-script): which functions exist, their symbols, when they
// are invoked, and what each does.

// What the machine does when a library function is called.
enum zkvm_host_kind = {
  ZKVM_START,
}

// A function of the static library: its symbol, what calling it does, and whether the library
// must export it (static-library-and-linker-script; the memory operations are optional).
struct zkvm_library_fn = {
  symbol   : string,
  kind     : zkvm_host_kind,
  required : bool,
}

// The zkVM static library: every function, once, with its C prototype. Everything else about the
// library (bindings, required and optional exports, the test stub library) is derived from it.
let zkvm_library : list(zkvm_library_fn) = [|
  // entry point; calls main and passes its return value to the termination mechanism
  struct { symbol = "_start", kind = ZKVM_START, required = true }
|]

// The symbol of the first library function of `kind`.
val zkvm_library_symbol : (list(zkvm_library_fn), zkvm_host_kind) -> string
function zkvm_library_symbol(fs, kind) =
  match fs {
    [||] => "",
    f :: rest => if f.kind == kind then f.symbol else zkvm_library_symbol(rest, kind),
  }

// A host-function symbol bound to its address.
struct zkvm_host_binding = {
  addr : xlenbits,
  func : zkvm_library_fn,
}

// Installed by the loader.
// Binding of each host-function symbol the ELF defines.
register zkvm_host_table : list(zkvm_host_binding) = [||]
// Address of main.
register zkvm_main : xlenbits = zeros()
// Value of __global_pointer$, if the ELF defines it.
register zkvm_gp : option(xlenbits) = None()
// Set when _start has called main; a later call of _start is main returning.
register zkvm_started : bool = false

// First host function bound to `pc` in `table`.
val zkvm_host_lookup : (list(zkvm_host_binding), xlenbits) -> option(zkvm_library_fn)
function zkvm_host_lookup(table, pc) =
  match table {
    [||] => None(),
    b :: rest => if b.addr == pc then Some(b.func) else zkvm_host_lookup(rest, pc),
  }

// A static-library call is the PC reaching a bound symbol address; zkvm_step then performs the
// host function instead of fetching.
function zkvm_host_at(pc : xlenbits) -> option(zkvm_library_fn) = zkvm_host_lookup(zkvm_host_table, pc)

// ---------------------------------------------------------------------------------------------
// Semantics of the host functions.
//
// Calling convention (RISC-V psABI): arguments in a0..a2 (x10..x12), result in a0, return
// address in ra (x1). Integer register convention:
// https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/56561cb3e7330fe99a98fd27457229707b2786ae/riscv-cc.adoc?plain=1#L9-L27
// Integer calling convention:
// https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/56561cb3e7330fe99a98fd27457229707b2786ae/riscv-cc.adoc?plain=1#L176-L180

// _start: the first time, set sp to the top of the stack region, gp to __global_pointer$ (if
// defined) and ra to _start itself, and call main. Reaching _start again is main returning: the
// run halts with exit code (uint32_t)a0.
function zkvm_start() -> unit =
  if zkvm_started then zkvm_exit(rX(Regno(10))[31 .. 0])
  else {
    wX(Regno(2), zkvm_profile.stack.base + zkvm_profile.stack.size);
    match zkvm_gp { Some(g) => wX(Regno(3), g), None() => () };
    wX(Regno(1), PC);
    zkvm_started = true;
    set_next_pc(zkvm_main);
    tick_pc()
  }

// Perform library function `f`.
function zkvm_host_call(f : zkvm_library_fn) -> unit =
  match f.kind {
    ZKVM_START        => zkvm_start(),
  }

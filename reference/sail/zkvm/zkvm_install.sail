// Machine initialisation by the loader. The Lean loader (ZkvmRef/Loader.lean) validates the ELF
// against the memory profile and computes what to install; these functions put it into machine
// state.

// Permission of a memory region the loader maps.
enum zkvm_perm = { ZKVM_PERM_R, ZKVM_PERM_RW, ZKVM_PERM_X, ZKVM_PERM_RX }

struct zkvm_region = {
  base : bits(64),
  size : bits(64),
  perm : zkvm_perm,
}

// Bytes to place at a virtual address (equal to the physical address: no MMU).
struct zkvm_segment = {
  vaddr : xlenbits,
  bytes : list(bits(8)),
}

// Trap vector installed by zkvm_reset. It lies in the null page, which the loader never maps,
// so no guest instruction executes there: PC reaches it only through a trap, or through a jump
// to it, whose fetch would fault anyway.
let zkvm_trap_vector : xlenbits = zkvm_null_page.base

// The memory attributes of a region. Only read-write regions are main memory. Misaligned loads
// and stores never fault (Zicclsm).
function zkvm_pma_region(r : zkvm_region) -> PMA_Region = {
  let (readable, writable, executable) : (bool, bool, bool) = match r.perm {
    ZKVM_PERM_R  => (true, false, false),
    ZKVM_PERM_RW => (true, true, false),
    ZKVM_PERM_X  => (false, false, true),
    ZKVM_PERM_RX => (true, false, true),
  };
  let is_main : bool = r.perm == ZKVM_PERM_RW;
  struct {
    base = r.base,
    size = r.size,
    attributes = struct {
      mem_type = if is_main then MainMemory else IOMemory,
      cacheable = true,
      coherent = is_main,
      executable = executable,
      readable = readable,
      writable = writable,
      read_idempotent = true,
      write_idempotent = true,
      misaligned_exceptions = struct { load_store = None(), vector = None(), amo = AccessFault },
      atomic_support = AMONone,
      reservability = RsrvNone,
      supports_cbo_zero = false,
      supports_pte_read = false,
      supports_pte_write = false,
    },
    include_in_device_tree = false,
  }
}

val zkvm_pma_regions : list(zkvm_region) -> list(PMA_Region)
function zkvm_pma_regions(rs) =
  match rs {
    [||] => [||],
    r :: rest => zkvm_pma_region(r) :: zkvm_pma_regions(rest),
  }

// Number of elements of a byte list.
function zkvm_byte_count(bs : list(bits(8))) -> int = {
  var n : int = 0;
  var rest = bs;
  var done : bool = false;
  while not(done) do {
    match rest {
      [||] => done = true,
      _ :: tail => { n = n + 1; rest = tail },
    }
  };
  n
}

// Place `bs` in memory from address `a` on, bypassing permissions (the loader, not the guest,
// writes them).
function zkvm_write_bytes(a : xlenbits, bs : list(bits(8))) -> unit = {
  var p = a;
  var rest = bs;
  var done : bool = false;
  while not(done) do {
    match rest {
      [||] => done = true,
      b :: tail => {
        let _ : bool = write_ram(Write_plain, Physaddr(zero_extend(p)), 1, b, default_meta);
        p = p + 1;
        rest = tail
      },
    }
  }
}

val zkvm_write_segments : list(zkvm_segment) -> unit
function zkvm_write_segments(ss) =
  match ss {
    [||] => (),
    s :: rest => { zkvm_write_bytes(s.vaddr, s.bytes); zkvm_write_segments(rest) },
  }

// Reset values for the control registers sail-riscv reads before its own reset writes them: a
// zkVM has no interrupts, no delegation, no PMP and no vector unit, and its counters start at
// zero. mtvec is the zkVM's trap vector. Every other register without a Sail initialiser stays
// unset, so a read of it makes the run stuck instead of returning an arbitrary value.
function zkvm_reset() -> unit = {
  mtvec = Mk_Mtvec(zkvm_trap_vector);
  stvec = Mk_Mtvec(zeros());
  medeleg = Mk_Medeleg(zeros());
  mideleg = Mk_Minterrupts(zeros());
  mie = Mk_Minterrupts(zeros());
  mip = Mk_Minterrupts(zeros());
  mcountinhibit = Mk_Counterin(zeros());
  minstret = zeros();
  minstretcfg = Mk_CountSmcntrpmf(zeros());
  pmpcfg_n = vector_init(Mk_Pmpcfg_ent(zeros()));
  vtype = Mk_Vtype(zeros());
  vcsr = Mk_Vcsr(zeros());
}

// Install a validated program: the memory profile, the memory map, the PC at the entry point,
// sail-riscv's reset, the segment contents (file bytes, then zeros up to p_memsz), the
// host-function bindings, and what _start needs to call main. No other register state is
// standardized; x1..x31 are set by the caller.
function zkvm_install(
  profile : zkvm_memory_profile,
  regions : list(zkvm_region),
  segments : list(zkvm_segment),
  entry : bits(64),
  table : list(zkvm_host_binding),
  main_addr : xlenbits,
  gp : option(xlenbits),
) -> unit = {
  zkvm_profile = profile;
  pma_regions = zkvm_pma_regions(regions);
  set_pc_reset_address(entry);
  zkvm_reset();
  init_model("");
  zkvm_write_segments(segments);
  zkvm_host_table = table;
  zkvm_main = main_addr;
  zkvm_gp = gp;
  zkvm_started = false
}

// Place the private input at the start of the profile's input region and record its size for
// read_input; false if it does not fit.
function zkvm_provide_input(input : list(bits(8))) -> bool = {
  let n = zkvm_byte_count(input);
  if n > unsigned(zkvm_profile.input.size) then return false;
  zkvm_write_bytes(zkvm_profile.input.base, input);
  zkvm_input_size = to_bits_truncate(n);
  true
}

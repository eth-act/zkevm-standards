// Machine initialisation: puts a validated image (zkvm_loader.sail) and the private input into
// machine state.

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

// Place the bytes [off, off + n) of `b` in memory from address `a` on, bypassing permissions
// (the loader, not the guest, writes them); bytes outside `b` are written as zero.
val zkvm_write_bytes : forall 'len, 'len >= 0. (xlenbits, vector('len, bits(8)), int, int) -> unit
function zkvm_write_bytes(a, b, off, n) = {
  var p = a;
  foreach (k from 0 to n - 1) {
    let i = off + k;
    let byte : bits(8) = if 0 <= i & i < length(b) then b[i] else zeros();
    let _ : bool = write_ram(Write_plain, Physaddr(zero_extend(p)), 1, byte, default_meta);
    p = p + 1
  }
}

// Each PT_LOAD segment: its p_filesz file bytes at p_vaddr, then zeros up to p_memsz.
val zkvm_write_segments : forall 'len, 'len >= 0. (vector('len, bits(8)), list(zkvm_phdr)) -> unit
function zkvm_write_segments(b, phs) =
  match phs {
    [||] => (),
    ph :: rest => {
      if zkvm_is_load(ph) then {
        zkvm_write_bytes(to_bits_truncate(ph.vaddr), b, ph.offset, ph.filesz);
        zkvm_write_bytes(to_bits_truncate(ph.vaddr + ph.filesz), b, length(b), ph.memsz - ph.filesz)
      };
      zkvm_write_segments(b, rest)
    },
  }

// The bindings of the library functions whose symbols the ELF defines, in zkvm_library order.
val zkvm_bindings : (list(zkvm_symbol), list(zkvm_library_fn)) -> list(zkvm_host_binding)
function zkvm_bindings(syms, fs) =
  match fs {
    [||] => [||],
    f :: rest => match zkvm_symbol_value(syms, f.symbol) {
      Some(v) => struct { addr = v, func = f } :: zkvm_bindings(syms, rest),
      None() => zkvm_bindings(syms, rest),
    },
  }


// Reset values for the control registers sail-riscv reads before its own reset writes them: a
// zkVM has no interrupts, no delegation, no PMP and no vector unit, and its counters start at
// zero. mtvec is the zkVM's trap vector. Every other register without a Sail initialiser stays
// unset, so a read of it makes the run stuck instead of returning an arbitrary value.
function zkvm_reset() -> unit = {
  mtvec = Mk_Mtvec(zeros());
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
val zkvm_install : forall 'len, 'len >= 0.
  (zkvm_memory_profile, zkvm_image, vector('len, bits(8))) -> unit
function zkvm_install(profile, img, b) = {
  let syms = img.elf.symbols;
  zkvm_profile = profile;
  pma_regions = zkvm_pma_regions(img.regions);
  set_pc_reset_address(to_bits_truncate(img.elf.entry));
  zkvm_reset();
  init_model("");
  zkvm_write_segments(b, img.elf.phdrs);
  zkvm_host_table = zkvm_bindings(syms, zkvm_library);
  zkvm_main = match zkvm_symbol_value(syms, "main") { Some(v) => v, None() => zeros() };
  zkvm_gp = zkvm_symbol_value(syms, "__global_pointer$");
  zkvm_started = false
}

// [IO6][IO7]
// Place the private input at the start of the profile's input region and record its size for
// read_input; false if it does not fit.
val zkvm_provide_input : forall 'len, 'len >= 0. vector('len, bits(8)) -> bool
function zkvm_provide_input(input) = {
  let n = length(input);
  if n > unsigned(zkvm_profile.input.size) then return false;
  zkvm_write_bytes(zkvm_profile.input.base, input, 0, n);
  zkvm_input_size = to_bits_truncate(n);
  true
}

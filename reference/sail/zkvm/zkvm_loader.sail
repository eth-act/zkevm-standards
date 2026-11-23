// ELF loading and validation (standards/elf-loading-and-validation) against the zkVM's memory
// profile: which ELFs are accepted, the memory map they get, and the symbols the machine binds.
// zkvm_validate is a pure function of the profile and the ELF bytes; zkvm_install
// (zkvm_install.sail) puts its result into machine state.

// ---------------------------------------------------------------------------------------------
// Reading the file.

// Little-endian unsigned integer of the `n` bytes at offset `off`; bytes outside the file read as
// 0. Callers check bounds first where it matters.
val zkvm_rd : forall 'len, 'len >= 0. (vector('len, bits(8)), int, int) -> int
function zkvm_rd(b, off, n) = {
  var v : int = 0;
  foreach (k from n - 1 downto 0) {
    let i = off + k;
    if 0 <= i & i < length(b) then v = v * 256 + unsigned(b[i]) else v = v * 256
  };
  v
}

// The printable ASCII character of a byte (symbol names are ASCII).
function zkvm_ascii(c : bits(8)) -> option(string) =
  match c {
    0x21 => Some("!"),
    0x23 => Some("#"),
    0x24 => Some("$"),
    0x25 => Some("%"),
    0x26 => Some("&"),
    0x27 => Some("'"),
    0x28 => Some("("),
    0x29 => Some(")"),
    0x2a => Some("*"),
    0x2b => Some("+"),
    0x2c => Some(","),
    0x2d => Some("-"),
    0x2e => Some("."),
    0x2f => Some("/"),
    0x30 => Some("0"),
    0x31 => Some("1"),
    0x32 => Some("2"),
    0x33 => Some("3"),
    0x34 => Some("4"),
    0x35 => Some("5"),
    0x36 => Some("6"),
    0x37 => Some("7"),
    0x38 => Some("8"),
    0x39 => Some("9"),
    0x3a => Some(":"),
    0x3b => Some(";"),
    0x3c => Some("<"),
    0x3d => Some("="),
    0x3e => Some(">"),
    0x3f => Some("?"),
    0x40 => Some("@"),
    0x41 => Some("A"),
    0x42 => Some("B"),
    0x43 => Some("C"),
    0x44 => Some("D"),
    0x45 => Some("E"),
    0x46 => Some("F"),
    0x47 => Some("G"),
    0x48 => Some("H"),
    0x49 => Some("I"),
    0x4a => Some("J"),
    0x4b => Some("K"),
    0x4c => Some("L"),
    0x4d => Some("M"),
    0x4e => Some("N"),
    0x4f => Some("O"),
    0x50 => Some("P"),
    0x51 => Some("Q"),
    0x52 => Some("R"),
    0x53 => Some("S"),
    0x54 => Some("T"),
    0x55 => Some("U"),
    0x56 => Some("V"),
    0x57 => Some("W"),
    0x58 => Some("X"),
    0x59 => Some("Y"),
    0x5a => Some("Z"),
    0x5b => Some("["),
    0x5d => Some("]"),
    0x5e => Some("^"),
    0x5f => Some("_"),
    0x60 => Some("`"),
    0x61 => Some("a"),
    0x62 => Some("b"),
    0x63 => Some("c"),
    0x64 => Some("d"),
    0x65 => Some("e"),
    0x66 => Some("f"),
    0x67 => Some("g"),
    0x68 => Some("h"),
    0x69 => Some("i"),
    0x6a => Some("j"),
    0x6b => Some("k"),
    0x6c => Some("l"),
    0x6d => Some("m"),
    0x6e => Some("n"),
    0x6f => Some("o"),
    0x70 => Some("p"),
    0x71 => Some("q"),
    0x72 => Some("r"),
    0x73 => Some("s"),
    0x74 => Some("t"),
    0x75 => Some("u"),
    0x76 => Some("v"),
    0x77 => Some("w"),
    0x78 => Some("x"),
    0x79 => Some("y"),
    0x7a => Some("z"),
    0x7b => Some("{"),
    0x7c => Some("|"),
    0x7d => Some("}"),
    0x7e => Some("~"),
    _ => None(),
  }

// The NUL-terminated ASCII string at `off`, if it is terminated within the file and printable.
val zkvm_cstring : forall 'len, 'len >= 0. (vector('len, bits(8)), int) -> option(string)
function zkvm_cstring(b, off) = {
  var s : string = "";
  foreach (i from off to length(b) - 1) {
    if 0 <= i & i < length(b) then {
      let c = b[i];
      if c == zeros() then return Some(s);
      match zkvm_ascii(c) { Some(t) => s = s ^ t, None() => return None() }
    }
  };
  None()
}

// ---------------------------------------------------------------------------------------------
// The parsed ELF.

struct zkvm_phdr = {
  ptype  : int,
  flags  : bits(32),
  offset : int,
  vaddr  : int,
  paddr  : int,
  filesz : int,
  memsz  : int,
}

// A named symbol of the first SHT_SYMTAB. Non-normative content: loading itself does not depend
// on it, but the reference binds host functions and main through it.
struct zkvm_symbol = {
  name  : string,
  value : xlenbits,
}

struct zkvm_elf = {
  entry   : int,
  phdrs   : list(zkvm_phdr),
  symbols : list(zkvm_symbol),
}

let ZKVM_PT_LOAD : int = 1
let ZKVM_PF_X : bits(32) = 0x00000001
let ZKVM_PF_W : bits(32) = 0x00000002
let ZKVM_PF_R : bits(32) = 0x00000004

val zkvm_parse_phdr : forall 'len, 'len >= 0. (vector('len, bits(8)), int) -> zkvm_phdr
function zkvm_parse_phdr(b, o) = struct {
  ptype  = zkvm_rd(b, o, 4),
  flags  = to_bits_truncate(zkvm_rd(b, o + 4, 4)),
  offset = zkvm_rd(b, o + 8, 8),
  vaddr  = zkvm_rd(b, o + 16, 8),
  paddr  = zkvm_rd(b, o + 24, 8),
  filesz = zkvm_rd(b, o + 32, 8),
  memsz  = zkvm_rd(b, o + 40, 8),
}

// Named symbols of the first SHT_SYMTAB section, resolved through its linked string table; none
// if the section headers or the table are missing or malformed.
val zkvm_parse_symbols : forall 'len, 'len >= 0. vector('len, bits(8)) -> list(zkvm_symbol)
function zkvm_parse_symbols(b) = {
  let size = length(b);
  let shoff = zkvm_rd(b, 40, 8);
  let shnum = zkvm_rd(b, 60, 2);
  if shoff == 0 | shnum == 0 | zkvm_rd(b, 58, 2) != 64 | shoff + shnum * 64 > size then return [||];
  var symtab : int = -1;
  foreach (i from shnum - 1 downto 0) {
    if zkvm_rd(b, shoff + i * 64 + 4, 4) == 2 then symtab = i
  };
  if symtab < 0 then return [||];
  let sh = shoff + symtab * 64;
  let link = zkvm_rd(b, sh + 40, 4);
  let off = zkvm_rd(b, sh + 24, 8);
  let len = zkvm_rd(b, sh + 32, 8);
  if link >= shnum | off + len > size then return [||];
  let strtab = zkvm_rd(b, shoff + link * 64 + 24, 8);
  var syms : list(zkvm_symbol) = [||];
  foreach (i from ediv_int(len, 24) - 1 downto 0) {
    let e = off + i * 24;
    match zkvm_cstring(b, strtab + zkvm_rd(b, e, 4)) {
      Some(name) => if name != "" then
        syms = struct { name = name, value = to_bits_truncate(zkvm_rd(b, e + 8, 8)) } :: syms,
      None() => (),
    }
  };
  syms
}

// Value of a symbol, if the ELF defines it (first match).
val zkvm_symbol_value : (list(zkvm_symbol), string) -> option(xlenbits)
function zkvm_symbol_value(syms, name) =
  match syms {
    [||] => None(),
    s :: rest => if s.name == name then Some(s.value) else zkvm_symbol_value(rest, name),
  }

// ---------------------------------------------------------------------------------------------
// The memory map.

// Permission of a memory region the loader maps.
enum zkvm_perm = { ZKVM_PERM_R, ZKVM_PERM_RW, ZKVM_PERM_X, ZKVM_PERM_RX }

struct zkvm_region = {
  base : bits(64),
  size : bits(64),
  perm : zkvm_perm,
}

// What last painted a run of pages.
enum zkvm_painter = { ZKVM_PAINT_INPUT, ZKVM_PAINT_RAM, ZKVM_PAINT_STACK, ZKVM_PAINT_SEGMENT }

// Pages first ..= last, painted with a permission.
struct zkvm_pages = {
  first   : int,
  last    : int,
  perm    : zkvm_perm,
  painter : zkvm_painter,
}

// Permission given to a page holding a segment with these flags.
function zkvm_seg_perm(flags : bits(32)) -> zkvm_perm =
  if (flags & ZKVM_PF_X) != zeros() then
    (if (flags & ZKVM_PF_R) != zeros() then ZKVM_PERM_RX else ZKVM_PERM_X)
  else if (flags & ZKVM_PF_W) != zeros() then ZKVM_PERM_RW
  else ZKVM_PERM_R

let zkvm_page : int = 4096

// `ps` with the pages first ..= last removed.
val zkvm_unpaint : (list(zkvm_pages), int, int) -> list(zkvm_pages)
function zkvm_unpaint(ps, first, last) =
  match ps {
    [||] => [||],
    p :: rest => {
      let rest' = zkvm_unpaint(rest, first, last);
      let rest'' = if last + 1 <= p.last then
        struct { first = if last + 1 > p.first then last + 1 else p.first, last = p.last,
                 perm = p.perm, painter = p.painter } :: rest'
        else rest';
      if p.first <= first - 1 then
        struct { first = p.first, last = if first - 1 < p.last then first - 1 else p.last,
                 perm = p.perm, painter = p.painter } :: rest''
      else rest''
    },
  }

// Paint the pages of the non-empty range [base, base + size).
function zkvm_paint(ps : list(zkvm_pages), base : int, size : int, perm : zkvm_perm,
                    painter : zkvm_painter) -> list(zkvm_pages) =
  if size == 0 then ps else {
    let first = ediv_int(base, zkvm_page);
    let last = ediv_int(base + size - 1, zkvm_page);
    struct { first = first, last = last, perm = perm, painter = painter } :: zkvm_unpaint(ps, first, last)
  }

// The run containing page `pg`, if any.
val zkvm_page_at : (list(zkvm_pages), int) -> option(zkvm_pages)
function zkvm_page_at(ps, pg) =
  match ps {
    [||] => None(),
    p :: rest => if p.first <= pg & pg <= p.last then Some(p) else zkvm_page_at(rest, pg),
  }

// Some mapped page lies entirely inside the range r.
val zkvm_maps_into : (list(zkvm_pages), zkvm_range) -> bool
function zkvm_maps_into(ps, r) = {
  let lo = ediv_int(unsigned(r.base) + zkvm_page - 1, zkvm_page);
  let hi = ediv_int(unsigned(r.base) + unsigned(r.size), zkvm_page) - 1;
  match ps {
    [||] => false,
    p :: rest => (p.first <= hi & lo <= p.last & lo <= hi) | zkvm_maps_into(rest, r),
  }
}

// Insert a run into a list sorted by first page.
val zkvm_insert_pages : (zkvm_pages, list(zkvm_pages)) -> list(zkvm_pages)
function zkvm_insert_pages(p, ps) =
  match ps {
    [||] => [|p|],
    q :: rest => if p.first <= q.first then p :: ps else q :: zkvm_insert_pages(p, rest),
  }

val zkvm_sort_pages : list(zkvm_pages) -> list(zkvm_pages)
function zkvm_sort_pages(ps) =
  match ps {
    [||] => [||],
    p :: rest => zkvm_insert_pages(p, zkvm_sort_pages(rest)),
  }

// Sorted runs to regions, merging adjacent runs with the same permission.
val zkvm_regions_of : list(zkvm_pages) -> list(zkvm_region)
function zkvm_regions_of(ps) =
  match ps {
    [||] => [||],
    p :: rest => {
      let base : bits(64) = to_bits_truncate(p.first * zkvm_page);
      let size : bits(64) = to_bits_truncate((p.last - p.first + 1) * zkvm_page);
      let rs = zkvm_regions_of(rest);
      match rs {
        [||] => [| struct { base = base, size = size, perm = p.perm } |],
        r :: tail =>
          if r.perm == p.perm & unsigned(r.base) == (p.last + 1) * zkvm_page
          then struct { base = base, size = size + r.size, perm = p.perm } :: tail
          else struct { base = base, size = size, perm = p.perm } :: rs,
      }
    },
  }

// ---------------------------------------------------------------------------------------------
// Validation.

// A validated program: its ELF and its memory map.
struct zkvm_image = {
  elf     : zkvm_elf,
  regions : list(zkvm_region),
}

function zkvm_is_load(ph : zkvm_phdr) -> bool = ph.ptype == ZKVM_PT_LOAD
function zkvm_is_exec(ph : zkvm_phdr) -> bool = (ph.flags & ZKVM_PF_X) != zeros()

val zkvm_loads : list(zkvm_phdr) -> list(zkvm_phdr)
function zkvm_loads(phs) =
  match phs {
    [||] => [||],
    ph :: rest => if zkvm_is_load(ph) then ph :: zkvm_loads(rest) else zkvm_loads(rest),
  }

// The per-segment checks, in program-header order; the first failure.
val zkvm_check_segments : (zkvm_memory_profile, int, list(zkvm_phdr)) -> option(string)
function zkvm_check_segments(p, size, phs) =
  match phs {
    [||] => None(),
    ph :: rest => {
      let h = hex_str(ph.vaddr);
      let space = p.address_space;
      let want : bits(32) = match p.exec_perm {
        ZKVM_EXEC_X => ZKVM_PF_X,
        ZKVM_EXEC_RX => ZKVM_PF_X | ZKVM_PF_R,
      };
      if ph.filesz > ph.memsz then Some("segment " ^ h ^ ": p_filesz > p_memsz")
      else if ph.offset + ph.filesz > size then Some("segment " ^ h ^ ": file data outside the file")
      else if emod_int(ph.vaddr, 4) != 0 then Some("segment " ^ h ^ ": p_vaddr not 4-byte aligned")
      else if not(unsigned(space.base) <= ph.vaddr &
                  ph.vaddr + ph.memsz <= unsigned(space.base) + unsigned(space.size)) then
        Some("segment " ^ h ^ ": outside the addressable space")
      else if (ph.flags & ZKVM_PF_W) != zeros() & zkvm_is_exec(ph) then
        Some("segment " ^ h ^ ": W^X violated")
      else if zkvm_is_exec(ph) & (ph.flags & (ZKVM_PF_X | ZKVM_PF_R)) != want then
        Some("segment " ^ h ^ ": executable flags do not match profile")
      else zkvm_check_segments(p, size, rest)
    },
  }

val zkvm_insert_phdr : (zkvm_phdr, list(zkvm_phdr)) -> list(zkvm_phdr)
function zkvm_insert_phdr(ph, phs) =
  match phs {
    [||] => [|ph|],
    q :: rest => if ph.vaddr <= q.vaddr then ph :: phs else q :: zkvm_insert_phdr(ph, rest),
  }

// Non-empty segments sorted by vaddr (stable).
val zkvm_sorted_nonempty : list(zkvm_phdr) -> list(zkvm_phdr)
function zkvm_sorted_nonempty(phs) =
  match phs {
    [||] => [||],
    ph :: rest => {
      let sorted = zkvm_sorted_nonempty(rest);
      if ph.memsz == 0 then sorted else zkvm_insert_phdr(ph, sorted)
    },
  }

val zkvm_first_overlap_with : (zkvm_phdr, list(zkvm_phdr)) -> option(zkvm_phdr)
function zkvm_first_overlap_with(a, phs) =
  match phs {
    [||] => None(),
    c :: rest => if c.vaddr < a.vaddr + a.memsz then Some(c) else zkvm_first_overlap_with(a, rest),
  }

// The first pair (a, c), a before c in the sorted list, of overlapping segments.
val zkvm_first_overlap : list(zkvm_phdr) -> option(string)
function zkvm_first_overlap(phs) =
  match phs {
    [||] => None(),
    a :: rest => match zkvm_first_overlap_with(a, rest) {
      Some(c) => Some("segments " ^ hex_str(a.vaddr) ^ " and " ^ hex_str(c.vaddr) ^ " overlap"),
      None() => zkvm_first_overlap(rest),
    },
  }

val zkvm_entry_in_exec : (int, list(zkvm_phdr)) -> bool
function zkvm_entry_in_exec(entry, phs) =
  match phs {
    [||] => false,
    ph :: rest => (zkvm_is_exec(ph) & ph.vaddr <= entry & entry < ph.vaddr + ph.memsz) |
                  zkvm_entry_in_exec(entry, rest),
  }

// Paint each non-empty segment's pages over ram pages, checking each page in increasing order:
// it must be ram or already hold a segment with the same permission.
val zkvm_paint_segments : (list(zkvm_pages), list(zkvm_phdr)) -> result(list(zkvm_pages), string)
function zkvm_paint_segments(ps, phs) =
  match phs {
    [||] => Ok(ps),
    ph :: rest => if ph.memsz == 0 then zkvm_paint_segments(ps, rest) else {
      let perm = zkvm_seg_perm(ph.flags);
      let first = ediv_int(ph.vaddr, zkvm_page);
      let last = ediv_int(ph.vaddr + ph.memsz - 1, zkvm_page);
      foreach (pg from first to last) {
        let ok : bool = match zkvm_page_at(ps, pg) {
          Some(q) => q.painter == ZKVM_PAINT_RAM | (q.painter == ZKVM_PAINT_SEGMENT & q.perm == perm),
          None() => false,
        };
        if not(ok) then {
          let shared : bool = match zkvm_page_at(ps, pg) {
            Some(q) => q.painter == ZKVM_PAINT_SEGMENT,
            None() => false,
          };
          let at = hex_str(pg * zkvm_page);
          if shared then return Err("page " ^ at ^ " shared by segments with different permissions")
          else return Err("segment page " ^ at ^ " outside ram")
        }
      };
      zkvm_paint_segments(zkvm_paint(ps, ph.vaddr, ph.memsz, perm, ZKVM_PAINT_SEGMENT), rest)
    },
  }

// Symbols the loader requires: the library entry point and I/O functions, and the guest's main.
let zkvm_required_symbols : list(string) =
  [| zkvm_host_symbol(ZKVM_START), "main", zkvm_host_symbol(ZKVM_READ_INPUT),
     zkvm_host_symbol(ZKVM_WRITE_OUTPUT) |]

val zkvm_first_missing : (list(zkvm_symbol), list(string)) -> option(string)
function zkvm_first_missing(syms, names) =
  match names {
    [||] => None(),
    n :: rest => match zkvm_symbol_value(syms, n) {
      None() => Some(n),
      Some(_) => zkvm_first_missing(syms, rest),
    },
  }

// Validate an ELF against the memory profile and compute its memory map. The checks run in a
// fixed order; the first failure is reported.
val zkvm_validate : forall 'len, 'len >= 0.
  (zkvm_memory_profile, vector('len, bits(8))) -> result(zkvm_image, string)
function zkvm_validate(p, b) = {
  let size = length(b);
  // Header.
  // "\x7fELF" read as a little-endian 32-bit integer.
  if size < 64 | zkvm_rd(b, 0, 4) != 1179403647 then return Err("bad magic");
  if zkvm_rd(b, 4, 1) != 2 then return Err("class is not ELFCLASS64");
  if zkvm_rd(b, 5, 1) != 1 then return Err("not ELFDATA2LSB");
  if zkvm_rd(b, 18, 2) != 243 then return Err("e_machine is not EM_RISCV");
  if zkvm_rd(b, 16, 2) != 2 then return Err("e_type is not ET_EXEC");
  let phoff = zkvm_rd(b, 32, 8);
  let phnum = zkvm_rd(b, 56, 2);
  if zkvm_rd(b, 54, 2) != 56 | phoff + phnum * 56 > size then
    return Err("program headers outside the file");
  var phdrs : list(zkvm_phdr) = [||];
  foreach (i from phnum - 1 downto 0) phdrs = zkvm_parse_phdr(b, phoff + i * 56) :: phdrs;
  let elf : zkvm_elf = struct { entry = zkvm_rd(b, 24, 8), phdrs = phdrs, symbols = zkvm_parse_symbols(b) };
  let loads = zkvm_loads(phdrs);
  // Segments.
  match zkvm_check_segments(p, size, loads) { Some(m) => return Err(m), None() => () };
  match zkvm_first_overlap(zkvm_sorted_nonempty(loads)) { Some(m) => return Err(m), None() => () };
  // Entry point.
  if emod_int(elf.entry, 4) != 0 then return Err("e_entry not 4-byte aligned");
  if not(zkvm_entry_in_exec(elf.entry, loads)) then return Err("e_entry not inside an executable segment");
  match p.boot_addr {
    Some(boot) => if elf.entry != unsigned(boot) then return Err("e_entry differs from the fixed boot address"),
    None() => (),
  };
  // Memory map: input, ram and stack, then segments over ram.
  var ps : list(zkvm_pages) = [||];
  ps = zkvm_paint(ps, unsigned(p.input.base), unsigned(p.input.size), ZKVM_PERM_R, ZKVM_PAINT_INPUT);
  ps = zkvm_paint(ps, unsigned(p.ram.base), unsigned(p.ram.size), ZKVM_PERM_RW, ZKVM_PAINT_RAM);
  ps = zkvm_paint(ps, unsigned(p.stack.base), unsigned(p.stack.size), ZKVM_PERM_RW, ZKVM_PAINT_STACK);
  match zkvm_paint_segments(ps, loads) {
    Ok(ps') => ps = ps',
    Err(m) => return Err(m),
  };
  if zkvm_maps_into(ps, zkvm_null_page) then return Err("null page is mapped");
  if zkvm_maps_into(ps, zkvm_stack_guard(p)) then return Err("stack guard page is mapped");
  // Symbols the loader binds.
  match zkvm_first_missing(elf.symbols, zkvm_required_symbols) {
    Some(n) => return Err("missing symbol " ^ n),
    None() => (),
  };
  Ok(struct { elf = elf, regions = zkvm_regions_of(zkvm_sort_pages(ps)) })
}

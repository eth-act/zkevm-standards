// Host functions: the functions of the zkVM static library (standards/io-interface,
// standards/accelerated-memory-operations, standards/c-interface-accelerators,
// standards/static-library-and-linker-script): which functions exist, their symbols, when they
// are invoked, and what each does. Accelerator semantics are not given: calling one halts the
// run with ZKVM_Unspecified.

enum zkvm_host_fn = {
  // entry point; calls main and passes its return value to the termination mechanism
  ZKVM_START,
  // void read_input(const uint8_t** buf_ptr, size_t* buf_size);
  ZKVM_READ_INPUT,
  // void write_output(const uint8_t* output, size_t size);
  ZKVM_WRITE_OUTPUT,
  // void *memcpy(void *dest, const void *src, size_t n)
  ZKVM_MEMCPY,
  // void *memmove(void *dest, const void *src, size_t n)
  ZKVM_MEMMOVE,
  // void *memset(void *dest, int c, size_t n)
  ZKVM_MEMSET,
  // int   memcmp(const void *lhs, const void *rhs, size_t n)
  ZKVM_MEMCMP,
  // zkvm_status zkvm_keccak256(const uint8_t* data, size_t len, zkvm_keccak256_hash* output);
  ZKVM_KECCAK256,
  // zkvm_status zkvm_secp256k1_verify(const zkvm_secp256k1_hash* msg, const zkvm_secp256k1_signature* sig, const zkvm_secp256k1_pubkey* pubkey, bool* verified);
  ZKVM_SECP256K1_VERIFY,
  // zkvm_status zkvm_secp256k1_ecrecover(const zkvm_secp256k1_hash* msg, const zkvm_secp256k1_signature* sig, uint8_t recid, zkvm_secp256k1_pubkey* output);
  ZKVM_SECP256K1_ECRECOVER,
  // zkvm_status zkvm_sha256(const uint8_t* data, size_t len, zkvm_sha256_hash* output);
  ZKVM_SHA256,
  // zkvm_status zkvm_ripemd160(const uint8_t* data, size_t len, zkvm_ripemd160_hash* output);
  ZKVM_RIPEMD160,
  // zkvm_status zkvm_modexp(const uint8_t* base, size_t base_len, const uint8_t* exp, size_t exp_len, const uint8_t* modulus, size_t mod_len, uint8_t* output);
  ZKVM_MODEXP,
  // zkvm_status zkvm_bn254_g1_add(const zkvm_bn254_g1_point* p1, const zkvm_bn254_g1_point* p2, zkvm_bn254_g1_point* result);
  ZKVM_BN254_G1_ADD,
  // zkvm_status zkvm_bn254_g1_mul(const zkvm_bn254_g1_point* point, const zkvm_bn254_scalar* scalar, zkvm_bn254_g1_point* result);
  ZKVM_BN254_G1_MUL,
  // zkvm_status zkvm_bn254_pairing(const zkvm_bn254_pairing_pair* pairs, size_t num_pairs, bool* verified);
  ZKVM_BN254_PAIRING,
  // zkvm_status zkvm_blake2f(uint32_t rounds, zkvm_blake2f_state* h, const zkvm_blake2f_message* m, const zkvm_blake2f_offset* t, uint8_t f);
  ZKVM_BLAKE2F,
  // zkvm_status zkvm_kzg_point_eval(const zkvm_kzg_commitment* commitment, const zkvm_kzg_field_element* z, const zkvm_kzg_field_element* y, const zkvm_kzg_proof* proof, bool* verified);
  ZKVM_KZG_POINT_EVAL,
  // zkvm_status zkvm_bls12_g1_add(const zkvm_bls12_381_g1_point* p1, const zkvm_bls12_381_g1_point* p2, zkvm_bls12_381_g1_point* result);
  ZKVM_BLS12_G1_ADD,
  // zkvm_status zkvm_bls12_g1_msm(const zkvm_bls12_381_g1_msm_pair* pairs, size_t num_pairs, zkvm_bls12_381_g1_point* result);
  ZKVM_BLS12_G1_MSM,
  // zkvm_status zkvm_bls12_g2_add(const zkvm_bls12_381_g2_point* p1, const zkvm_bls12_381_g2_point* p2, zkvm_bls12_381_g2_point* result);
  ZKVM_BLS12_G2_ADD,
  // zkvm_status zkvm_bls12_g2_msm(const zkvm_bls12_381_g2_msm_pair* pairs, size_t num_pairs, zkvm_bls12_381_g2_point* result);
  ZKVM_BLS12_G2_MSM,
  // zkvm_status zkvm_bls12_pairing(const zkvm_bls12_381_pairing_pair* pairs, size_t num_pairs, bool* verified);
  ZKVM_BLS12_PAIRING,
  // zkvm_status zkvm_bls12_map_fp_to_g1(const zkvm_bls12_381_fp* field_element, zkvm_bls12_381_g1_point* result);
  ZKVM_BLS12_MAP_FP_TO_G1,
  // zkvm_status zkvm_bls12_map_fp2_to_g2(const zkvm_bls12_381_fp2* field_element, zkvm_bls12_381_g2_point* result);
  ZKVM_BLS12_MAP_FP2_TO_G2,
  // zkvm_status zkvm_secp256r1_verify(const zkvm_secp256r1_hash* msg, const zkvm_secp256r1_signature* sig, const zkvm_secp256r1_pubkey* pubkey, bool* verified);
  ZKVM_SECP256R1_VERIFY
}

// Every host function, in declaration order.
let zkvm_host_fns : list(zkvm_host_fn) = [|
  ZKVM_START,
  ZKVM_READ_INPUT,
  ZKVM_WRITE_OUTPUT,
  ZKVM_MEMCPY,
  ZKVM_MEMMOVE,
  ZKVM_MEMSET,
  ZKVM_MEMCMP,
  ZKVM_KECCAK256,
  ZKVM_SECP256K1_VERIFY,
  ZKVM_SECP256K1_ECRECOVER,
  ZKVM_SHA256,
  ZKVM_RIPEMD160,
  ZKVM_MODEXP,
  ZKVM_BN254_G1_ADD,
  ZKVM_BN254_G1_MUL,
  ZKVM_BN254_PAIRING,
  ZKVM_BLAKE2F,
  ZKVM_KZG_POINT_EVAL,
  ZKVM_BLS12_G1_ADD,
  ZKVM_BLS12_G1_MSM,
  ZKVM_BLS12_G2_ADD,
  ZKVM_BLS12_G2_MSM,
  ZKVM_BLS12_PAIRING,
  ZKVM_BLS12_MAP_FP_TO_G1,
  ZKVM_BLS12_MAP_FP2_TO_G2,
  ZKVM_SECP256R1_VERIFY
|]

// The symbol the static library exports for each host function.
function zkvm_host_symbol(f : zkvm_host_fn) -> string =
  match f {
    ZKVM_START => "_start",
    ZKVM_READ_INPUT => "read_input",
    ZKVM_WRITE_OUTPUT => "write_output",
    ZKVM_MEMCPY => "memcpy",
    ZKVM_MEMMOVE => "memmove",
    ZKVM_MEMSET => "memset",
    ZKVM_MEMCMP => "memcmp",
    ZKVM_KECCAK256 => "zkvm_keccak256",
    ZKVM_SECP256K1_VERIFY => "zkvm_secp256k1_verify",
    ZKVM_SECP256K1_ECRECOVER => "zkvm_secp256k1_ecrecover",
    ZKVM_SHA256 => "zkvm_sha256",
    ZKVM_RIPEMD160 => "zkvm_ripemd160",
    ZKVM_MODEXP => "zkvm_modexp",
    ZKVM_BN254_G1_ADD => "zkvm_bn254_g1_add",
    ZKVM_BN254_G1_MUL => "zkvm_bn254_g1_mul",
    ZKVM_BN254_PAIRING => "zkvm_bn254_pairing",
    ZKVM_BLAKE2F => "zkvm_blake2f",
    ZKVM_KZG_POINT_EVAL => "zkvm_kzg_point_eval",
    ZKVM_BLS12_G1_ADD => "zkvm_bls12_g1_add",
    ZKVM_BLS12_G1_MSM => "zkvm_bls12_g1_msm",
    ZKVM_BLS12_G2_ADD => "zkvm_bls12_g2_add",
    ZKVM_BLS12_G2_MSM => "zkvm_bls12_g2_msm",
    ZKVM_BLS12_PAIRING => "zkvm_bls12_pairing",
    ZKVM_BLS12_MAP_FP_TO_G1 => "zkvm_bls12_map_fp_to_g1",
    ZKVM_BLS12_MAP_FP2_TO_G2 => "zkvm_bls12_map_fp2_to_g2",
    ZKVM_SECP256R1_VERIFY => "zkvm_secp256r1_verify",
  }

// Accelerators (standards/c-interface-accelerators). Their semantics are left unspecified.
function zkvm_host_is_accelerator(f : zkvm_host_fn) -> bool =
  match f {
    ZKVM_START => false,
    ZKVM_READ_INPUT => false,
    ZKVM_WRITE_OUTPUT => false,
    ZKVM_MEMCPY => false,
    ZKVM_MEMMOVE => false,
    ZKVM_MEMSET => false,
    ZKVM_MEMCMP => false,
    ZKVM_KECCAK256 => true,
    ZKVM_SECP256K1_VERIFY => true,
    ZKVM_SECP256K1_ECRECOVER => true,
    ZKVM_SHA256 => true,
    ZKVM_RIPEMD160 => true,
    ZKVM_MODEXP => true,
    ZKVM_BN254_G1_ADD => true,
    ZKVM_BN254_G1_MUL => true,
    ZKVM_BN254_PAIRING => true,
    ZKVM_BLAKE2F => true,
    ZKVM_KZG_POINT_EVAL => true,
    ZKVM_BLS12_G1_ADD => true,
    ZKVM_BLS12_G1_MSM => true,
    ZKVM_BLS12_G2_ADD => true,
    ZKVM_BLS12_G2_MSM => true,
    ZKVM_BLS12_PAIRING => true,
    ZKVM_BLS12_MAP_FP_TO_G1 => true,
    ZKVM_BLS12_MAP_FP2_TO_G2 => true,
    ZKVM_SECP256R1_VERIFY => true,
  }

// A host-function symbol bound to its address.
struct zkvm_host_binding = {
  addr : xlenbits,
  func : zkvm_host_fn,
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
val zkvm_host_lookup : (list(zkvm_host_binding), xlenbits) -> option(zkvm_host_fn)
function zkvm_host_lookup(table, pc) =
  match table {
    [||] => None(),
    b :: rest => if b.addr == pc then Some(b.func) else zkvm_host_lookup(rest, pc),
  }

// A static-library call is the PC reaching a bound symbol address; zkvm_step then performs the
// host function instead of fetching.
function zkvm_host_at(pc : xlenbits) -> option(zkvm_host_fn) = zkvm_host_lookup(zkvm_host_table, pc)

// Checked byte access for host functions: a data load or store with the guest's
// permissions; None()/false when the access would trap.
function zkvm_load_byte(addr : xlenbits) -> option(bits(8)) =
  match vmem_read_addr(Virtaddr(addr), 1, Load(Data), false, false, false) {
    Ok(b) => Some(b),
    Err(_) => None(),
  }

function zkvm_store_byte(addr : xlenbits, b : bits(8)) -> bool =
  match vmem_write_addr(Virtaddr(addr), 1, b, Store(Data), false, false, false) {
    Ok(_) => true,
    Err(_) => false,
  }

// ---------------------------------------------------------------------------------------------
// Semantics of the host functions.
//
// Calling convention (RISC-V psABI): arguments in a0..a2 (x10..x12), result in a0, return
// address in ra (x1). Integer register convention:
// https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/56561cb3e7330fe99a98fd27457229707b2786ae/riscv-cc.adoc?plain=1#L9-L27
// Integer calling convention:
// https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/56561cb3e7330fe99a98fd27457229707b2786ae/riscv-cc.adoc?plain=1#L176-L180
//
// Address arithmetic wraps at 64 bits and sizes are full 64-bit register values. Memory is
// accessed byte by byte with the guest's permissions; the first failing access ends the run
// with a fault and the function does not return.

// Continue at the return address.
function zkvm_ret() -> unit = {
  set_next_pc(rX(Regno(1)));
  tick_pc()
}

// Store `v` little-endian at `a` (a pointer or size_t is xlen bits); false at the first failing
// store.
function zkvm_store_xlen(a : xlenbits, v : xlenbits) -> bool = {
  foreach (i from 0 to xlen_bytes - 1) {
    if not(zkvm_store_byte(a + i, v[8 * i + 7 .. 8 * i])) then return false
  };
  true
}

// The `n` bytes at `a` are all readable.
function zkvm_readable(a : xlenbits, n : int) -> bool = {
  var p = a;
  foreach (i from 1 to n) {
    match zkvm_load_byte(p) { Some(_) => (), None() => return false };
    p = p + 1
  };
  true
}

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

// read_input(buf_ptr, buf_size): *buf_ptr := input address, *buf_size := input size.
function zkvm_read_input() -> unit =
  if not(zkvm_store_xlen(rX(Regno(10)), zkvm_profile.input.base)) then zkvm_host_fault()
  else if not(zkvm_store_xlen(rX(Regno(11)), zkvm_input_size)) then zkvm_host_fault()
  else zkvm_ret()

// write_output(output, size): append the `size` bytes at `output` to the public output; if any
// of them is unreadable, fault without appending anything.
function zkvm_write_output() -> unit = {
  let a = rX(Regno(10));
  let n = unsigned(rX(Regno(11)));
  if not(zkvm_readable(a, n)) then { zkvm_host_fault(); return () };
  var p = a;
  foreach (i from 1 to n) {
    match zkvm_load_byte(p) { Some(b) => zkvm_output_rev = b :: zkvm_output_rev, None() => () };
    p = p + 1
  };
  zkvm_ret()
}

// memcpy(dest, src, n): for each i < n in increasing order, copy byte src + i to dest + i.
// Returns dest (a0 unchanged).
function zkvm_memcpy() -> unit = {
  let dest = rX(Regno(10));
  let src = rX(Regno(11));
  foreach (i from 0 to unsigned(rX(Regno(12))) - 1) {
    match zkvm_load_byte(src + i) {
      None() => { zkvm_host_fault(); return () },
      Some(b) => if not(zkvm_store_byte(dest + i, b)) then { zkvm_host_fault(); return () },
    }
  };
  zkvm_ret()
}

// memmove(dest, src, n): as if all n source bytes were first copied to a temporary buffer, so the
// regions may overlap. Faults before storing anything if a source byte is unreadable; otherwise
// copies in the direction that reads each source byte before it is overwritten. Returns dest.
function zkvm_memmove() -> unit = {
  let dest = rX(Regno(10));
  let src = rX(Regno(11));
  let n = unsigned(rX(Regno(12)));
  if not(zkvm_readable(src, n)) then { zkvm_host_fault(); return () };
  // Byte src + i is overwritten by an earlier forward store exactly when 0 < dest - src < n.
  let d = unsigned(dest - src);
  if d == 0 | d >= n then {
    foreach (i from 0 to n - 1) {
      match zkvm_load_byte(src + i) {
        None() => { zkvm_host_fault(); return () },
        Some(b) => if not(zkvm_store_byte(dest + i, b)) then { zkvm_host_fault(); return () },
      }
    }
  } else {
    foreach (i from n - 1 downto 0) {
      match zkvm_load_byte(src + i) {
        None() => { zkvm_host_fault(); return () },
        Some(b) => if not(zkvm_store_byte(dest + i, b)) then { zkvm_host_fault(); return () },
      }
    }
  };
  zkvm_ret()
}

// memset(dest, c, n): store c & 0xff at dest + i for each i < n. Returns dest.
function zkvm_memset() -> unit = {
  let dest = rX(Regno(10));
  let c = rX(Regno(11))[7 .. 0];
  foreach (i from 0 to unsigned(rX(Regno(12))) - 1) {
    if not(zkvm_store_byte(dest + i, c)) then { zkvm_host_fault(); return () }
  };
  zkvm_ret()
}

// memcmp(lhs, rhs, n): compare unsigned bytes in increasing order up to the first difference;
// a0 := -1, 1 or 0.
function zkvm_memcmp() -> unit = {
  let lhs = rX(Regno(10));
  let rhs = rX(Regno(11));
  foreach (i from 0 to unsigned(rX(Regno(12))) - 1) {
    match (zkvm_load_byte(lhs + i), zkvm_load_byte(rhs + i)) {
      (Some(x), Some(y)) =>
        if x != y then {
          wX(Regno(10), if unsigned(x) < unsigned(y) then ones() else zero_extend(0b1));
          zkvm_ret();
          return ()
        },
      _ => { zkvm_host_fault(); return () },
    }
  };
  wX(Regno(10), zeros());
  zkvm_ret()
}

// Perform host function `f`.
function zkvm_host_call(f : zkvm_host_fn) -> unit =
  match f {
    ZKVM_START        => zkvm_start(),
    ZKVM_READ_INPUT   => zkvm_read_input(),
    ZKVM_WRITE_OUTPUT => zkvm_write_output(),
    ZKVM_MEMCPY       => zkvm_memcpy(),
    ZKVM_MEMMOVE      => zkvm_memmove(),
    ZKVM_MEMSET       => zkvm_memset(),
    ZKVM_MEMCMP       => zkvm_memcmp(),
    _                 => zkvm_halt_with(ZKVM_Unspecified(zkvm_host_symbol(f))),
  }

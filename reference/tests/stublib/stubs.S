# Stub static library for the reference tests: one 4-byte label per library symbol.
# Never executed; the machine performs the host function when the PC reaches the symbol
# (reference/sail/zkvm/zkvm_host.sail, reference/lean/ZkvmRef/Host.lean).
  .section .text
  .balign 4
  .globl _start
_start:
  unimp
  .globl read_input
read_input:
  unimp
  .globl write_output
write_output:
  unimp
  .globl memcpy
memcpy:
  unimp
  .globl memmove
memmove:
  unimp
  .globl memset
memset:
  unimp
  .globl memcmp
memcmp:
  unimp
  .globl zkvm_keccak256
zkvm_keccak256:
  unimp
  .globl zkvm_secp256k1_verify
zkvm_secp256k1_verify:
  unimp
  .globl zkvm_secp256k1_ecrecover
zkvm_secp256k1_ecrecover:
  unimp
  .globl zkvm_sha256
zkvm_sha256:
  unimp
  .globl zkvm_ripemd160
zkvm_ripemd160:
  unimp
  .globl zkvm_modexp
zkvm_modexp:
  unimp
  .globl zkvm_bn254_g1_add
zkvm_bn254_g1_add:
  unimp
  .globl zkvm_bn254_g1_mul
zkvm_bn254_g1_mul:
  unimp
  .globl zkvm_bn254_pairing
zkvm_bn254_pairing:
  unimp
  .globl zkvm_blake2f
zkvm_blake2f:
  unimp
  .globl zkvm_kzg_point_eval
zkvm_kzg_point_eval:
  unimp
  .globl zkvm_bls12_g1_add
zkvm_bls12_g1_add:
  unimp
  .globl zkvm_bls12_g1_msm
zkvm_bls12_g1_msm:
  unimp
  .globl zkvm_bls12_g2_add
zkvm_bls12_g2_add:
  unimp
  .globl zkvm_bls12_g2_msm
zkvm_bls12_g2_msm:
  unimp
  .globl zkvm_bls12_pairing
zkvm_bls12_pairing:
  unimp
  .globl zkvm_bls12_map_fp_to_g1
zkvm_bls12_map_fp_to_g1:
  unimp
  .globl zkvm_bls12_map_fp2_to_g2
zkvm_bls12_map_fp2_to_g2:
  unimp
  .globl zkvm_secp256r1_verify
zkvm_secp256r1_verify:
  unimp

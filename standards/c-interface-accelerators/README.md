# zkVM Cryptographic Accelerators C Interface

This standard defines the C interface for accessing accelerators in zkVMs, primarily based on the precompiles needed in the Ethereum Virtual Machine(EVM).

## Overview

zkVMs can provide optimized implementations of common cryptographic operations used in Ethereum. This standard defines a portable C API for guest programs to access these accelerators.

Note: The interface is based on Ethereum precompiles but simplified to expose raw cryptographic operations without Ethereum-specific constraints where feasible.

## Header File

See [`zkvm_accelerators.h`](./zkvm_accelerators.h) for the complete interface that a guest program can use. The functions in the header file will be implemented by the appropriate zkVM.

## Normative requirements

Each requirement has an ID. "Checked by" names where it is enforced or tested: `Sail` (the reference in `reference/sail/`), `Lean` (a statement in `reference/lean/ZkvmRef/`), `monitor` (a guest test in eth-act/zkevm-test-monitor), `monitor-static` (a static check there), or `not tested` with the reason.

| ID | Requirement | Applies to | Checked by |
| --- | --- | --- | --- |
| ACC1 | The functions in `zkvm_accelerators.h` are implemented by the zkVM's library. | vendor library | Sail, monitor |
| ACC2 | The caller MUST ensure all pointers are valid. | guest | not tested: guest obligation |
| ACC3 | If a function is called with a NULL pointer, the function SHOULD panic. | vendor library | monitor |
| ACC4 | The caller SHOULD allocate and free the input and output memory. | guest | not tested: guest obligation |
| ACC5 | Each function returns `ZKVM_EOK` (0) on success and `ZKVM_EFAIL` on failure. | vendor library | monitor |
| ACC6 | Each function computes its documented operation with the documented encodings (for example, the RIPEMD-160 output's first 12 bytes are zero, the `modexp` output is exactly `mod_len` bytes, `blake2f` uses the documented endianness). | vendor library | monitor, not tested in Sail: semantics unspecified (#61) |

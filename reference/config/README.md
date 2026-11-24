# sail-riscv configuration

`../scripts/make-config.py OUT` writes the configuration of the reference machine
(`../build/config/zkvm.json`):

1. Fill sail-riscv's `config/config.json.in` with the values its CMake uses for
   `rv64d_v256_e64.json` (XLEN 64) and drop the `//` comment lines.
2. Disable every extension: each `supported` key under `extensions` becomes `false`, and each
   `support_level` (the vector extensions) becomes `"Disabled"`.
3. Deep-merge `riscv-target.json`, then `platform.json` (objects merge recursively, any other value
   replaces).

Rule: `riscv-target.json` lists the enabled extensions; every other extension is disabled. [TGT1]
[TGT2] The target is `riscv64im_zicclsm`: `M` and `Zicclsm` are the only enabled extensions, so the
encodings of `C`, `F`, `D` and every other extension decode as illegal instructions and trap. [TGT4]
No supervisor mode or paging is configured: memory is flat, physical, and little-endian.

| File                | Standard      | Contents                                                  |
| ------------------- | ------------- | --------------------------------------------------------- |
| `riscv-target.json` | riscv-target  | `M` and `Zicclsm` enabled, F and V state off, misaligned  |
|                     |               | loads and stores never trap                               |
| `platform.json`     | zkVM platform | no PMP entries, no CLINT, no interrupt generator, no      |
|                     |               | configured memory regions (the loader installs the memory |
|                     |               | map)                                                      |

Sail evaluates configuration values at generation time (`sail --config`), so the configuration is
baked into the generated Lean model; changing it requires rerunning `../scripts/build-lean.sh`.

## Zicclsm

[TGT5][TGT6]

Zicclsm defines no instructions; it requires misaligned loads and stores to main memory to succeed.
In the reference machine that is three settings:

- `extensions.Zicclsm.supported: true` (`riscv-target.json`), so the hart reports Zicclsm;
- `memory.misaligned.exceptions.load_store: None` (`riscv-target.json`), so `vmem_read_addr` and
  `vmem_write_addr` split a misaligned access instead of raising an address-misaligned or
  access-fault exception;
- `misaligned_exceptions.load_store = none` in every memory region the loader installs
  (`zkvm_pma_region` in `../sail/zkvm/zkvm_install.sail`), so the regions accept the split accesses.

`../tests/guests/misaligned_load.c` checks the result: an 8-byte load from and store to odd
addresses succeed and the run reports `misaligned=2`.

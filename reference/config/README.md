# sail-riscv configuration

`../scripts/make-config.py OUT` writes the configuration of the reference machine
(`../build/config/zkvm.json`):

1. Fill sail-riscv's `config/config.json.in` with the values its CMake uses for
   `rv64d_v256_e64.json` (XLEN 64) and drop the `//` comment lines.
2. Disable every extension: each `supported` key under `extensions` becomes `false`, and each
   `support_level` (the vector extensions) becomes `"Disabled"`.
3. Deep-merge `riscv-target.json`, then `platform.json` (objects merge recursively, any other value
   replaces).

Rule: `riscv-target.json` lists the enabled extensions; every other extension is disabled.

| File                | Standard      | Contents                                                  |
| ------------------- | ------------- | --------------------------------------------------------- |
| `riscv-target.json` | riscv-target  | `M` enabled, F and V state off                            |
| `platform.json`     | zkVM platform | no PMP entries, no CLINT, no interrupt generator, no      |
|                     |               | configured memory regions (the loader installs the memory |
|                     |               | map)                                                      |

Sail evaluates configuration values at generation time (`sail --config`), so the configuration is
baked into the generated Lean model; changing it requires rerunning `../scripts/build-lean.sh`.

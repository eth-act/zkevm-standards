# Build scripts

Run from anywhere; outputs go to `../build/` (ignored).

| Script | Does | Output |
|---|---|---|
| `fetch-sail.sh` | downloads the Sail 0.20.2 binary release (skipped if present) | `build/sail-0.20.2/` |
| `prepare-sail.sh` | copies the pinned `sail-riscv`, applies `sail/hooks.patch`, adds `sail/zkvm/*.sail` as `model/zkvm/` | `build/sail-riscv/` |
| `make-config.py OUT` | builds the sail-riscv configuration from `config.json.in` and the overlays in `config/` | `build/config/zkvm.json` |
| `build-lean.sh` | runs the three above, generates the Lean model (modules `I_insts M_insts postlude zkvm_host`), patches two generated-code issues, writes `lean/ZkvmRef/RegisterDefaults.lean`, builds the model and `lean/` | `build/lean/Lean_RV64D_executable/`, `lean/.lake/build/bin/zkvm-run` |

`build-lean.sh` is the only entry point needed; it reruns the others every time.

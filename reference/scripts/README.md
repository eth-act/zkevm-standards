# Scripts

Run from anywhere; outputs go to `../build/` (ignored).

| Script               | Does                                                        | Output                               |
| -------------------- | ----------------------------------------------------------- | ------------------------------------ |
| `fetch-sail.sh`      | downloads the Sail 0.20.2 binary release (skipped if        | `build/sail-0.20.2/`                 |
|                      | present)                                                    |                                      |
| `make-config.py OUT` | builds the sail-riscv configuration from                    | `build/config/zkvm.json`             |
|                      | `sail-riscv/config/config.json.in` and the overlays in      |                                      |
|                      | `config/`                                                   |                                      |
| `build-lean.sh`      | runs the two above, generates the Lean model from           | `build/lean/Lean_RV64D_executable/`, |
|                      | `sail-riscv/model/riscv.sail_project` and                   | `lean/.lake/build/bin/zkvm-run`      |
|                      | `sail/zkvm.sail_project` (modules `I_insts M_insts postlude |                                      |
|                      | zkvm_extension_fallback zkvm_machine`), patches two         |                                      |
|                      | generated-code issues, builds the model and `lean/`         |                                      |

`build-lean.sh` is the only entry point needed; it reruns the others every time.

| Script                  | Does                                                         |
| ----------------------- | ------------------------------------------------------------ |
| `check-requirements.py` | run from the repository root: reads the `Normative           |
|                         | requirements` table of every standard and fails if a         |
|                         | requirement checked by `Sail` or `Lean` has no `[ID]` tag in |
|                         | `sail/`, `config/README.md` or `lean/`, if an ID is defined  |
|                         | twice, if a tag names an unknown ID, or if a `not tested`    |
|                         | entry gives no reason                                        |

## Markdown formatting

| Script                 | Does                                                         |
| ---------------------- | ------------------------------------------------------------ |
| `md-wrap-prose`        | markdown formatter (stdin to stdout): prettier with prose    |
|                        | wrapped at 100 columns, table cells wrapped at 60; requires  |
|                        | `python3` and `prettier`                                     |
| `install-git-hooks.sh` | sets `core.hooksPath` to `reference/githooks`, whose         |
|                        | `pre-commit` runs `md-wrap-prose` on staged markdown under   |
|                        | `reference/` and fails the commit if `python3` or `prettier` |
|                        | is missing                                                   |

Run `reference/scripts/install-git-hooks.sh` once per clone.

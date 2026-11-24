# Tests

`python3 reference/tests/run.py` (from the repository root, after `scripts/build-lean.sh`) builds
every guest for both profiles and runs it with `zkvm-run` twice (integer registers `x1`…`x31` all
zero, then a canary pattern; both runs must give the expected observation, since the standards leave
initial registers unspecified). It ends with `passed N, failed M` and exits non-zero on any failure.
Build products go to `../build/tests/`.

## Stub library and linker script

- Stub library: `run.py` generates `build/tests/stubs.S` with one `unimp` per symbol that
  `zkvm-run --list-symbols` prints (Sail's `zkvm_library`). Never executed: the machine performs the
  host function when the PC reaches the symbol.
- `stublib/link.ld.in`: text at the start of RAM, then rodata and data/bss segments, each
  page-aligned; defines `_heap_start`, `_heap_end` and `__global_pointer$`. `run.py` fills
  `@TEXT_FLAGS@` (1 for `x`, 5 for `rx`), `@RAM_BASE@` and `@RAM_END@` from the profile.

## Guests (`guests/`)

Each guest's expectations are in sidecar files next to it, in
[zkevm-test-monitor](https://github.com/eth-act/zkevm-test-monitor/tree/main/tests/eth-act-standards)'s
format, which `run.py` reads:

| File                      | Contents                                                     | Default                |
| ------------------------- | ------------------------------------------------------------ | ---------------------- |
| `<name>.input`            | the private input                                            | empty                  |
| `<name>.expected`         | the public output                                            | empty                  |
| `<name>.outcome`          | `fail` (a fault: abnormal termination without an error       | successful termination |
|                           | code), `fail <code>` (`main` returned `<code>`), or, for the |                        |
|                           | reference only, `unspecified <symbol>` (an accelerator call) |                        |
| `<name>.misaligned`       | the misaligned-access count (reference only)                 | not checked            |
| `<name>.profiles`         | memory profiles to run under: `x` and/or `rx` (reference     | `x`                    |
|                           | only)                                                        |                        |
| `<name>.<profile>.<kind>` | overrides `<name>.<kind>` under that profile                 |                        |

Summary of the current guests:

| Guest              | Profile | Expected                                                     |
| ------------------ | ------- | ------------------------------------------------------------ |
| `exit3`            | x       | failure:3                                                    |
| `bss`              | x       | success (bss is zeroed)                                      |
| `accel`            | x       | unspecified:zkvm_keccak256                                   |
| `memops`           | x       | success: checks the results of                               |
|                    |         | `memcpy`/`memmove`/`memset`/`memcmp` itself (`failure:<i+1>` |
|                    |         | at the first wrong byte `i`)                                 |
| `echo`             | x, rx   | success, output `len=10;mvkz olleh` (reads input, two        |
|                    |         | `write_output` calls)                                        |
| `output_null`      | x       | fault (`write_output` from an unmapped address)              |
| `output_then_fail` | x       | failure:5, output `partial`                                  |

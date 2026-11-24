# Tests

`python3 reference/tests/run.py` (from the repository root, after `scripts/build-lean.sh`) builds
every guest for both profiles and runs it with `zkvm-run` twice (integer registers `x1`…`x31` all
zero, then a canary pattern; both runs must give the expected observation, since the standards leave
initial registers unspecified), checks the loader's rejection messages, and checks that
`zkvm-run --check-exec-decodes` accepts the `echo` ELF under the `x` profile. It ends with
`passed N, failed M` and exits non-zero on any failure. Build products go to `../build/tests/`.

## Stub library and linker script

- Stub library: `run.py` generates `build/tests/stubs.S` with one `ebreak` (RV64I, so execute-only
  segments stay decodable) per symbol that `zkvm-run --list-symbols` prints (Sail's `zkvm_library`).
  Never executed: the machine performs the host function when the PC reaches the symbol.
- `stublib/link.ld.in`: text at the start of RAM, then rodata and data/bss segments, each
  page-aligned; defines `_heap_start`, `_heap_end`, `_stack_bottom`, `_stack_top` (the profile's
  stack region, so the script describes the stack as the memory-layout standard requires) and
  `__global_pointer$`. `run.py` fills `@TEXT_FLAGS@` (1 for `x`, 5 for `rx`), `@RAM_BASE@`,
  `@RAM_END@`, `@STACK_BASE@` and `@STACK_END@` from the profile.

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

| Guest                               | Profile | Expected                                                     |
| ----------------------------------- | ------- | ------------------------------------------------------------ |
| `exit3`                             | x       | failure:3                                                    |
| `bss`                               | x       | success (bss is zeroed)                                      |
| `accel`                             | x       | unspecified:zkvm_keccak256                                   |
| `memops`                            | x       | success: checks the results of                               |
|                                     |         | `memcpy`/`memmove`/`memset`/`memcmp` itself (`failure:<i+1>` |
|                                     |         | at the first wrong byte `i`)                                 |
| `echo`                              | x, rx   | success, output `len=10;mvkz olleh` (reads input, two        |
|                                     |         | `write_output` calls)                                        |
| `output_null`                       | x       | fault (`write_output` from an unmapped address)              |
| `output_then_fail`                  | x       | failure:5, output `partial`                                  |
| `ebreak`, `illegal`, `ecall`, `csr` | x       | fault (trap)                                                 |
| `input_write`                       | x       | fault (input region is read-only)                            |
| `misaligned_jump`                   | x       | fault (misaligned jump target)                               |
| `misaligned_load`                   | x       | success, output `0405060708090a0b`, 2 misaligned accesses    |
| `text_read`                         | x       | fault (execute-only code is unreadable)                      |
| `text_read`                         | rx      | success, output `13000000` (a `nop` read as data)            |
| `null_load`, `null_store_fff`       | x       | fault (null page)                                            |
| `stack_overflow`                    | x       | fault (stack guard)                                          |

Rejections (`zkvm-run` prints `REJECT <message>`, exit 2): `echo.elf` patched for bad magic,
ELFCLASS32, wrong machine, wrong type, misaligned entry, W^X, overlapping segments, a segment
outside the address space, a segment in the input region (outside the profile's `memory`); and the
`rx` build of `echo` under the `x` profile.

Accepted: `echo.elf` with `p_paddr ≠ p_vaddr` runs as `echo` does, because the image is placed at
`p_vaddr` and the ELF standard does not check `p_paddr`.

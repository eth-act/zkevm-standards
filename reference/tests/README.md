# Tests

`python3 reference/tests/run.py` (from the repository root, after `scripts/build-lean.sh`) builds
every guest for both profiles, runs it with `zkvm-run` on input `hello zkvm` twice (integer
registers `x1`…`x31` all zero, then a canary pattern; both runs must give the expected observation,
since the standards leave initial registers unspecified), and checks the loader's rejection
messages. It ends with `passed N, failed M` and exits non-zero on any failure. Build products go to
`../build/tests/`.

## Stub library and linker script

- Stub library: `run.py` generates `build/tests/stubs.S` with one `unimp` per symbol that
  `zkvm-run --list-symbols` prints (Sail's `zkvm_library`). Never executed: the machine performs the
  host function when the PC reaches the symbol.
- `stublib/link.ld.in`: text at the start of RAM, then rodata and data/bss segments, each
  page-aligned; defines `_heap_start`, `_heap_end` and `__global_pointer$`. `run.py` fills
  `@TEXT_FLAGS@` (1 for `x`, 5 for `rx`), `@RAM_BASE@` and `@RAM_END@` from the profile.

## Guests (`guests/`)

| Guest                               | Profile | Expected                                                  |
| ----------------------------------- | ------- | --------------------------------------------------------- |
| `echo`                              | x, rx   | success, output `len=10;mvkz olleh` (reads input, two     |
|                                     |         | `write_output` calls)                                     |
| `exit3`                             | x       | failure:3                                                 |
| `null_load`, `null_store_fff`       | x       | fault (null page)                                         |
| `stack_overflow`                    | x       | fault (stack guard)                                       |
| `misaligned_jump`                   | x       | fault (misaligned fetch)                                  |
| `input_write`                       | x       | fault (input region is read-only)                         |
| `output_null`                       | x       | fault (`write_output` from an unmapped address)           |
| `ebreak`, `illegal`, `ecall`, `csr` | x       | fault (trap)                                              |
| `misaligned_load`                   | x       | success, output `0405060708090a0b`, 2 misaligned accesses |
| `text_read`                         | x       | fault (execute-only code is unreadable)                   |
| `text_read`                         | rx      | success, output = the first byte of `main`                |
| `output_then_fail`                  | x       | failure:5, output `partial`                               |
| `bss`                               | x       | success (bss is zeroed)                                   |
| `memops`                            | x       | success, output of `memcpy`/`memmove`/`memset`/`memcmp`   |
|                                     |         | results                                                   |
| `accel`                             | x       | unspecified:zkvm_keccak256                                |

Rejections (`zkvm-run` prints `REJECT <message>`, exit 2): `echo.elf` patched for bad magic,
ELFCLASS32, wrong machine, wrong type, misaligned entry, W^X, overlapping segments, a segment
outside the address space; the `rx` build of `echo` under the `x` profile; and `exit3.c` linked
against a library with only `_start` (`missing symbol read_input`).

Accepted: `echo.elf` with `p_paddr ≠ p_vaddr` runs as `echo` does, because the image is placed at
`p_vaddr` and the ELF standard does not check `p_paddr`.

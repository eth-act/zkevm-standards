# Memory profiles

A memory profile is the memory layout a zkVM offers (memory-layout-restrictions,
memory-safety-guard-regions, elf-loading-and-validation). `ZkvmRef.MemoryProfile.fromJson` parses:

| Field           | Meaning                                                      |
| --------------- | ------------------------------------------------------------ |
| `name`          | profile name                                                 |
| `exec_perm`     | permission of executable segments: `x` (execute-only) or     |
|                 | `rx` (read+execute)                                          |
| `address_space` | range every segment must lie in                              |
| `boot_addr`     | fixed entry address, or `null` for any                       |
| `input`         | read-only region holding the private input (from its base)   |
| `memory`        | list of `{base, size}` ranges where loadable segments may be |
|                 | placed; every page is read-write until a segment paints it   |
| `stack`         | read-write stack region; the page below it is the stack      |
|                 | guard; `_start` sets `sp` to its top                         |

Addresses are `0x`-prefixed hex strings. The page at 0 is never mapped.

`reference-x.json` and `reference-rx.json` differ only in `exec_perm`, because the standards allow
both execute-only and read+execute code; the two profiles exercise both (for example, reading code
faults under `x` and succeeds under `rx`).

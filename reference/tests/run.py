#!/usr/bin/env python3
"""Tests of the Lean reference: each guest must produce its expected observation, and
zkvm-run must reject malformed ELFs with the exact loader message.

Run from the repository root after scripts/build-lean.sh:
    python3 reference/tests/run.py
"""
import json
import pathlib
import re
import shutil
import struct
import subprocess
import sys

from elftools.elf.elffile import ELFFile

ROOT = pathlib.Path.cwd()
REF = ROOT / "reference"
BUILD = REF / "build" / "tests"
STUBLIB = REF / "tests" / "stublib"
ZKVM_RUN = REF / "lean" / ".lake" / "build" / "bin" / "zkvm-run"
PROFILES = ["reference-x", "reference-rx"]
CC = "riscv64-unknown-elf-gcc"
CFLAGS = [
    "-march=rv64im_zicclsm", "-mabi=lp64", "-mcmodel=medany", "-O2", "-ffreestanding",
    "-fno-builtin", "-fno-jump-tables", "-nostdlib",
    "-I", str(ROOT / "standards" / "io-interface"),
    "-I", str(ROOT / "standards" / "c-interface-accelerators"),
]
INPUT = b"hello zkvm"

FAULT_GUESTS = [
    "null_load", "null_store_fff", "stack_overflow", "misaligned_jump", "input_write",
    "output_null", "ebreak", "illegal", "ecall", "csr",
]

results = []


def report(name, ok, detail=""):
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'} {name}" + (f": {detail}" if detail and not ok else ""))


def profile_path(profile):
    return REF / "memory-profiles" / f"{profile}.json"


def linker_script(profile, out):
    """Fill stublib/link.ld.in for a profile."""
    prof = json.loads(profile_path(profile).read_text())
    ram = prof["ram"]
    subst = {
        "@TEXT_FLAGS@": str({"x": 1, "rx": 5}[prof["exec_perm"]]),
        "@RAM_BASE@": ram["base"],
        "@RAM_END@": hex(int(ram["base"], 16) + int(ram["size"], 16)),
    }
    text = (STUBLIB / "link.ld.in").read_text()
    for key, value in subst.items():
        text = text.replace(key, value)
    out.write_text(text)


def link(src, ld, objs, elf):
    subprocess.run([CC, *CFLAGS, "-T", str(ld), str(src), *map(str, objs), "-o", str(elf)], check=True)


def build():
    for profile in PROFILES:
        out = BUILD / profile
        out.mkdir(parents=True, exist_ok=True)
        ld = out / "link.ld"
        linker_script(profile, ld)
        stubs = out / "stubs.o"
        subprocess.run([CC, *CFLAGS, "-c", str(STUBLIB / "stubs.S"), "-o", str(stubs)], check=True)
        for src in sorted((REF / "tests" / "guests").glob("*.c")):
            link(src, ld, [stubs], out / f"{src.stem}.elf")


def run_lean(profile, elf, workdir):
    r = subprocess.run([str(ZKVM_RUN), str(profile_path(profile)), str(elf), str(workdir / "input.bin")],
                       capture_output=True, text=True)
    m = re.fullmatch(r"outcome=(.*) output=([0-9a-f]*) misaligned=(\d+)", r.stdout.strip())
    if r.returncode != 0 or not m:
        return f"error:{r.returncode}:{r.stdout.strip()}{r.stderr.strip()}", b"", None
    return m.group(1), bytes.fromhex(m.group(2)), int(m.group(3))


def symbol_file_byte(elf, name):
    with open(elf, "rb") as f:
        e = ELFFile(f)
        addr = e.get_section_by_name(".symtab").get_symbol_by_name(name)[0]["st_value"]
        for seg in e.iter_segments():
            if seg["p_type"] == "PT_LOAD" and seg["p_vaddr"] <= addr < seg["p_vaddr"] + seg["p_filesz"]:
                f.seek(seg["p_offset"] + addr - seg["p_vaddr"])
                return f.read(1)
    raise RuntimeError(f"symbol {name} not in file data")


def case(guest, profile, outcome, output, misaligned=None):
    elf = BUILD / profile / f"{guest}.elf"
    workdir = BUILD / "runs" / profile / guest
    shutil.rmtree(workdir, ignore_errors=True)
    workdir.mkdir(parents=True)
    (workdir / "input.bin").write_bytes(INPUT)
    got_outcome, got_output, got_mis = run_lean(profile, elf, workdir)
    problems = []
    if (got_outcome, got_output) != (outcome, output):
        problems.append(f"got {got_outcome} {got_output!r}")
    if misaligned is not None and got_mis != misaligned:
        problems.append(f"misaligned count {got_mis}, expected {misaligned}")
    report(f"{profile}/{guest} -> {outcome} {output!r}", not problems,
           "; ".join(problems) + f" (expected {outcome} {output!r})")


def phdr_offsets(data):
    phoff = struct.unpack_from("<Q", data, 32)[0]
    phnum = struct.unpack_from("<H", data, 56)[0]
    offs = [phoff + i * 56 for i in range(phnum)]
    return [o for o in offs if struct.unpack_from("<I", data, o)[0] == 1]


def patched(edit):
    data = bytearray((BUILD / "reference-x" / "echo.elf").read_bytes())
    edit(data, phdr_offsets(data))
    return bytes(data)


def put(fmt, off, value):
    return lambda d, _: struct.pack_into(fmt, d, off, value)


def phdr_field(index, field_off, fmt, fn):
    def edit(d, loads):
        o = loads[index] + field_off
        struct.pack_into(fmt, d, o, fn(struct.unpack_from(fmt, d, o)[0]))
    return edit


def both(*edits):
    def edit(d, loads):
        for e in edits:
            e(d, loads)
    return edit


def rejection(name, elf_bytes, message, profile="reference-x"):
    workdir = BUILD / "reject" / name
    shutil.rmtree(workdir, ignore_errors=True)
    workdir.mkdir(parents=True)
    elf = workdir / "guest.elf"
    elf.write_bytes(elf_bytes)
    (workdir / "input.bin").write_bytes(INPUT)
    want = f"REJECT {message}"
    r = subprocess.run([str(ZKVM_RUN), str(profile_path(profile)), str(elf), str(workdir / "input.bin")],
                       capture_output=True, text=True)
    ok = r.returncode == 2 and r.stdout.strip() == want
    report(f"reject {name} -> {want}", ok, f"exit {r.returncode} printed {r.stdout.strip()!r}{r.stderr.strip()!r}")


def missing_symbol_elf():
    """exit3.c linked against a library that defines only `_start`."""
    workdir = BUILD / "reject" / "missing-symbol-build"
    workdir.mkdir(parents=True, exist_ok=True)
    stub = workdir / "start_only.S"
    stub.write_text("  .section .text\n  .balign 4\n  .globl _start\n_start:\n  unimp\n")
    obj = workdir / "start_only.o"
    subprocess.run([CC, *CFLAGS, "-c", str(stub), "-o", str(obj)], check=True)
    elf = workdir / "exit3.elf"
    link(REF / "tests" / "guests" / "exit3.c", BUILD / "reference-x" / "link.ld", [obj], elf)
    return elf.read_bytes()


def main():
    build()

    for profile in PROFILES:
        case("echo", profile, "success", b"len=10;mvkz olleh")
    case("exit3", "reference-x", "failure:3", b"")
    for guest in FAULT_GUESTS:
        case(guest, "reference-x", "fault", b"")
    case("misaligned_load", "reference-x", "success", bytes(range(4, 12)), misaligned=2)
    case("text_read", "reference-x", "fault", b"")
    case("text_read", "reference-rx", "success",
         symbol_file_byte(BUILD / "reference-rx" / "text_read.elf", "main"))
    case("output_then_fail", "reference-x", "failure:5", b"partial")
    case("bss", "reference-x", "success", b"")
    case("memops", "reference-x", "success", bytes.fromhex(
        "010201020304050607080b0c0d0e0f100102030405060708abababab00000000ff00"))
    case("accel", "reference-x", "unspecified:zkvm_keccak256", b"")

    rejection("bad-magic", patched(put("<B", 0, 0)), "bad magic")
    rejection("class32", patched(put("<B", 4, 1)), "class is not ELFCLASS64")
    rejection("machine", patched(put("<H", 18, 0x3e)), "e_machine is not EM_RISCV")
    rejection("etype", patched(put("<H", 16, 3)), "e_type is not ET_EXEC")
    rejection("entry", patched(lambda d, _: struct.pack_into(
        "<Q", d, 24, struct.unpack_from("<Q", d, 24)[0] + 2)), "e_entry not 4-byte aligned")
    rejection("paddr", patched(phdr_field(0, 24, "<Q", lambda v: v + 0x1000)),
              "segment 0x80000000: p_paddr differs from p_vaddr")
    rejection("wx", patched(phdr_field(0, 4, "<I", lambda v: 7)),
              "segment 0x80000000: W^X violated")
    rejection("rx-under-x", (BUILD / "reference-rx" / "echo.elf").read_bytes(),
              "segment 0x80000000: executable flags do not match profile")
    rejection("overlap", patched(both(phdr_field(2, 16, "<Q", lambda v: 0x80000000),
                                      phdr_field(2, 24, "<Q", lambda v: 0x80000000))),
              "segments 0x80000000 and 0x80000000 overlap")
    rejection("outside", patched(both(phdr_field(0, 16, "<Q", lambda v: 0x200000000),
                                      phdr_field(0, 24, "<Q", lambda v: 0x200000000))),
              "segment 0x200000000: outside the addressable space")
    rejection("missing-symbol", missing_symbol_elf(), "missing symbol read_input")

    passed = sum(results)
    failed = len(results) - passed
    print(f"passed {passed}, failed {failed}")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()

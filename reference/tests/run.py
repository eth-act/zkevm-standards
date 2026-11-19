#!/usr/bin/env python3
"""Differential tests: the C++ sail-riscv emulator and the Lean reference must both match
the expected observation of each guest, and both Lean executables must reject malformed
ELFs with the exact loader message.

Run from the repository root after scripts/build-emulator.sh and scripts/build-lean.sh:
    python3 reference/tests/run.py
"""
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
SIM = REF / "build" / "emu" / "c_emulator" / "sail_riscv_sim"
LEAN_BIN = REF / "lean" / ".lake" / "build" / "bin"
ZKVM_LOAD = LEAN_BIN / "zkvm-load"
ZKVM_RUN = LEAN_BIN / "zkvm-run"
BASE_CONFIG = REF / "config" / "zkvm-ref-base.json"
PROFILES = ["reference-x", "reference-rx"]
CC = "riscv64-unknown-elf-gcc"
CFLAGS = [
    "-march=rv64im_zicclsm", "-mabi=lp64", "-mcmodel=medany", "-O2", "-ffreestanding",
    "-fno-builtin", "-fno-jump-tables", "-nostdlib", "-I", str(ROOT / "standards" / "io-interface"),
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
    return REF / "profiles" / f"{profile}.json"


def build():
    for profile in PROFILES:
        subprocess.run(["make", "-s", "-C", str(REF / "runtime"), f"PROFILE={profile_path(profile)}"],
                       check=True)
        rt = REF / "build" / "runtime" / profile
        out = BUILD / profile
        out.mkdir(parents=True, exist_ok=True)
        for src in sorted((REF / "tests" / "guests").glob("*.c")):
            subprocess.run([CC, *CFLAGS, "-T", str(rt / "link.ld"), str(src), "-Wl,--whole-archive",
                            str(rt / "libzkvm_ref.a"), "-Wl,--no-whole-archive",
                            "-o", str(out / f"{src.stem}.elf")], check=True)


def decode_exit(code):
    if code == 0:
        return "success"
    if code < 2**32:
        return f"failure:{code}"
    if code == 2**32:
        return "fault"
    return f"badexit:{code}"


def run_cpp(profile, elf, workdir):
    """Returns (outcome, output bytes, misaligned count) or raises on loader rejection."""
    inp = workdir / "input.bin"
    load = subprocess.run([str(ZKVM_LOAD), str(profile_path(profile)), str(BASE_CONFIG), str(elf),
                           str(inp), str(workdir)], capture_output=True, text=True)
    if load.returncode != 0:
        return f"load:{load.returncode}:{load.stdout.strip()}{load.stderr.strip()}", b"", None
    out = workdir / "out.bin"
    sim = subprocess.run([str(SIM), "--config", str(workdir / "config.json"), "--zkvm-output",
                          str(out), "--inst-limit", "5000000", str(elf), str(workdir / "input.elf")],
                         capture_output=True, text=True)
    outcome = "outoffuel"
    misaligned = None
    for line in sim.stdout.splitlines():
        if m := re.fullmatch(r"zkvm: misaligned accesses: (\d+)", line):
            misaligned = int(m.group(1))
        elif line == "SUCCESS":
            outcome = decode_exit(0)
        elif m := re.fullmatch(r"FAILURE: (\d+) \(0x[0-9a-f]+\)", line):
            outcome = decode_exit(int(m.group(1)))
        elif line.startswith("FAILURE"):
            outcome = f"stuck:{line}"
    if sim.returncode != 0 and outcome in ("success", "outoffuel"):
        outcome = f"stuck:exit {sim.returncode}: {sim.stderr.strip()}"
    output = out.read_bytes() if out.exists() else b""
    return outcome, output, misaligned


def run_lean(profile, elf, workdir):
    r = subprocess.run([str(ZKVM_RUN), str(profile_path(profile)), str(elf), str(workdir / "input.bin")],
                       capture_output=True, text=True)
    m = re.fullmatch(r"outcome=(.*) output=([0-9a-f]*)", r.stdout.strip())
    if r.returncode != 0 or not m:
        return f"error:{r.returncode}:{r.stdout.strip()}{r.stderr.strip()}", b""
    return m.group(1), bytes.fromhex(m.group(2))


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
    expected = (outcome, output)
    cpp_outcome, cpp_output, cpp_mis = run_cpp(profile, elf, workdir)
    lean = run_lean(profile, elf, workdir)
    problems = []
    if (cpp_outcome, cpp_output) != expected:
        problems.append(f"C++ gave {cpp_outcome} {cpp_output!r}")
    if lean != expected:
        problems.append(f"Lean gave {lean[0]} {lean[1]!r}")
    if misaligned is not None and cpp_mis != misaligned:
        problems.append(f"C++ misaligned count {cpp_mis}, expected {misaligned}")
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
    load = subprocess.run([str(ZKVM_LOAD), str(profile_path(profile)), str(BASE_CONFIG), str(elf),
                           str(workdir / "input.bin"), str(workdir / "out")], capture_output=True, text=True)
    run = subprocess.run([str(ZKVM_RUN), str(profile_path(profile)), str(elf), str(workdir / "input.bin")],
                         capture_output=True, text=True)
    problems = []
    for tool, r in (("zkvm-load", load), ("zkvm-run", run)):
        if r.returncode != 2 or r.stdout.strip() != want:
            problems.append(f"{tool} exit {r.returncode} printed {r.stdout.strip()!r}{r.stderr.strip()!r}")
    report(f"reject {name} -> {want}", not problems, "; ".join(problems))


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

    passed = sum(results)
    failed = len(results) - passed
    print(f"passed {passed}, failed {failed}")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()

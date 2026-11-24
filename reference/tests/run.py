#!/usr/bin/env python3
"""Tests of the Lean reference: each guest must produce its expected observation, and
zkvm-run must reject malformed ELFs with the exact loader message.

Each guest `guests/<name>.c` has its expectations in sidecar files, in zkevm-test-monitor's
format (https://github.com/eth-act/zkevm-test-monitor/tree/main/tests/eth-act-standards):
  <name>.input     the private input (default: empty)
  <name>.expected  the public output (default: empty)
  <name>.outcome   `fail` (a fault: abnormal termination without an error code) or `fail <code>`
                   (main returned <code>); default: successful termination
and, for the reference only:
  <name>.outcome   `unspecified <symbol>` (the guest called an accelerator)
  <name>.misaligned  the misaligned-access count
  <name>.profiles  the memory profiles to run under, `x` and/or `rx` (default: `x`)
  <name>.<profile>.<kind>  overrides <name>.<kind> under that profile

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
GUESTS = REF / "tests" / "guests"
ECHO_INPUT = (GUESTS / "echo.input").read_bytes()

results = []


def report(name, ok, detail=""):
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'} {name}" + (f": {detail}" if detail and not ok else ""))


def profile_path(profile):
    return REF / "memory-profiles" / f"{profile}.json"


def linker_script(profile, out):
    """Fill stublib/link.ld.in for a profile."""
    prof = json.loads(profile_path(profile).read_text())
    ram = prof["memory"][0]
    subst = {
        "@TEXT_FLAGS@": str({"x": 1, "rx": 5}[prof["exec_perm"]]),
        "@RAM_BASE@": ram["base"],
        "@RAM_END@": hex(int(ram["base"], 16) + int(ram["size"], 16)),
        "@STACK_BASE@": prof["stack"]["base"],
        "@STACK_END@": hex(int(prof["stack"]["base"], 16) + int(prof["stack"]["size"], 16)),
    }
    text = (STUBLIB / "link.ld.in").read_text()
    for key, value in subst.items():
        text = text.replace(key, value)
    out.write_text(text)


def link(src, ld, objs, elf):
    subprocess.run([CC, *CFLAGS, "-T", str(ld), str(src), *map(str, objs), "-o", str(elf)], check=True)


def stub_library(path):
    """One 4-byte label per static-library symbol, as listed by `zkvm-run --list-symbols` (Sail's
    `zkvm_library`). Never executed: the machine performs the host function when the PC reaches
    the symbol. Each label holds `ebreak`, an RV64I instruction, so execute-only segments stay
    decodable (`unimp` is a Zicsr instruction)."""
    symbols = subprocess.run([str(ZKVM_RUN), "--list-symbols"], capture_output=True, text=True,
                             check=True).stdout.split()
    lines = ["  .section .text", "  .balign 4"]
    for s in symbols:
        lines += ["", f"  .globl {s}", f"{s}:", "  ebreak"]
    path.write_text("\n".join(lines) + "\n")


def build():
    BUILD.mkdir(parents=True, exist_ok=True)
    stubs_src = BUILD / "stubs.S"
    stub_library(stubs_src)
    for profile in PROFILES:
        out = BUILD / profile
        out.mkdir(parents=True, exist_ok=True)
        ld = out / "link.ld"
        linker_script(profile, ld)
        stubs = out / "stubs.o"
        subprocess.run([CC, *CFLAGS, "-c", str(stubs_src), "-o", str(stubs)], check=True)
        for src in sorted((REF / "tests" / "guests").glob("*.c")):
            link(src, ld, [stubs], out / f"{src.stem}.elf")


def run_lean(profile, elf, workdir, canary=False):
    r = subprocess.run([str(ZKVM_RUN), *(["--canary"] if canary else []), str(profile_path(profile)),
                        str(elf), str(workdir / "input.bin")], capture_output=True, text=True)
    m = re.fullmatch(r"outcome=(.*) output=([0-9a-f]*) misaligned=(\d+)", r.stdout.strip())
    if r.returncode != 0 or not m:
        return f"error:{r.returncode}:{r.stdout.strip()}{r.stderr.strip()}", b"", None
    return m.group(1), bytes.fromhex(m.group(2)), int(m.group(3))


def sidecar(guest, profile, kind):
    """The bytes of guests/<guest>.<profile>.<kind>, else guests/<guest>.<kind>, else None."""
    short = profile.removeprefix("reference-")
    for path in (GUESTS / f"{guest}.{short}.{kind}", GUESTS / f"{guest}.{kind}"):
        if path.exists():
            return path.read_bytes()
    return None


def expected_outcome(text):
    """zkvm-run's outcome string for an `.outcome` file's contents (None: success)."""
    if text is None:
        return "success"
    words = text.decode().split()
    if words == ["fail"]:
        return "fault"
    if len(words) == 2 and words[0] == "fail":
        return f"failure:{int(words[1])}"
    if len(words) == 2 and words[0] == "unspecified":
        return f"unspecified:{words[1]}"
    raise ValueError(f"bad .outcome contents {text!r}")


def guest_profiles(guest):
    path = GUESTS / f"{guest}.profiles"
    names = path.read_text().split() if path.exists() else ["x"]
    return [f"reference-{p}" for p in names]


def case(guest, profile):
    """Run with x1..x31 all zero and again with a canary pattern: both must give the expected
    observation, since the standards leave the initial integer registers unspecified."""
    outcome = expected_outcome(sidecar(guest, profile, "outcome"))
    output = sidecar(guest, profile, "expected") or b""
    mis_text = sidecar(guest, profile, "misaligned")
    misaligned = int(mis_text) if mis_text is not None else None
    elf = BUILD / profile / f"{guest}.elf"
    workdir = BUILD / "runs" / profile / guest
    shutil.rmtree(workdir, ignore_errors=True)
    workdir.mkdir(parents=True)
    (workdir / "input.bin").write_bytes(sidecar(guest, profile, "input") or b"")
    problems = []
    for canary in (False, True):
        regs = "canary" if canary else "zero"
        got_outcome, got_output, got_mis = run_lean(profile, elf, workdir, canary)
        if (got_outcome, got_output) != (outcome, output):
            problems.append(f"{regs} registers: got {got_outcome} {got_output!r}")
        if misaligned is not None and got_mis != misaligned:
            problems.append(f"{regs} registers: misaligned count {got_mis}, expected {misaligned}")
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
    (workdir / "input.bin").write_bytes(ECHO_INPUT)
    want = f"REJECT {message}"
    r = subprocess.run([str(ZKVM_RUN), str(profile_path(profile)), str(elf), str(workdir / "input.bin")],
                       capture_output=True, text=True)
    ok = r.returncode == 2 and r.stdout.strip() == want
    report(f"reject {name} -> {want}", ok, f"exit {r.returncode} printed {r.stdout.strip()!r}{r.stderr.strip()!r}")


def accepted(name, elf_bytes, outcome, output, profile="reference-x"):
    """A patched ELF the loader must accept, with its expected observation."""
    workdir = BUILD / "accept" / name
    shutil.rmtree(workdir, ignore_errors=True)
    workdir.mkdir(parents=True)
    elf = workdir / "guest.elf"
    elf.write_bytes(elf_bytes)
    (workdir / "input.bin").write_bytes(ECHO_INPUT)
    got_outcome, got_output, _ = run_lean(profile, elf, workdir)
    report(f"accept {name} -> {outcome} {output!r}", (got_outcome, got_output) == (outcome, output),
           f"got {got_outcome} {got_output!r}")


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


def exec_decodes(profile, elf):
    """`zkvm-run --check-exec-decodes` accepts an ELF whose execute-only segment holds only
    instructions."""
    r = subprocess.run([str(ZKVM_RUN), "--check-exec-decodes", str(profile_path(profile)), str(elf)],
                       capture_output=True, text=True)
    report(f"check-exec-decodes {profile}/{elf.name} -> OK", r.returncode == 0 and r.stdout.strip() == "OK",
           f"exit {r.returncode} printed {r.stdout.strip()!r}{r.stderr.strip()!r}")


def main():
    build()

    for src in sorted(GUESTS.glob("*.c")):
        for profile in guest_profiles(src.stem):
            case(src.stem, profile)

    rejection("bad-magic", patched(put("<B", 0, 0)), "bad magic")
    rejection("class32", patched(put("<B", 4, 1)), "class is not ELFCLASS64")
    rejection("machine", patched(put("<H", 18, 0x3e)), "e_machine is not EM_RISCV")
    rejection("etype", patched(put("<H", 16, 3)), "e_type is not ET_EXEC")
    rejection("entry", patched(lambda d, _: struct.pack_into(
        "<Q", d, 24, struct.unpack_from("<Q", d, 24)[0] + 2)), "e_entry not 4-byte aligned")
    # The image is placed at p_vaddr; the ELF standard has no p_paddr check.
    accepted("paddr", patched(phdr_field(0, 24, "<Q", lambda v: v + 0x1000)),
             "success", b"len=10;mvkz olleh")
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
    rejection("segment-in-input", patched(both(phdr_field(2, 16, "<Q", lambda v: 0x40000000),
                                               phdr_field(2, 24, "<Q", lambda v: 0x40000000))),
              "segment page 0x40000000 outside memory")
    rejection("missing-symbol", missing_symbol_elf(), "missing symbol read_input")
    exec_decodes("reference-x", BUILD / "reference-x" / "echo.elf")

    passed = sum(results)
    failed = len(results) - passed
    print(f"passed {passed}, failed {failed}")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()

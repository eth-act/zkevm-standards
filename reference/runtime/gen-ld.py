#!/usr/bin/env python3
"""Print the reference linker script filled in for a profile JSON."""
import json
import pathlib
import sys


def main() -> None:
    profile = json.loads(pathlib.Path(sys.argv[1]).read_text())
    num = lambda s: int(s, 16)
    flags = {"x": 1, "rx": 5}[profile["exec_perm"]]
    ram, stack, inp = profile["ram"], profile["stack"], profile["input"]
    subst = {
        "@TEXT_FLAGS@": str(flags),
        "@TEXT_BASE@": hex(num(profile["trap_vector"])),
        "@RAM_END@": hex(num(ram["base"]) + num(ram["size"])),
        "@STACK_BOTTOM@": hex(num(stack["base"])),
        "@STACK_TOP@": hex(num(stack["base"]) + num(stack["size"])),
        "@INPUT_BASE@": hex(num(inp["base"])),
    }
    text = (pathlib.Path(__file__).parent / "link.ld.in").read_text()
    for key, value in subst.items():
        text = text.replace(key, value)
    sys.stdout.write(text)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Write the sail-riscv configuration of the zkVM reference machine.

Usage: make-config.py OUT

Starts from reference/sail-riscv/config/config.json.in with the placeholders filled as
sail-riscv's CMake does for rv64d_v256_e64.json, disables every extension, then merges
reference/config/riscv-target.json and reference/config/platform.json on top.
Rule: riscv-target.json lists the enabled extensions; every other extension is disabled.

Why generated rather than a committed config file: sail-riscv ships only this template (CMake
placeholders and `//` comments, so not JSON), about 600 lines. Generating keeps the files we
maintain to the two short overlays, and the rule above keeps holding when a sail-riscv update
adds extensions, which a committed copy would silently leave at their template defaults.
"""
import json
import pathlib
import sys

REF = pathlib.Path(__file__).resolve().parent.parent

# Values sail-riscv's config/CMakeLists.txt uses for rv64d_v256_e64.json.
PLACEHOLDERS = {
    "@CONFIG__BASE__XLEN@": "64",
    "@CONFIG__V__ELEN_EXP@": "6",
    "@CONFIG__V__VLEN_EXP@": "8",
    "@CONFIG_XLEN_IS_32@": "false",
    "@CONFIG_XLEN_IS_64@": "true",
    "@CONFIG_MIDELEG_DELEGATABLE_BITS_VALUE@": "0xFFFF_FFFF_FFFF_FFFF",
    "@CONFIG_ELEN_IS_64@": "true",
    "@CONFIG__V__SUPPORT@": "Full",
}


def disable_all(node):
    """Disable every extension below `node`: each `supported` flag becomes false and each
    `support_level` (the vector extensions, whose template default is "Full") "Disabled"."""
    if isinstance(node, dict):
        if "supported" in node:
            node["supported"] = False
        if "support_level" in node:
            node["support_level"] = "Disabled"
        for value in node.values():
            disable_all(value)


def merge(base, overlay):
    """Merge `overlay` into `base`: dicts merge recursively, any other value replaces."""
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge(base[key], value)
        else:
            base[key] = value


def main():
    out = pathlib.Path(sys.argv[1])
    text = (REF / "sail-riscv" / "config" / "config.json.in").read_text()
    for key, value in PLACEHOLDERS.items():
        text = text.replace(key, value)
    cfg = json.loads("\n".join(l for l in text.splitlines() if not l.lstrip().startswith("//")))
    disable_all(cfg["extensions"])
    for overlay in ("riscv-target.json", "platform.json"):
        merge(cfg, json.loads((REF / "config" / overlay).read_text()))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(cfg, indent=2) + "\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Derive reference/config/zkvm-ref-base.json from sail-riscv's rv64d_v256_e64.json.

Usage: make-base-config.py SOURCE_JSON OUTPUT_JSON
"""
import json
import pathlib
import sys

ZKVM_IO_BASE = 0x00F0000000000000


def disable_all(node):
    if isinstance(node, dict):
        if "supported" in node:
            node["supported"] = False
        for value in node.values():
            disable_all(value)


def region(base, size, perm):
    """Same attributes as toSailRegion in reference/lean/ZkvmRef/Loader.lean."""
    main = perm == "rw"
    readable, writable, executable = {
        "r": (True, False, False),
        "rw": (True, True, False),
        "x": (False, False, True),
        "rx": (True, False, True),
        "io": (True, True, False),
    }[perm]
    return {
        "base": {"len": 64, "value": hex(base)},
        "size": {"len": 64, "value": hex(size)},
        "attributes": {
            "mem_type": "MainMemory" if main else "IOMemory",
            "cacheable": True,
            "coherent": main,
            "executable": executable,
            "readable": readable,
            "writable": writable,
            "read_idempotent": True,
            "write_idempotent": True,
            "misaligned_exceptions": {
                "load_store": {"None": None},
                "vector": {"None": None},
                "amo": "AccessFault",
            },
            "atomic_support": "AMONone",
            "reservability": "RsrvNone",
            "supports_cbo_zero": False,
            "supports_pte_read": False,
            "supports_pte_write": False,
        },
        "include_in_device_tree": False,
    }


def main():
    src, dst = map(pathlib.Path, sys.argv[1:3])
    text = "\n".join(l for l in src.read_text().splitlines() if not l.lstrip().startswith("//"))
    cfg = json.loads(text)

    ext = cfg["extensions"]
    disable_all(ext)
    ext["M"]["supported"] = True
    ext["Zicclsm"]["supported"] = True
    ext["V"]["support_level"] = "Disabled"

    cfg["base"]["mstatus"]["fs_legal_states"] = "ExtContext_Off"
    cfg["base"]["mstatus"]["vs_legal_states"] = "ExtContext_Off"
    cfg["base"]["mtvec"]["reset_value"] = 0x80000000

    mem = cfg["memory"]
    mem["misaligned"]["exceptions"]["load_store"] = {"None": None}
    mem["pmp"]["count"] = 0
    mem["pmp"]["usable_count"] = 0
    mem["regions"] = [
        region(0x40000000, 0x1000000, "r"),
        region(0x80000000, 0x8000000, "rw"),
        region(0x88001000, 0x100000, "rw"),
        region(ZKVM_IO_BASE, 0x1000, "io"),
    ]

    plat = cfg["platform"]
    plat["clint"]["supported"] = False
    plat["simple_interrupt_generator"]["supported"] = False
    plat["zkvm_io"] = {"supported": True, "base": ZKVM_IO_BASE}

    dst.write_text(json.dumps(cfg, indent=2) + "\n")


if __name__ == "__main__":
    main()

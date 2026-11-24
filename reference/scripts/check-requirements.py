#!/usr/bin/env python3
"""Check the normative-requirement IDs of the standards against the tags in the reference.

Usage (from the repository root): python3 reference/scripts/check-requirements.py

Reads the `## Normative requirements` table of every standard under `standards/` and fails, one
line per problem, if
  - an ID is defined twice;
  - a row whose "Checked by" lists `Sail` has no `[ID]` tag in `reference/sail/**/*.sail` or
    `reference/config/README.md`;
  - a row whose "Checked by" lists `Lean` has no `[ID]` tag in `reference/lean/**/*.lean`;
  - a tag names an ID that no table defines;
  - a `not tested` entry gives no reason after its colon.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path.cwd()
STANDARDS = ROOT / "standards"
REF = ROOT / "reference"
HEADING = "## Normative requirements"
TAG = re.compile(r"\[((?:TER|IO|MEM|ACC|IAM|TGT|ELF|LAY|GUA|LIB)[0-9]+)\]")
ID = re.compile(r"(?:TER|IO|MEM|ACC|IAM|TGT|ELF|LAY|GUA|LIB)[0-9]+")


def cells(line):
    """Cells of a markdown table row; `\\|` is a literal pipe inside a cell."""
    parts = re.split(r"(?<!\\)\|", line.strip().strip("|"))
    return [p.strip() for p in parts]


def top_level_items(text):
    """Comma-separated items of a "Checked by" cell, ignoring commas inside parentheses."""
    items, depth, cur = [], 0, ""
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            items.append(cur.strip())
            cur = ""
        else:
            cur += ch
    items.append(cur.strip())
    return [i for i in items if i]


def tables():
    """(file, id, checked-by items) for every row of every requirements table."""
    rows = []
    for path in sorted(STANDARDS.rglob("*.md")):
        lines = path.read_text().splitlines()
        if HEADING not in lines:
            continue
        i = lines.index(HEADING) + 1
        while i < len(lines) and not lines[i].lstrip().startswith("|"):
            i += 1
        header = cells(lines[i])
        col = header.index("Checked by")
        for line in lines[i + 2:]:
            if not line.lstrip().startswith("|"):
                break
            row = cells(line)
            rows.append((path.relative_to(ROOT), row[0], top_level_items(row[col])))
    return rows


def tags(paths):
    found = set()
    for path in paths:
        found.update(TAG.findall(path.read_text()))
    return found


def main():
    problems = []
    rows = tables()
    defined = {}
    for path, rid, _ in rows:
        if not ID.fullmatch(rid):
            problems.append(f"{path}: malformed ID {rid!r}")
        if rid in defined:
            problems.append(f"{path}: {rid} already defined in {defined[rid]}")
        defined.setdefault(rid, path)
    sail = tags([*REF.glob("sail/**/*.sail"), REF / "config" / "README.md"])
    lean = tags(p for p in REF.glob("lean/**/*.lean") if ".lake" not in p.parts)
    for path, rid, items in rows:
        for item in items:
            if item.startswith("Sail") and rid not in sail:
                problems.append(f"{path}: {rid} is checked by Sail but has no [{rid}] tag in reference/sail or reference/config/README.md")
            if item.startswith("Lean") and rid not in lean:
                problems.append(f"{path}: {rid} is checked by Lean but has no [{rid}] tag in reference/lean")
            if item.startswith("not tested") and not item.partition(":")[2].strip():
                problems.append(f"{path}: {rid}: `{item}` gives no reason after a colon")
    for rid in sorted((sail | lean) - defined.keys()):
        problems.append(f"tag [{rid}] names an ID that no requirements table defines")
    for p in problems:
        print(p)
    if problems:
        sys.exit(1)
    print(f"requirements: {len(defined)} ids, all tagged")


if __name__ == "__main__":
    main()

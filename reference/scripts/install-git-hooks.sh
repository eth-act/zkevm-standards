#!/usr/bin/env bash
# Use reference/githooks/ as this clone's git hooks directory (markdown formatting on commit).
set -euo pipefail
REF="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git -C "$REF" config core.hooksPath reference/githooks
echo "core.hooksPath = reference/githooks"

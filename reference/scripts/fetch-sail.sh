#!/usr/bin/env bash
# Download the official Sail 0.20.2 binary release into reference/build/sail-0.20.2/.
set -euo pipefail
REF="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REF/build/sail-0.20.2"
if [ -x "$DEST/sail/bin/sail" ]; then
  exit 0
fi
mkdir -p "$DEST"
URL="https://github.com/rems-project/sail/releases/download/0.20.2-binary/sail-Linux-x86_64.tar.gz"
curl -fL --retry 3 -o "$DEST/sail.tar.gz" "$URL"
tar -xzf "$DEST/sail.tar.gz" -C "$DEST"
rm "$DEST/sail.tar.gz"
test -x "$DEST/sail/bin/sail"

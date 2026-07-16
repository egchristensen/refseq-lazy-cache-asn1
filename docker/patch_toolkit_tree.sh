#!/usr/bin/env bash
set -euo pipefail

toolkit_root="${1:?usage: patch_toolkit_tree.sh TOOLKIT_ROOT PAYLOAD_DIR}"
payload_dir="${2:?usage: patch_toolkit_tree.sh TOOLKIT_ROOT PAYLOAD_DIR}"
app_dir="$toolkit_root/src/app/asn_cache"

test -f "$app_dir/CMakeLists.txt"
test -f "$payload_dir/gks_ncbi_sequence_probe.cpp"
test -f "$payload_dir/CMakeLists.gks_ncbi_sequence_probe.app.txt"

cp "$payload_dir/gks_ncbi_sequence_probe.cpp" "$app_dir/"
cp "$payload_dir/CMakeLists.gks_ncbi_sequence_probe.app.txt" "$app_dir/"

python3 - "$app_dir/CMakeLists.txt" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
if "gks_ncbi_sequence_probe" not in text:
    marker = "NCBI_add_app(\n"
    if marker not in text:
        raise SystemExit(f"cannot find NCBI_add_app in {path}")
    text = text.replace(marker, marker + "  gks_ncbi_sequence_probe\n", 1)
    path.write_text(text)
PY

grep -q 'gks_ncbi_sequence_probe' "$app_dir/CMakeLists.txt"

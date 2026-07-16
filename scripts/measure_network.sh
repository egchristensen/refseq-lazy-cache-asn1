#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASE="${1:?usage: measure_network.sh CASE [probe arguments...]}"; shift
mkdir -p "$ROOT/results/raw/$CASE"
docker run --rm --platform linux/arm64 --cap-add SYS_PTRACE \
  -v "$ROOT:/workspace" -w /workspace "${IMAGE:-gks-ncbi:arm64}" \
  strace -f -tt -e trace=network -o "results/raw/$CASE/network.strace" \
  gks_ncbi_sequence_probe "$@"
rg -c 'connect\(' "$ROOT/results/raw/$CASE/network.strace" > "$ROOT/results/raw/$CASE/connect-count.txt" || printf '0\n' > "$ROOT/results/raw/$CASE/connect-count.txt"

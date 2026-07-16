#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-gks-ncbi:arm64}"

arch="$(docker image inspect "$IMAGE" --format '{{.Architecture}}')"
[[ "$arch" == arm64 ]] || { echo "Unexpected image architecture: $arch" >&2; exit 1; }
docker run --rm --platform linux/arm64 "$IMAGE" sh -ec '
  test "$(uname -m)" = aarch64
  for command in prime_cache asn_cache_test gks_ncbi_sequence_probe asnvalidate asn2asn asn2fasta asn2flat asn_cleanup annotwriter; do
    command -v "$command" >/dev/null
  done
  gks_ncbi_sequence_probe -help >/dev/null
  bcftools --version >/dev/null
'
echo "Native ARM image smoke test passed."

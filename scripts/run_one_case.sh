#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASE="${1:?usage: run_one_case.sh CASE MODE REQUESTS [extra probe args...]}"
MODE="${2:?missing mode}"
REQUESTS="${3:?missing requests file}"
shift 3
IMAGE="${IMAGE:-gks-ncbi:arm64}"
NETWORK="${NETWORK:-on}"
ASN_CACHE="${ASN_CACHE:-work/asn_cache_full}"
RAW="$ROOT/results/raw/$CASE"
mkdir -p "$RAW"

image_digest="$(docker image inspect "$IMAGE" --format '{{.Id}}')"
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
network_args=(--network bridge)
[[ "$NETWORK" == on ]] || network_args=(--network none)
mode_args=(-mode "$MODE")
[[ "$MODE" == asn || "$MODE" == hybrid ]] && mode_args+=(-asn-cache "$ASN_CACHE")

printf '%q ' docker run --rm --platform linux/arm64 "${network_args[@]}" -v "$ROOT:/workspace" -w /workspace "$IMAGE" gks_ncbi_sequence_probe "${mode_args[@]}" -requests "$REQUESTS" -output "results/raw/$CASE/results.jsonl" -fail-on-mismatch "$@" > "$RAW/command.txt"
printf '\n' >> "$RAW/command.txt"
set +e
docker run --rm --platform linux/arm64 "${network_args[@]}" \
  -v "$ROOT:/workspace" -w /workspace "$IMAGE" \
  /usr/bin/time -v -o "results/raw/$CASE/time.txt" \
  gks_ncbi_sequence_probe "${mode_args[@]}" -requests "$REQUESTS" \
    -output "results/raw/$CASE/results.jsonl" -fail-on-mismatch "$@" \
  > "$RAW/stdout.log" 2> "$RAW/stderr.log"
rc=$?
set -e
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$RAW/metadata.json" <<EOF
{"case":"$CASE","mode":"$MODE","network_disabled":$([[ "$NETWORK" == on ]] && echo false || echo true),"platform":"linux/arm64","emulated":false,"toolkit_commit":"fe8144adf21fc19db6b9c8c96aa623965419e8bd","image_digest":"$image_digest","utc_start":"$start","utc_end":"$end","exit_code":$rc}
EOF
exit "$rc"

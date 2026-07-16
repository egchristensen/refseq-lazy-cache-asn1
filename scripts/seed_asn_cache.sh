#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-gks-ncbi:arm64}"
REFSEQ_ACCESSION="${REFSEQ_ACCESSION:-NC_000023.11}"
CACHE_REL="work/asn_cache_full"
RAW="$ROOT/results/raw/asn_seed"

mkdir -p "$ROOT/work" "$RAW"
printf '%s\n' "$REFSEQ_ACCESSION" > "$ROOT/work/seed_ids.txt"
sed -n '1,4p' "$ROOT/work/requests.tsv" > "$ROOT/work/seed_slices.tsv"
test "$(wc -l < "$ROOT/work/seed_slices.tsv" | tr -d ' ')" = 4

echo "Hydrating $REFSEQ_ACCESSION into $CACHE_REL"
docker run --rm --platform linux/arm64 \
  -v "$ROOT:/workspace" -w /workspace "$IMAGE" \
  /usr/bin/time -v prime_cache \
    -ifmt ids -i work/seed_ids.txt -cache "$CACHE_REL" \
    -extract-delta \
    -oseq-ids work/asn_cache.loaded_ids.txt \
  2>&1 | tee "$RAW/prime_cache.log"

docker run --rm --platform linux/arm64 \
  -v "$ROOT:/workspace" -w /workspace "$IMAGE" \
  asn_cache_test -cache "$CACHE_REL" -i work/seed_ids.txt \
    -test-loader -no-serialize \
  > "$RAW/asn_cache_test.log" 2>&1

docker run --rm --platform linux/arm64 \
  -v "$ROOT:/workspace" -w /workspace "$IMAGE" \
  gks_ncbi_sequence_probe -mode asn -asn-cache "$CACHE_REL" \
    -requests work/seed_slices.tsv -output work/asn_seed_online.jsonl \
    -fail-on-mismatch

docker run --rm --network none --platform linux/arm64 \
  -v "$ROOT:/workspace" -w /workspace "$IMAGE" \
  gks_ncbi_sequence_probe -mode asn -asn-cache "$CACHE_REL" \
    -requests work/seed_slices.tsv -output work/asn_seed_offline.jsonl \
    -fail-on-mismatch

cmp "$ROOT/work/asn_seed_online.jsonl" "$ROOT/work/asn_seed_offline.jsonl" \
  >/dev/null || python3 - "$ROOT/work/asn_seed_online.jsonl" "$ROOT/work/asn_seed_offline.jsonl" <<'PY'
import json, sys
def stable(path):
    rows=[]
    for line in open(path):
        row=json.loads(line)
        row.pop("elapsed_us", None)
        rows.append(row)
    return rows
if stable(sys.argv[1]) != stable(sys.argv[2]):
    raise SystemExit("online and offline ASN slices differ")
PY

du -sk "$ROOT/$CACHE_REL" > "$RAW/cache-size-kib.txt"
echo "ASN cache online/offline verification passed."

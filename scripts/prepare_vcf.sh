#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-gks-ncbi:arm64}"
SOURCE="${SOURCE:-exomes}"
GNOMAD_CONTIG="${GNOMAD_CONTIG:-chrX}"
REFSEQ_ACCESSION="${REFSEQ_ACCESSION:-NC_000023.11}"
GNOMAD_REGION="${GNOMAD_REGION:-chrX:200000-1000000}"
GNOMAD_URL="${GNOMAD_URL:-https://storage.googleapis.com/gcp-public-data--gnomad/release/4.1/vcf/exomes/gnomad.exomes.v4.1.sites.chrX.vcf.bgz}"
MAX_VARIANTS="${MAX_VARIANTS:-100000}"
OUTPUT="$ROOT/work/gnomad.sample.minimal.vcf.bgz"

[[ "$SOURCE" == exomes ]] || { echo "Only SOURCE=exomes is configured" >&2; exit 2; }
[[ "$MAX_VARIANTS" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid MAX_VARIANTS" >&2; exit 2; }
mkdir -p "$ROOT/work" "$ROOT/results/raw/vcf_preparation"

curl -fsSIL --max-time 30 "$GNOMAD_URL" >/dev/null
index=""
for suffix in .tbi .csi; do
    if curl -fsSIL --max-time 30 "${GNOMAD_URL}${suffix}" >/dev/null; then
        index="${GNOMAD_URL}${suffix}"
        break
    fi
done
[[ -n "$index" ]] || { echo "No usable adjacent .tbi or .csi index" >&2; exit 1; }
echo "Using remote index: $index"

docker run --rm --platform linux/arm64 \
  -v "$ROOT:/workspace" -w /workspace "$IMAGE" bash -euo pipefail -c '
    bcftools view -r "$1" "$2" -Ou \
      | bcftools norm -m -any -Ou \
      | bcftools annotate -x ID,QUAL,FILTER,INFO -Ov \
      | python3 scripts/limit_vcf.py --max-records "$3" \
      | bgzip -c > work/gnomad.sample.minimal.vcf.bgz
    tabix -f -p vcf work/gnomad.sample.minimal.vcf.bgz
    bcftools index -f work/gnomad.sample.minimal.vcf.bgz
    bcftools view -h work/gnomad.sample.minimal.vcf.bgz >/dev/null
    # bcftools index stats enforce a .vcf.gz suffix even though BGZF itself
    # does not; validate the required .vcf.bgz artifact through aliases.
    ln -sf /workspace/work/gnomad.sample.minimal.vcf.bgz /tmp/gks-sample.vcf.gz
    ln -sf /workspace/work/gnomad.sample.minimal.vcf.bgz.csi /tmp/gks-sample.vcf.gz.csi
    bcftools index -n /tmp/gks-sample.vcf.gz
    bcftools view -H work/gnomad.sample.minimal.vcf.bgz \
      | python3 scripts/vcf_to_requests.py --accession "$4" --contig "$5" \
          --output work/requests.tsv --stats results/vcf_preparation.json
  ' _ "$GNOMAD_REGION" "$GNOMAD_URL" "$MAX_VARIANTS" "$REFSEQ_ACCESSION" "$GNOMAD_CONTIG" \
  2>&1 | tee "$ROOT/results/raw/vcf_preparation/prepare.log"

python3 - "$ROOT/results/vcf_preparation.json" "$GNOMAD_URL" "$GNOMAD_REGION" "$index" <<'PY'
import json, sys
path, url, region, index = sys.argv[1:]
data = json.load(open(path))
data.update({"url": url, "region": region, "index": index})
open(path, "w").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
test -s "$OUTPUT"
test -s "$OUTPUT.tbi"
test -s "$ROOT/work/requests.tsv"

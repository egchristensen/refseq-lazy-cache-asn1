#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/results"
OUT="$ROOT/results/docker_desktop_diagnostics.txt"

exec > >(tee "$OUT") 2>&1

echo "=== Docker Desktop diagnostics ==="
date -u '+UTC %Y-%m-%dT%H:%M:%SZ'
echo "Workspace: $ROOT"
echo

echo "=== macOS ==="
uname -a
sw_vers
df -h "$HOME"
echo

echo "=== Docker contexts and engine ==="
docker context ls 2>&1 || true
docker version 2>&1 || true
docker info 2>&1 || true
docker buildx ls 2>&1 || true
docker system df 2>&1 || true
echo

echo "=== Host proxy summary ==="
scutil --proxy 2>&1 || true
env | grep -iE '^(http|https|no|all)_proxy=' \
  | sed -E 's#(https?://)[^/@]+@#\1<redacted>@#g' || true
echo

echo "=== Host DNS summary ==="
scutil --dns 2>&1 | sed -n '1,220p' || true
echo

echo "=== Native container architecture and resolver ==="
docker run --rm --platform linux/arm64 alpine:3.20 sh -ec '
  uname -a
  cat /etc/resolv.conf
  apk add --no-cache ca-certificates curl bind-tools >/dev/null
  for name in github.com ftp.ncbi.nlm.nih.gov storage.googleapis.com chatgpt.com; do
    echo "--- $name"
    nslookup "$name" || true
  done
  for url in \
    https://github.com/ \
    https://ftp.ncbi.nlm.nih.gov/ \
    https://storage.googleapis.com/gcp-public-data--gnomad/release/4.1/vcf/exomes/gnomad.exomes.v4.1.sites.chrX.vcf.bgz
  do
    echo "--- $url"
    curl -sSIL --max-time 30 "$url" | sed -n "1,8p" || true
  done
' 2>&1 || true
echo

echo "=== BuildKit diagnostic ==="
docker buildx build \
  --platform linux/arm64 \
  --load \
  --progress=plain \
  -t gks-docker-diagnostic:arm64 \
  - <<'EOF' 2>&1 || true
FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive
RUN set -eux; \
    uname -a; \
    dpkg --print-architecture; \
    cat /etc/resolv.conf; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl dnsutils; \
    nslookup github.com; \
    curl -fsSIL --max-time 30 https://github.com/ >/dev/null; \
    curl -fsSIL --max-time 30 https://ftp.ncbi.nlm.nih.gov/ >/dev/null
EOF

echo
echo "=== File-sharing diagnostic ==="
docker run --rm --platform linux/arm64 \
  -v "$ROOT:/workspace:ro" alpine:3.20 \
  sh -ec 'ls -la /workspace; test -r /workspace/PLAN.md' 2>&1 || true

echo
echo "Diagnostics complete: $OUT"

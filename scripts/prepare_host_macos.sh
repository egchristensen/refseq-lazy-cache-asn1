#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/results"
OUT="$ROOT/results/host_bootstrap.txt"

exec > >(tee "$OUT") 2>&1

echo "=== NCBI-native GKS MacBook host preflight ==="
date -u '+UTC %Y-%m-%dT%H:%M:%SZ'
echo "Workspace: $ROOT"
echo

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

warn() {
  echo "WARNING: $*" >&2
}

[[ "$(uname -s)" == "Darwin" ]] || fail "This bundle expects macOS."
[[ "$(uname -m)" == "arm64" ]] || fail "This bundle expects Apple silicon (arm64)."

echo "=== Host ==="
uname -a
sw_vers
printf 'Model: '
sysctl -n hw.model 2>/dev/null || true
printf 'Logical CPUs: '
sysctl -n hw.logicalcpu
printf 'Memory bytes: '
sysctl -n hw.memsize
system_profiler SPHardwareDataType 2>/dev/null | sed -n '1,30p' || true
df -h "$HOME"
echo

case "$ROOT" in
  "$HOME"/*) echo "Workspace is under HOME: yes" ;;
  *) warn "Workspace is outside HOME. Docker Desktop file sharing may require configuration." ;;
esac

echo "=== Host tools ==="
command -v git && git --version
command -v curl && curl --version | head -1
command -v python3 && python3 --version
command -v clang && clang --version | head -1 || true
command -v caffeinate || warn "caffeinate not found"
echo

if [[ ! -d /Applications/Docker.app ]] && [[ ! -d "$HOME/Applications/Docker.app" ]]; then
  fail "Docker Desktop.app was not found. Install the Apple-silicon Docker Desktop release and start it."
fi

command -v docker >/dev/null 2>&1 || fail "Docker CLI is not on PATH. Finish Docker Desktop setup."
docker version >/dev/null 2>&1 || fail "Docker Desktop daemon is not ready. Start Docker Desktop and wait for it to finish."

echo "=== Docker Desktop ==="
docker context show
docker context ls
docker version
docker buildx version
docker compose version
docker info

server_os="$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || true)"
server_arch="$(docker info --format '{{.Architecture}}' 2>/dev/null || true)"
mem_bytes="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"
cpu_count="$(docker info --format '{{.NCPU}}' 2>/dev/null || echo 0)"

echo "Docker server OS: $server_os"
echo "Docker server architecture: $server_arch"
echo "Docker CPUs: $cpu_count"
echo "Docker memory bytes: $mem_bytes"

[[ "$server_os" == *"Docker Desktop"* || "$server_os" == *"Linux"* ]] || warn "Unexpected Docker server OS: $server_os"
case "$server_arch" in
  aarch64|arm64) ;;
  *) fail "Docker daemon is not native ARM64; got architecture '$server_arch'." ;;
esac

min_mem=$((14 * 1024 * 1024 * 1024))
if [[ "$mem_bytes" =~ ^[0-9]+$ ]] && (( mem_bytes < min_mem )); then
  warn "Docker VM has less than 14 GiB. Configure about 16 GiB in Docker Desktop before the full build."
fi
if [[ "$cpu_count" =~ ^[0-9]+$ ]] && (( cpu_count < 8 )); then
  warn "Docker VM has fewer than 8 CPUs. Configure about 10 CPUs before the full build."
fi

echo "=== Native ARM and file-sharing test ==="
docker run --rm --platform linux/arm64 \
  -v "$ROOT:/workspace:ro" \
  alpine:3.20 \
  sh -ec '
    arch="$(uname -m)"
    echo "container architecture=$arch"
    case "$arch" in aarch64|arm64) ;; *) exit 20 ;; esac
    test -r /workspace/PLAN.md
  '

echo "=== Bridge DNS/HTTPS test ==="
docker run --rm --platform linux/arm64 alpine:3.20 sh -ec '
  apk add --no-cache ca-certificates curl bind-tools >/dev/null
  nslookup github.com >/dev/null
  curl -fsSIL --max-time 30 https://github.com/ >/dev/null
  curl -fsSIL --max-time 30 https://ftp.ncbi.nlm.nih.gov/ >/dev/null
  curl -fsSIL --max-time 30 \
    https://storage.googleapis.com/gcp-public-data--gnomad/release/4.1/vcf/exomes/gnomad.exomes.v4.1.sites.chrX.vcf.bgz \
    >/dev/null
'

echo "=== BuildKit native ARM network test ==="
docker buildx build \
  --platform linux/arm64 \
  --load \
  --progress=plain \
  -t gks-docker-network-smoke:arm64 \
  - <<'EOF'
FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive
RUN uname -m \
 && test "$(dpkg --print-architecture)" = arm64 \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -fsSIL --max-time 30 https://github.com/ >/dev/null \
 && curl -fsSIL --max-time 30 https://ftp.ncbi.nlm.nih.gov/ >/dev/null \
 && rm -rf /var/lib/apt/lists/*
EOF

echo "=== Offline negative control ==="
if docker run --rm --network none --platform linux/arm64 \
    alpine:3.20 wget -qO- https://github.com/ >/dev/null 2>&1; then
  fail "Offline negative control unexpectedly reached the network."
else
  echo "Offline negative control failed as expected."
fi

echo "=== Disk usage ==="
docker system df
df -h "$ROOT"
echo
echo "Host preflight completed. Review warnings before the full build."

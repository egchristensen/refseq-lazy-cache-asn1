#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="$ROOT/results"
OUT="$RESULTS/preflight.txt"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/arm64}"
MIN_DOCKER_CPUS=8
MIN_DOCKER_MEMORY=$((14 * 1024 * 1024 * 1024))
MIN_FREE_GIB=100

mkdir -p "$RESULTS"
exec > >(tee "$OUT") 2>&1

fail() { echo "GATE_H_FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

echo "=== Gate H preflight ==="
date -u '+UTC %Y-%m-%dT%H:%M:%SZ'
echo "Workspace: $ROOT"
echo "Primary platform: $TARGET_PLATFORM"

[[ "$(uname -s)" == Darwin ]] || fail "host OS is not Darwin"
[[ "$(uname -m)" == arm64 ]] || fail "host architecture is not arm64"
[[ "$TARGET_PLATFORM" == linux/arm64 ]] || fail "primary platform must be linux/arm64"
case "$ROOT" in "$HOME"/*) ;; *) fail "workspace is not under HOME" ;; esac
pass "native Apple-silicon host and workspace location"

echo
echo "=== Host evidence ==="
uname -a
sw_vers
sysctl -n hw.model hw.logicalcpu hw.memsize
df -h "$ROOT"
clang --version | sed -n '1p'
for tool in git curl gzip python3 caffeinate docker; do
    command -v "$tool" || fail "missing host tool: $tool"
done
curl -fsSIL --max-time 30 https://github.com/ >/dev/null
curl -fsSIL --max-time 30 https://ftp.ncbi.nlm.nih.gov/ >/dev/null
curl -fsSIL --max-time 30 \
  https://storage.googleapis.com/gcp-public-data--gnomad/release/4.1/vcf/exomes/gnomad.exomes.v4.1.sites.chrX.vcf.bgz \
  >/dev/null
pass "host HTTPS endpoints"

free_kib="$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')"
(( free_kib >= MIN_FREE_GIB * 1024 * 1024 )) || \
  fail "less than ${MIN_FREE_GIB} GiB free on workspace volume"

echo
echo "=== Proxy evidence (credentials redacted) ==="
scutil --proxy
env | grep -iE '^(http|https|no|all)_proxy=' \
  | sed -E 's#(https?://)[^/@]+@#\1<redacted>@#g' || true

[[ -d /Applications/Docker.app || -d "$HOME/Applications/Docker.app" ]] || \
  fail "Docker Desktop.app is not installed"
docker version >/dev/null 2>&1 || fail "Docker Desktop daemon is not ready"
context="$(docker context show)"
[[ "$context" == desktop-linux ]] || fail "active context is '$context', expected desktop-linux"

echo
echo "=== Docker evidence ==="
docker context ls
docker version
docker buildx version
docker compose version
docker info
docker system df

server_os="$(docker info --format '{{.OSType}}')"
server_arch="$(docker info --format '{{.Architecture}}')"
docker_cpus="$(docker info --format '{{.NCPU}}')"
docker_memory="$(docker info --format '{{.MemTotal}}')"
storage_driver="$(docker info --format '{{.Driver}}')"
[[ "$server_os" == linux ]] || fail "Docker daemon OS is '$server_os'"
case "$server_arch" in arm64|aarch64) ;; *) fail "Docker daemon is '$server_arch'" ;; esac
(( docker_cpus >= MIN_DOCKER_CPUS )) || fail "Docker has fewer than $MIN_DOCKER_CPUS CPUs"
(( docker_memory >= MIN_DOCKER_MEMORY )) || fail "Docker has less than 14 GiB memory"
echo "Docker storage driver: $storage_driver"
pass "local native ARM Docker Desktop resources"

docker run --rm --platform linux/arm64 -v "$ROOT:/workspace:ro" alpine:3.20 \
  sh -ec 'case "$(uname -m)" in arm64|aarch64) ;; *) exit 1;; esac; test -r /workspace/PLAN.md'
pass "native container and read-only repository mount"

docker run --rm --platform linux/arm64 alpine:3.20 sh -ec '
  apk add --no-cache ca-certificates curl bind-tools >/dev/null
  nslookup github.com >/dev/null
  curl -fsSIL --max-time 30 https://github.com/ >/dev/null
  curl -fsSIL --max-time 30 https://ftp.ncbi.nlm.nih.gov/ >/dev/null
  curl -fsSIL --max-time 30 https://storage.googleapis.com/gcp-public-data--gnomad/release/4.1/vcf/exomes/gnomad.exomes.v4.1.sites.chrX.vcf.bgz >/dev/null
'
pass "bridge DNS and HTTPS"

docker buildx build --platform linux/arm64 --load --progress=plain \
  -t gks-preflight:arm64 - <<'EOF'
FROM ubuntu:22.04
RUN test "$(dpkg --print-architecture)" = arm64 \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -fsSIL --max-time 30 https://github.com/ >/dev/null \
 && curl -fsSIL --max-time 30 https://ftp.ncbi.nlm.nih.gov/ >/dev/null \
 && rm -rf /var/lib/apt/lists/*
EOF
pass "native BuildKit apt and HTTPS"

if docker run --rm --network none --platform linux/arm64 alpine:3.20 \
    wget -qO- https://github.com/ >/dev/null 2>&1; then
    fail "offline negative control unexpectedly reached GitHub"
fi
pass "offline negative control failed as expected"

echo
echo "Build compiler assertion: GCC 12 and C++20 inside Ubuntu 22.04 linux/arm64; host Clang is diagnostic only."
test -s "$RESULTS/host_bootstrap.txt" || fail "host_bootstrap.txt is missing"
test -s "$RESULTS/docker_desktop_diagnostics.txt" || fail "docker_desktop_diagnostics.txt is missing"
echo "GATE_H_PASS"

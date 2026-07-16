#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/arm64}"
NCBI_BUILD_JOBS="${NCBI_BUILD_JOBS:-8}"
NCBI_CXX_TOOLKIT_REF="${NCBI_CXX_TOOLKIT_REF:-fe8144adf21fc19db6b9c8c96aa623965419e8bd}"
IMAGE="${IMAGE:-gks-ncbi:arm64}"
LOG_DIR="$ROOT/results/raw/build_arm64"
LOG="$LOG_DIR/build.log"

[[ "$TARGET_PLATFORM" == linux/arm64 ]] || {
    echo "Refusing non-native primary platform: $TARGET_PLATFORM" >&2
    exit 2
}
[[ "$NCBI_BUILD_JOBS" =~ ^[1-8]$ ]] || {
    echo "NCBI_BUILD_JOBS must be between 1 and 8" >&2
    exit 2
}

mkdir -p "$LOG_DIR"
exec > >(tee "$LOG") 2>&1
echo "UTC start: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Platform: $TARGET_PLATFORM"
echo "Jobs: $NCBI_BUILD_JOBS"
echo "Toolkit: $NCBI_CXX_TOOLKIT_REF"
echo "Image: $IMAGE"

docker buildx build \
  --platform "$TARGET_PLATFORM" \
  --load \
  --progress=plain \
  --build-arg "NCBI_BUILD_JOBS=$NCBI_BUILD_JOBS" \
  --build-arg "NCBI_CXX_TOOLKIT_REF=$NCBI_CXX_TOOLKIT_REF" \
  -t "$IMAGE" \
  "$ROOT"

docker image inspect "$IMAGE" > "$LOG_DIR/image-inspect.json"
echo "UTC end: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

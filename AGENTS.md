# AGENTS.md

## Project

This workspace implements the NCBI-native GKS sequence backend experiment specified in `PLAN.md`.

## Environment

- Local macOS workspace on Apple silicon
- Expected host: M4 Max, 32 GB memory
- Docker Desktop
- Primary build and runtime platform: `linux/arm64`
- Ubuntu 22.04 builder
- GCC 12 and C++20 inside the container
- Codex runs in the local VS Code extension

## Read first

1. `PLAN.md`
2. `MACBOOK_SETUP.md`
3. `CODEX_PROMPT.md`
4. `data/refseq_accessions.txt`

## Safety

- No silent software installation or license acceptance.
- No `sudo docker`.
- No macOS firewall, DNS, VPN, proxy, certificate, login-item, or Docker Desktop setting changes without approval.
- No Rosetta or `linux/amd64` fallback without a preserved ARM failure and approval.
- No destructive Docker prune commands.
- Never delete unrelated images, volumes, builders, or caches.
- No downloads of the complete gnomAD chromosome VCF when indexed slicing works.
- No host compiler or host C++ libraries in the NCBI build.
- No NCBI build tree bind-mounted onto macOS.
- No claims of cache behavior without evidence.

## Build defaults

```text
TARGET_PLATFORM=linux/arm64
NCBI_BUILD_JOBS=8
NCBI_CXX_TOOLKIT_REF=fe8144adf21fc19db6b9c8c96aa623965419e8bd
GCC_MAJOR=12
```

The plan's initial toolkit pin (`203e594d...`) was tried first and its native
build log was preserved. It requires GCC 13, so the experiment uses the
immediately preceding GCC 12-compatible toolkit revision shown above.

Reduce build jobs before increasing Docker memory when memory pressure occurs.

## Required checks

```bash
bash scripts/prepare_host_macos.sh
bash scripts/diagnose_docker_desktop.sh
```

Run project tests and inspect their output before reporting success.

## Git

Create logical local commits. Do not push or rewrite unrelated history.

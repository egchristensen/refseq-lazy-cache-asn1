Work locally in the currently open VS Code workspace and execute the repository's NCBI-native GKS experiment plan.

Read these files completely before editing anything:

1. `AGENTS.md`
2. `PLAN.md`
3. `MACBOOK_SETUP.md`
4. `CODEX_PROMPT.md`
5. `data/refseq_accessions.txt`
6. All existing source, scripts, tests, and results

This run is on an Apple-silicon MacBook Pro with an M4 Max, 32 GB unified memory, and a 2 TB SSD. Codex is running locally in VS Code. Docker Desktop is the container runtime.

Operating constraints:

- Verify the actual macOS version, `arm64` architecture, free disk, and Docker Desktop state.
- The primary container platform is `linux/arm64`.
- Build the NCBI C++ Toolkit inside an Ubuntu 22.04 ARM64 builder using explicitly selected GCC 12 and C++20.
- Do not use Apple Clang, Homebrew C++ libraries, host SDKs, `-march=native`, or host-built libraries in the image.
- Do not bind-mount the NCBI source/build tree onto macOS; keep compilation inside Docker layers or BuildKit caches.
- Start with no more than 8 parallel build jobs.
- Do not use `sudo docker`.
- Do not install Docker Desktop, accept licenses, change Docker Desktop resources, enable Rosetta, switch virtualization frameworks, alter macOS networking, or modify certificates without explaining the need and asking me first.
- If Docker Desktop is missing or not running, stop and give me the exact manual step.
- Use `linux/amd64` only as an approved fallback after preserving a native ARM failure and proving it is architecture-specific.
- Any amd64-emulated benchmark is non-representative and may support only functional conclusions.
- Keep the repository under my home directory and keep all generated data in the workspace or Docker-managed storage.
- Do not download a complete gnomAD chromosome VCF when indexed regional access works.
- Default to chrX and `NC_000023.11`; preserve a selectable chr22 profile and document the original chr22/chrX discrepancy.
- Do not claim persistent, lazy, range-reusable, write-through, warm, or offline cache behavior until the specified tests prove it.
- Preserve complete error logs and record every deviation from the pinned toolkit revision or build platform.
- Make logical local git commits, but do not push.

First:

1. Report the workspace root and current git status.
2. Run the non-destructive checks in `scripts/prepare_host_macos.sh`.
3. Confirm Docker's active context, daemon OS/architecture, allocated CPUs and memory, and disk usage.
4. Confirm a native `linux/arm64` container runs.
5. Confirm the repository can be mounted read-only into a container.
6. Run the bridge-network, BuildKit-network, and `--network none` control checks.
7. Compare the repository contents with the required layout in `PLAN.md`.
8. Create or update `AGENTS.md` only if the bundled version is incomplete.

After the initial report, proceed with the first safe implementation phase. Do not stop merely to ask whether you should continue. Stop only when an action needs my approval or a material blocker has been demonstrated.

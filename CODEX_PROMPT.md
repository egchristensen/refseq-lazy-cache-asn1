# Codex task — local Apple-silicon MacBook

Execute `PLAN.md` in the currently open local VS Code workspace.

Read completely, in this order:

1. `AGENTS.md`
2. `PLAN.md`
3. `MACBOOK_SETUP.md`
4. `SIDEBAR_PROMPT.md`
5. `data/refseq_accessions.txt`
6. Existing source, scripts, tests, and results

Host assumptions:

- macOS on Apple silicon, expected `arm64`
- M4 Max
- 32 GB unified memory
- 2 TB SSD
- Codex is running locally in the VS Code extension
- Docker Desktop is the container runtime
- primary container platform is `linux/arm64`
- NCBI compilation uses GCC 12/C++20 inside Ubuntu 22.04 containers
- Apple Clang and Homebrew C++ libraries are diagnostic only and must not enter the build

Rules:

1. Run only non-destructive host checks until Docker Desktop readiness and workspace safety are established.
2. If Docker Desktop is absent, stopped, still starting, or points to an unrelated context, stop and tell the user exactly what needs attention.
3. Never use `sudo docker`, install Docker Desktop silently, accept licenses, or modify Docker Desktop settings without approval.
4. Keep the primary build native `linux/arm64`.
5. Do not enable Rosetta, switch virtualization frameworks, or build `linux/amd64` until a documented architecture-specific ARM failure has been preserved and the user approves the fallback.
6. Treat emulated amd64 performance as non-representative.
7. Use bounded build parallelism, initially no more than 8 jobs.
8. Do not use the host compiler, `-march=native`, host C++ libraries, or a bind-mounted NCBI source/build tree.
9. Keep all generated project data under the workspace or Docker-managed storage.
10. Do not download a whole gnomAD chromosome VCF when indexed regional access works.
11. Default to the supplied chrX object and `NC_000023.11`; retain a chr22 profile and document the mismatch.
12. Treat all cache properties as hypotheses until the required new-process and offline tests prove them.
13. Preserve logs and failures.
14. Commit logical milestones locally; do not push.
15. Finish with the exact recommendation scheme required by `PLAN.md`.

Begin by reporting:

- workspace root;
- git status;
- macOS version and architecture;
- Docker Desktop context, daemon architecture, CPUs, memory, and disk state;
- whether native `linux/arm64` and repository bind mounting work;
- whether required instruction/data files are present;
- any conflict between repository state and `PLAN.md`.

Then proceed immediately through the first safe implementation steps. Stop only for a genuinely privileged, host-wide, GUI-dependent, destructive, or architecture-fallback decision.

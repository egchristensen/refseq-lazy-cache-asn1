# NCBI-Native GKS Sequence Backend Spike
## Codex execution plan

**Prepared:** 2026-07-15  
**MacBook revision:** 2026-07-16  
**Revised for local laptop:** Apple-silicon MacBook Pro (M4 Max, 32 GB RAM, 2 TB SSD)  
**Primary ticket:** https://github.com/ga4gh/gks-portal/issues/59  
**Purpose:** Build and evaluate an NCBI-native sequence retrieval and caching proof of concept using the NCBI C++ Toolkit Object Manager, GenBank loader, GenBank reader cache, ASN cache, and `prime_cache`.

---

## 1. Mission

Create a reproducible, Dockerized experiment that answers this question:

> Can NCBI's native Object Manager and data-loader stack provide a practical sequence backend for GKS/VRS workloads, with transparent local reuse of previously fetched sequence data and a viable offline/warm-cache mode?

The implementation must use the existing Docker project below as its starting point, not replace it with an unrelated installation approach:

- Baseline repository: https://github.com/egchristensen/ncbi_cxx_toolkit_installation_docker
- Baseline commit to start from: `6278e477f281dd0f04d150d059e51a9a88da47cd`

Pin the NCBI C++ Toolkit checkout for reproducibility:

- Toolkit repository: https://github.com/ncbi/ncbi-cxx-toolkit-public
- Initial pin: `203e594d7b4cad620d597a2bb8afef8e391e4eb8`

The pin may be changed only if that commit cannot build on the target MacBook. Record any replacement commit and the reason in `results/report.md`.

---


## 2. Local-host bootstrap: Apple-silicon MacBook and Docker Desktop

The target MacBook is an Apple-silicon MacBook Pro with an M4 Max, 32 GB unified memory, and a 2 TB SSD. Codex will run locally in the VS Code extension. The NCBI software itself must still build and run in Linux containers.

Use **Docker Desktop for Mac (Apple silicon)**. Do not attempt to install the Linux Docker daemon directly on macOS. Docker Desktop runs the Linux daemon and containers in a managed Linux virtual machine.

### 2.1 Host and interaction rules

Codex must first run these non-destructive checks:

```bash
pwd
uname -a
uname -m
sw_vers
sysctl -n hw.logicalcpu
sysctl -n hw.memsize
df -h "$HOME"
command -v docker || true
docker context show 2>/dev/null || true
docker version 2>/dev/null || true
docker info 2>/dev/null || true
```

Rules:

1. Verify `uname -s` is `Darwin` and `uname -m` is `arm64`.
2. Work in a repository located under the user's home directory, preferably `~/Projects/refseq-lazy-cache-asn1`, so Docker Desktop file sharing works without additional host configuration.
3. If Docker Desktop is absent, stopped, or not fully initialized, Codex must stop and ask the user to install/start Docker Desktop for Apple silicon. It must not silently install a cask, accept a license, or change Docker Desktop settings.
4. Never use `sudo docker`; Docker Desktop is a per-user application and does not use the Linux `docker` group workflow.
5. Do not install or switch the macOS system compiler for this project.
6. Do not modify macOS firewall, DNS, VPN, proxy, certificate, login-item, or virtualization settings without a demonstrated failure and explicit user approval.
7. Do not expose the Docker socket over TCP.
8. Do not run privileged containers unless a specific NCBI test requires it and the reason is explained first. The required plan should not need privileged containers.
9. Do not publish inbound ports. This experiment is batch-oriented.
10. Keep the laptop connected to power during long builds. For a long approved command, Codex may prefix the command with `caffeinate -dimsu --` so sleep does not interrupt it.

### 2.2 Docker Desktop installation and first launch

When Docker Desktop is not installed, instruct the user to install the current Apple-silicon release from Docker's official Mac installation page and complete the first-launch prompts.

After the user starts Docker Desktop, Codex must verify:

```bash
docker context show
docker version
docker info
docker buildx version
docker compose version
docker run --rm hello-world
```

Expected state:

- active context is normally `desktop-linux`;
- daemon operating system is Linux;
- daemon architecture is `aarch64` or `arm64`;
- Buildx is available;
- ordinary Docker commands work without `sudo`.

Do not continue while Docker Desktop reports “starting,” the daemon is unreachable, or the active context points to an unrelated remote engine.

### 2.3 Recommended Docker Desktop resources for this laptop

Before the NCBI build, ask the user to inspect **Docker Desktop → Settings → Resources**.

Recommended starting allocation:

```text
Memory: 16 GB
CPUs: 8–12, with 10 as a reasonable starting value
Swap: 2–4 GB if that setting is available
Docker disk image maximum: at least 200 GB
```

Requirements:

1. Leave enough memory and CPU for macOS and VS Code; do not allocate all 32 GB or all CPU cores.
2. `docker info` should report at least 14 GiB available to the Docker VM before the full toolkit build.
3. Keep at least 100 GiB free on the macOS volume before the scale phase. The smoke build may proceed with less, but Codex must record the value and stop before a large operation that would exhaust the disk.
4. If the build is killed for memory pressure, preserve the log and ask the user to raise Docker memory to 20 GB before retrying. Do not immediately switch architectures or toolkit revisions.
5. Do not use an unbounded parallel build. Start with:

```text
NCBI_BUILD_JOBS=min(8, available Docker CPUs)
```

Reduce to 4 if memory pressure or thermal throttling is observed.

### 2.4 Native Apple-silicon build is the primary path

The primary platform is:

```text
linux/arm64
```

Required safeguards:

1. Build and run the primary image with an explicit platform:

```bash
docker buildx build \
  --platform linux/arm64 \
  --load \
  --progress=plain \
  -t gks-ncbi:arm64 \
  .
```

2. Use an Ubuntu 22.04 **arm64** builder stage.
3. Pin GCC 12 and C++20 inside the builder container.
4. Print and record all of the following during the build:

```bash
uname -m
dpkg --print-architecture
gcc-12 --version
g++-12 --version
cmake --version
```

5. Fail the primary build if the builder reports `x86_64`/`amd64`; accidental emulation must not be mistaken for a native result.
6. Add `ARG TARGETARCH` and an OCI image label recording `TARGETARCH`, toolkit commit, and compiler.
7. Do not use `-march=native`, Apple Clang, Homebrew C++ libraries, or bind-mounted host libraries.
8. Keep the NCBI source and compilation tree inside Docker build layers or BuildKit cache mounts. Do not bind-mount the source/build tree onto the default case-insensitive macOS filesystem.
9. Runtime invocations must also use `--platform linux/arm64` until an image inspection confirms its architecture.

### 2.5 Controlled Intel fallback

A `linux/amd64` build is allowed only after the native `linux/arm64` failure is captured and classified as architecture-specific.

Before an Intel fallback:

1. Preserve the full native configure/build log in `results/raw/build_arm64/`.
2. Confirm the failure is not a missing dependency, incorrect CMake target, insufficient memory, or unrelated source error.
3. Ask the user before enabling or installing Rosetta 2 or changing Docker Desktop's virtual-machine settings.
4. When Docker Desktop offers the setting, Intel emulation may use the Apple Virtualization framework with Rosetta acceleration.
5. Build explicitly:

```bash
docker buildx build \
  --platform linux/amd64 \
  --load \
  --progress=plain \
  -t gks-ncbi:amd64 \
  .
```

6. Record that the image is emulated.
7. Use an emulated image for functional correctness and cache-semantics tests only. Do not use its throughput or latency as representative M4 Max performance.
8. Do not change the toolkit commit in the same experiment step that changes architecture.

If both architectures fail, diagnose the common build error before changing the pinned toolkit revision.

### 2.6 Docker Desktop network and file-sharing acceptance tests

The bundle includes:

```text
scripts/prepare_host_macos.sh
scripts/diagnose_docker_desktop.sh
MACBOOK_SETUP.md
```

All of the following must pass before the NCBI image build:

```bash
# Verify native Linux architecture and repository file sharing.
docker run --rm --platform linux/arm64 \
  -v "$PWD:/workspace:ro" \
  alpine:3.20 \
  sh -ec 'uname -m; test -r /workspace/PLAN.md'

# DNS and HTTPS from a normal Docker Desktop container.
docker run --rm --platform linux/arm64 alpine:3.20 sh -ec '\
  apk add --no-cache ca-certificates curl bind-tools >/dev/null; \
  nslookup github.com; \
  curl -fsSIL --max-time 30 https://github.com/ >/dev/null; \
  curl -fsSIL --max-time 30 https://ftp.ncbi.nlm.nih.gov/ >/dev/null; \
  curl -fsSIL --max-time 30 https://storage.googleapis.com/gcp-public-data--gnomad/release/4.1/vcf/exomes/gnomad.exomes.v4.1.sites.chrX.vcf.bgz >/dev/null'

# BuildKit DNS, apt, TLS, and outbound HTTPS on the native platform.
docker buildx build --platform linux/arm64 --load --progress=plain \
  -t gks-docker-network-smoke - <<'EOF'
FROM ubuntu:22.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -fsSIL --max-time 30 https://github.com/ >/dev/null \
 && curl -fsSIL --max-time 30 https://ftp.ncbi.nlm.nih.gov/ >/dev/null \
 && rm -rf /var/lib/apt/lists/*
EOF
```

Also record the offline control:

```bash
! docker run --rm --network none --platform linux/arm64 \
  alpine:3.20 wget -qO- https://github.com/
```

The offline control must fail.

### 2.7 Docker Desktop troubleshooting order

When macOS can reach the internet but a container cannot, collect evidence before changing settings:

```bash
docker context ls
docker version
docker info
docker system df
docker network inspect bridge || true
docker run --rm --platform linux/arm64 alpine:3.20 cat /etc/resolv.conf
scutil --dns
scutil --proxy
env | grep -iE '^(http|https|no|all)_proxy=' || true
```

Troubleshoot in this order:

1. **Docker Desktop not ready:** open Docker Desktop and wait until the engine is running.
2. **Wrong context:** switch only to the expected local Docker Desktop context after confirming it exists.
3. **Workspace not shared:** move the repository under `$HOME`, or ask the user to add the directory in Docker Desktop file-sharing settings.
4. **VPN/proxy issue:** compare the same request on macOS and inside a container. Ask before changing Docker Desktop proxy or networking settings.
5. **TLS inspection:** use only an approved organizational CA. Never use `curl -k`, `GIT_SSL_NO_VERIFY`, or disabled certificate checks.
6. **BuildKit-only failure:** reproduce with the supplied inline Dockerfile and inspect its full output before changing global settings.
7. **Intel-only failure:** do not enable Rosetta merely to solve a native ARM network problem.

Do not edit Linux firewall rules from the Mac plan; Docker Desktop's Linux VM is managed by Docker Desktop.

### 2.8 Compiler/toolchain isolation

Compilation occurs entirely inside the Linux builder container.

Use:

```dockerfile
ARG GCC_MAJOR=12
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-${GCC_MAJOR} g++-${GCC_MAJOR} \
    build-essential cmake ninja-build pkg-config ccache \
    # existing toolkit dependencies continue here
ENV CC=/usr/bin/gcc-12
ENV CXX=/usr/bin/g++-12
```

Pass explicitly to CMake:

```text
-DCMAKE_C_COMPILER=/usr/bin/gcc-12
-DCMAKE_CXX_COMPILER=/usr/bin/g++-12
-DCMAKE_CXX_STANDARD=20
-DCMAKE_CXX_STANDARD_REQUIRED=ON
-DCMAKE_CXX_EXTENSIONS=OFF
```

Record the host Apple Clang version for diagnostics, but state clearly that Apple Clang and macOS SDKs were not used to compile the toolkit.


## 3. Required outcome

The finished repository must:

1. Provide and validate a non-destructive Apple-silicon MacBook and Docker Desktop preflight path, including native-ARM, file-sharing, bridge-network, BuildKit, and offline-control tests.
2. Build an image containing the NCBI C++ Toolkit tools already present in the baseline image, including `prime_cache`, plus a new C++ executable named `gks_ncbi_sequence_probe`.
3. Support three explicit loader modes:
   - `genbank`: remote GenBank loader only.
   - `asn`: local ASN cache only.
   - `hybrid`: ASN cache at priority 1 and GenBank at priority 2.
4. Separately test the GenBank loader's native `cache;id2` reader configuration as a candidate lazy/write-through disk cache.
5. Create a small, stripped gnomAD v4.1 VCF sample without downloading or retaining unnecessary INFO annotations.
6. Convert each VCF record into a 0-based, half-open reference sequence request and compare the sequence returned by Object Manager with the VCF REF allele.
7. Measure cold, warm-same-process, warm-new-process, and offline behavior.
8. Explicitly test nested ranges, such as fetching a larger interval and then a contained interval, and determine whether the second request requires network traffic.
9. Produce machine-readable metrics and a human-readable recommendation.
10. Keep all generated caches, downloads, and build output inside configurable workspace directories.
11. Never claim that ASN cache is write-through unless the experiment proves it. Treat pre-seeded ASN cache and GenBank reader cache as distinct mechanisms.

---

## 4. Important interpretation of the ticket

The ticket requires more than exact request memoization. If an earlier fetch makes a sequence blob or larger interval available locally, a later contained interval should be served without another remote fetch.

NCBI Object Manager normally works with sequence records/blobs rather than a cache key composed only of `(accession, start, end)`. This may naturally satisfy contained-range reuse after a record has been loaded, but it may also over-fetch an entire chromosome-scale record. Measure both the benefit and the cost.

There are two different NCBI-native cache paths to evaluate:

### A. Pre-seeded ASN cache

`prime_cache -ifmt ids` registers the GenBank loader, retrieves complete sequence entries by identifier, and writes an ASN cache. `CAsnCache_DataLoader` then reads that local cache.

This path is expected to be deterministic and suitable for offline use after hydration. Do not assume that a miss handled by a lower-priority GenBank loader is automatically written into the ASN cache.

### B. GenBank reader cache

The GenBank loader supports a reader order such as `cache;id2`, with local ID and blob caches. This is the candidate for transparent lazy caching after a remote fetch.

The experiment must determine whether the public toolkit build and configuration actually provide persistent warm-new-process and offline replay behavior for the selected records.

---

## 5. Scope

### Required

- Genomic sequence retrieval on GRCh38.
- Direct accession/range queries through Object Manager.
- REF validation using a gnomAD v4.1 exomes VCF sample.
- Alias/identifier enumeration where available from Object Manager.
- Cache correctness and performance characterization.
- Reproducible Docker build.
- Results report with an adopt / conditional-adopt / reject decision.

### Optional only after all required acceptance tests pass

- A persistent JSONL server mode suitable for a Python wrapper.
- A minimal `vrs-python` adapter spike against a pinned revision.
- Transcript benchmarks using a small list of `NM_` accessions.
- Bulk FASTA hydration using a selected RefSeq asset from `data/refseq_accessions.txt`.

### Non-goals

- Replacing UTA end-to-end.
- Reproducing transcript alignment and exon mapping semantics.
- Production deployment, authentication, multi-tenancy, or autoscaling.
- Building a full VRS implementation in C++.
- Downloading the full gnomAD chromosome file when indexed remote slicing works.
- Downloading all RefSeq paths in the supplied list.

---

## 6. Data profiles and the chr22/chrX discrepancy

The request says “chr22,” but the supplied object is for chrX. Do not silently choose one.

Implement both profiles and default to the exact supplied URL:

### Default profile: chrX

```text
GNOMAD_CONTIG=chrX
REFSEQ_ACCESSION=NC_000023.11
GNOMAD_URL=https://storage.googleapis.com/gcp-public-data--gnomad/release/4.1/vcf/exomes/gnomad.exomes.v4.1.sites.chrX.vcf.bgz
GNOMAD_REGION=chrX:200000-1000000
```

### Alternate profile: chr22

```text
GNOMAD_CONTIG=chr22
REFSEQ_ACCESSION=NC_000022.11
GNOMAD_URL=https://storage.googleapis.com/gcp-public-data--gnomad/release/4.1/vcf/exomes/gnomad.exomes.v4.1.sites.chr22.vcf.bgz
GNOMAD_REGION=chr22:16000000-18000000
```

Before a data run:

1. Check the VCF object with `curl --fail --location --head`.
2. Check for an adjacent `.tbi` and then `.csi` index.
3. Use `bcftools view -r` against the remote indexed object.
4. Fail clearly if neither index is usable.
5. Only then consider accepting a user-supplied chunk.

No user upload should be needed when the MacBook can reach the public GCS object and its index.

---

## 7. Expected repository layout

Create this layout:

```text
.
├── AGENTS.md
├── README.md
├── MACBOOK_SETUP.md
├── Dockerfile
├── Makefile
├── .gitignore
├── config/
│   ├── genbank-remote.ini
│   └── genbank-bdb-cache.ini
├── data/
│   ├── refseq_accessions.txt
│   ├── primary_accessions.tsv
│   └── transcript_smoke_ids.txt
├── docker/
│   ├── CMakeLists.gks_ncbi_sequence_probe.app.txt
│   └── patch_toolkit_tree.sh
├── scripts/
│   ├── prepare_host_macos.sh
│   ├── diagnose_docker_desktop.sh
│   ├── preflight.sh
│   ├── prepare_vcf.sh
│   ├── seed_asn_cache.sh
│   ├── run_experiment_matrix.sh
│   ├── run_one_case.sh
│   ├── measure_network.sh
│   └── summarize_results.py
├── src/
│   └── gks_ncbi_sequence_probe.cpp
├── tests/
│   ├── smoke.sh
│   ├── test_coordinate_conversion.py
│   └── test_result_schema.py
├── work/
│   └── .gitkeep
└── results/
    └── .gitkeep
```

Do not commit generated caches, toolkit sources, VCF data, build trees, or result logs.

---

## 8. Phase 0 — MacBook preflight

Create `scripts/preflight.sh`. It must refuse to start the full build until Gate H passes. It must check and record:

- macOS version, Darwin kernel, and `arm64` host architecture;
- Mac model, logical CPU count, and total unified memory;
- free space on the workspace volume;
- whether the workspace is under `$HOME`;
- Docker Desktop installation and running state;
- active Docker context, client/server versions, Buildx, Compose, daemon OS, daemon architecture, and storage driver;
- memory and CPU resources visible to the Docker VM;
- successful `linux/arm64` container execution;
- successful read-only bind mount of the repository;
- bridge-container, BuildKit, and `--network none` control results;
- host Apple Clang version for diagnostics only;
- an assertion that the build compiler is GCC 12 inside Linux;
- proxy variables and macOS proxy summary, with credentials redacted;
- Git, curl, gzip, Python, and `caffeinate` availability;
- outbound HTTPS to GitHub, NCBI, and the gnomAD GCS object from both macOS and Docker;
- current UTC timestamp.

Write output to:

```text
results/host_bootstrap.txt
results/docker_desktop_diagnostics.txt
results/preflight.txt
```

Recommended thresholds before the full build:

```text
Docker VM memory: >= 14 GiB
Docker VM CPUs: >= 8
Free macOS disk: >= 100 GiB
Primary platform: linux/arm64
```

A smoke build may proceed below the disk threshold when at least 60 GiB is free, but Codex must not start the 100,000-record scale phase without rechecking capacity.

Initialize a git repository before implementation and commit logical milestones. Never overwrite an unrelated existing repository.


## 9. Phase 1 — Docker build based on the supplied project

Start from the baseline Dockerfile's Ubuntu 22.04 multi-stage build and dependency set. The host is macOS/arm64, but Apple Clang, the macOS SDK, and Homebrew libraries must not leak into this build. Use the native `linux/arm64` platform and the pinned GCC 12 container toolchain defined in the MacBook bootstrap section.

Required changes:

1. Add build arguments:

```dockerfile
ARG NCBI_CXX_TOOLKIT_REF=203e594d7b4cad620d597a2bb8afef8e391e4eb8
ARG NCBI_CXX_TOOLKIT_REPO=https://github.com/ncbi/ncbi-cxx-toolkit-public.git
ARG GCC_MAJOR=12
```

2. Install `gcc-12` and `g++-12`, set `CC` and `CXX`, pass both compiler paths to CMake, and print the resolved compiler versions before configuration.
3. Clone, fetch, and checkout the exact revision. Print the resolved commit during build.
4. Copy the custom probe source and NCBIptb target file into `src/app/asn_cache/`.
5. Patch `src/app/asn_cache/CMakeLists.txt` to add `gks_ncbi_sequence_probe` to `NCBI_add_app(...)`.
6. Model the target file after the toolkit's ASN-cache applications:

```cmake
NCBI_begin_app(gks_ncbi_sequence_probe)
  NCBI_sources(gks_ncbi_sequence_probe)
  NCBI_uses_toolkit_libraries(
    ncbi_xloader_asn_cache
    ncbi_xloader_genbank
    xobjutil
  )
  NCBI_requires(BerkeleyDB)
NCBI_end_app()
```

If the target requires a different minimal toolkit library set, inspect the generated linker errors and existing toolkit targets, make the smallest justified change, and document it.

7. Build these targets:

```text
prime_cache
asn_cache_test
gks_ncbi_sequence_probe
asnvalidate
asn2asn
asn2fasta
asn2flat
asn_cleanup
annotwriter
```

8. Include runtime dependencies needed by:
   - the toolkit binaries,
   - Berkeley DB,
   - `bcftools`,
   - `tabix`,
   - `/usr/bin/time`,
   - `strace`,
   - Python 3 for orchestration and reports.

9. Preserve `/opt/ncbi/bin` on PATH and set `LD_LIBRARY_PATH=/opt/ncbi/lib`.
10. Add image build checks:
   - `prime_cache -h`
   - `asn_cache_test -h`
   - `gks_ncbi_sequence_probe -help`
   - `bcftools --version`
11. Emit an OCI label containing the toolkit commit.

Use named BuildKit caches for source and compilation artifacts where practical. Key caches by toolkit commit, base-image digest, target architecture, compiler major version, and build type.

Use bounded build parallelism:

```bash
NCBI_BUILD_JOBS="${NCBI_BUILD_JOBS:-8}"
cmake --build /scratch/build --parallel "$NCBI_BUILD_JOBS" --target ...
```

Do not optimize image size until the experiment is passing. Record native versus emulated architecture in every build and benchmark result.

---

## 10. Phase 2 — Implement `gks_ncbi_sequence_probe`

Use `CNcbiApplication` and the NCBI Object Manager APIs.

### CLI

Implement these arguments:

```text
-mode                  genbank | asn | hybrid
-asn-cache             path, required for asn/hybrid
-requests              TSV input path
-output                 JSONL output path, default stdout
-repeat                 integer, default 1
-warmup                 integer, default 0
-allow-remote           boolean flag
-print-sequence         boolean flag
-fail-on-mismatch       boolean flag
```

TSV input columns:

```text
request_id  accession  start  end  expected_ref
```

Coordinates are **0-based, half-open**. Reject negative starts, `end < start`, and malformed identifiers.

### Loader registration

Use explicit loader registration and explicit scope membership. Do not rely on ambient default loaders.

- `asn`:
  - register `CAsnCache_DataLoader` with priority 1;
  - add only that loader to the scope;
  - remote access must not be possible.

- `genbank`:
  - register `CGBDataLoader`;
  - add only the GenBank loader to the scope;
  - require `-allow-remote`.

- `hybrid`:
  - register ASN cache as priority 1;
  - register GenBank as priority 2 only when `-allow-remote` is set;
  - add only the selected loaders to the scope.

Follow the public toolkit examples for exact overloads and loader names.

### Sequence extraction

For each request:

1. Resolve the accession to a `CBioseq_Handle`.
2. Obtain sequence length.
3. Validate `end <= sequence_length`.
4. Extract the requested interval with `CSeqVector` using IUPAC coding.
5. Normalize the returned sequence and expected REF to uppercase.
6. Record whether they match.
7. Enumerate known sequence IDs/aliases when feasible without another full fetch.
8. Record elapsed microseconds.

Do not print complete chromosome sequences. `-print-sequence` may print only requested slices and should default off.

### JSONL result schema

Each line must contain at least:

```json
{
  "request_id": "v000001",
  "mode": "hybrid",
  "accession": "NC_000023.11",
  "start": 253592,
  "end": 253593,
  "length": 1,
  "expected_ref": "G",
  "observed_ref": "G",
  "match": true,
  "elapsed_us": 1234,
  "iteration": 1,
  "sequence_length": 156040895,
  "aliases": []
}
```

Errors must be structured JSONL records with `error_type` and `error_message`, followed by a nonzero process exit when `-fail-on-mismatch` is set or a retrieval error occurs.

### Same-process warm behavior

Keep one Object Manager and one scope alive for the full request file and all repeat iterations. This makes `-repeat 2` a same-process cold/warm comparison.

---

## 11. Phase 3 — Prepare a compact gnomAD VCF sample

Create `scripts/prepare_vcf.sh`.

Defaults:

```text
SOURCE=exomes
GNOMAD_CONTIG=chrX
GNOMAD_REGION=chrX:200000-1000000
MAX_VARIANTS=100000
```

Required behavior:

1. Preflight the VCF URL and remote index.
2. Read only the selected indexed region.
3. Split multiallelic records into one ALT per row.
4. Remove ID, QUAL, FILTER, INFO, and genotype/sample data not needed by this experiment.
5. Keep a valid VCF header and the standard fixed columns.
6. Write:
   - `work/gnomad.sample.minimal.vcf.bgz`
   - `work/gnomad.sample.minimal.vcf.bgz.tbi`
   - `work/requests.tsv`
7. Stop after `MAX_VARIANTS`.
8. Convert VCF POS to:
   - `start = POS - 1`
   - `end = start + length(REF)`
9. Skip and count:
   - symbolic alleles,
   - breakends,
   - malformed REF fields,
   - records outside the selected contig.
10. Write preparation statistics to `results/vcf_preparation.json`.

A suitable pipeline pattern is:

```bash
bcftools view -r "$GNOMAD_REGION" "$GNOMAD_URL" -Ou \
  | bcftools norm -m -any -Ou \
  | bcftools annotate -x ID,QUAL,FILTER,INFO -Oz -o "$OUTPUT"
```

Because truncating a BGZF stream with `head` can create an invalid file, enforce `MAX_VARIANTS` through a valid region, an intermediate BCF/VCF step, or a record-aware script. Always re-index and validate the final VCF with `bcftools view -h` and `bcftools index -n`.

---

## 12. Phase 4 — Seed and verify an ASN cache

Create `scripts/seed_asn_cache.sh`.

For the default chrX profile:

```bash
printf '%s\n' NC_000023.11 > work/seed_ids.txt
prime_cache \
  -ifmt ids \
  -i work/seed_ids.txt \
  -cache work/asn_cache \
  -oseq-ids work/asn_cache.loaded_ids.txt
```

For chr22, use `NC_000022.11`.

Requirements:

1. Run hydration with network enabled.
2. Record wall time, peak RSS, cache size, and output IDs.
3. Validate the cache with `asn_cache_test`.
4. Query at least three slices through `gks_ncbi_sequence_probe -mode asn`.
5. Start a new container with `--network none` and repeat the same queries.
6. Fail the ASN-cache acceptance test if the offline container cannot return identical slices.
7. Record all commands and logs.

Optional bulk hydration may use the bundled RefSeq path list. Prefer the GRCh38.p14 genomic FASTA entry:

```text
genomes/refseq/vertebrate_mammalian/Homo_sapiens/all_assembly_versions/GCF_000001405.40_GRCh38.p14/GCF_000001405.40_GRCh38.p14_genomic.fna.gz
```

Do not download that full assembly unless the direct accession experiment is complete and the report needs a comparison.

---

## 13. Phase 5 — Configure and test GenBank native disk caching

Create two configuration files.

### `config/genbank-remote.ini`

Configure a remote reader without a persistent local reader cache. Use deferred connection opening where supported.

### `config/genbank-bdb-cache.ini`

Configure the GenBank reader order as:

```ini
[genbank]
loader_method=cache;id2
preopen=false
```

Configure local Berkeley DB-backed ID and blob caches under a path supplied by the experiment, using the exact section and parameter names supported by the pinned toolkit revision.

Do not guess silently. Locate the pinned revision's sample configurations, generated help, or source defaults and include a comment in the file naming the source consulted.

Tests:

1. Empty BDB cache, network enabled, one slice.
2. Same process, repeated slice.
3. Same process, contained slice.
4. New process, same slice.
5. New process, contained slice.
6. New container, `--network none`, same slice.
7. New container, `--network none`, contained slice.
8. An uncached accession while offline; this must fail clearly.

Record whether the cache is actually persistent and sufficient for offline replay. If public ID2 connectivity or BDB cache configuration is unavailable, document the exact failure and continue with the ASN-cache path.

---

## 14. Phase 6 — Experiment matrix

Implement `scripts/run_experiment_matrix.sh` and `scripts/run_one_case.sh`.

Run at least these cases:

| Case | Loader/config | Process state | Network | Expected |
|---|---|---:|---:|---|
| `genbank_cold` | GenBank remote | new | on | success |
| `genbank_same_process_warm` | GenBank remote | repeated | on | success, faster |
| `genbank_bdb_cold` | `cache;id2`, empty disk cache | new | on | success |
| `genbank_bdb_new_process_warm` | `cache;id2`, populated cache | new | on | success |
| `genbank_bdb_offline` | local cache only/equivalent | new | off | success only if persistent cache works |
| `asn_offline` | ASN cache only | new | off | success |
| `hybrid_asn_hit` | ASN priority 1, GenBank priority 2 | new | on | ASN result |
| `hybrid_miss_remote` | ASN miss, GenBank fallback | new | on | success |
| `nested_same_process` | selected mode | same | on | second interval has no new connection |
| `vcf_10k` | ASN only | new | off | all eligible REF values match |
| `vcf_100k` | best passing mode | new | selected | all eligible REF values match |

For a contained-range test, use requests similar to:

```text
large   NC_000023.11  253000  254000
inside  NC_000023.11  253592  253600
```

Do not use only one-base requests for the cache semantics test.

---

## 15. Measurements

For every case, capture:

- toolkit commit;
- image digest;
- command;
- UTC start/end;
- exit code;
- request count;
- success/mismatch/error counts;
- wall-clock time;
- throughput;
- per-request p50, p95, p99, and max latency;
- peak RSS;
- cache size before and after;
- container RX/TX byte counters before and after;
- count of network-related syscalls or connection attempts when practical;
- first request latency;
- warm request latency;
- whether the run was network-disabled.

Store raw results under:

```text
results/raw/<case>/
```

Write normalized summary rows to:

```text
results/metrics.csv
```

Do not infer “no network” only from a fast run. Use `docker run --network none` for offline proof and network counters or `strace` for same-process nested-range evidence.

---

## 16. Correctness tests

Required automated tests:

1. Coordinate conversion:
   - VCF POS 1 maps to start 0.
   - end is start plus REF length.
2. Single nucleotide, insertion-anchor, and deletion-anchor REF slices.
3. Same request repeated returns identical sequence.
4. Contained request equals the corresponding substring of the larger request.
5. ASN-only offline result equals the network-hydrated result.
6. Alias list is stable across warm runs when aliases are available.
7. At least 10,000 eligible gnomAD records have 100% REF agreement.
8. The final 100,000-record run has 100% agreement, or every exclusion/mismatch is enumerated and investigated.
9. An uncached offline accession fails without silently enabling a remote loader.
10. Tests detect a deliberate off-by-one coordinate error.

---

## 17. Acceptance gates

### Gate H — MacBook and Docker Desktop

Pass when:

- the host is verified as macOS on Apple silicon (`arm64`);
- Docker Desktop for Apple silicon is installed, running, and using the local Linux context;
- the Docker daemon reports Linux on `arm64`/`aarch64`;
- Docker VM resources meet the recorded threshold or a smaller smoke-only exception is documented;
- a native `linux/arm64` container runs successfully;
- the repository can be bind-mounted read-only;
- bridge-container DNS/HTTPS succeeds;
- native-platform BuildKit apt/TLS/HTTPS succeeds;
- the `--network none` negative control fails as expected;
- no unreviewed macOS network, proxy, CA, virtualization, or Docker Desktop settings were changed;
- `results/host_bootstrap.txt`, `results/docker_desktop_diagnostics.txt`, and `results/preflight.txt` exist.


### Gate A — Build

Pass when:

- image builds from the pinned sources;
- required binaries run;
- the toolkit revision is recorded;
- a clean rebuild succeeds.

### Gate B — ASN cache

Pass when:

- `prime_cache -ifmt ids` hydrates the selected chromosome accession;
- the new probe returns correct slices;
- a new `--network none` container returns the same slices;
- 10,000 VCF REF checks pass.

### Gate C — Lazy GenBank reader cache

Pass when:

- an empty cache can fetch the record remotely;
- a new process can reuse it;
- a network-disabled process can reuse it;
- an uncached record still fails offline;
- nested contained ranges require no additional remote access after the initial record fetch.

This gate may legitimately fail. A failed gate is an experimental result, not a reason to fabricate a workaround.

### Gate D — Scale

Pass when:

- 100,000 eligible records validate;
- latency and memory metrics are complete;
- cache growth and initial hydration costs are reported.

---

## 18. Decision rules

End the report with exactly one recommendation.

### `ADOPT_FOR_FOLLOW_ON_PROTOTYPE`

Use when:

- ASN cache is correct and offline-capable;
- operational cost is acceptable;
- the integration boundary can be kept stable;
- results justify building a VRS sequence/alias adapter.

### `ADOPT_PRESEEDED_ASN_CACHE_ONLY`

Use when:

- pre-seeded ASN cache works well;
- GenBank lazy disk caching fails or is operationally unsuitable;
- deterministic hydration is still valuable for deployment.

### `CONTINUE_RESEARCH_WITH_CONSTRAINTS`

Use when:

- correctness passes but performance, cache size, public service access, or integration complexity needs another focused experiment.

### `REJECT_FOR_GKS_BACKEND`

Use when:

- offline correctness cannot be achieved;
- cache behavior does not meet the ticket;
- whole-record fetching is prohibitively expensive;
- build/runtime complexity clearly outweighs the benefits.

Compare the conclusion with the issue's existing SeqRepo and RefGetStore direction, but do not rerun unrelated systems unless a local benchmark is already available.

---

## 19. Required final artifacts

Codex must leave:

```text
README.md
AGENTS.md
MACBOOK_SETUP.md
SIDEBAR_PROMPT.md
Dockerfile
Makefile
src/gks_ncbi_sequence_probe.cpp
config/genbank-remote.ini
config/genbank-bdb-cache.ini
scripts/prepare_host_macos.sh
scripts/diagnose_docker_desktop.sh
scripts/*
tests/*
results/host_bootstrap.txt
results/docker_desktop_diagnostics.txt
results/preflight.txt
results/vcf_preparation.json
results/metrics.csv
results/report.md
results/raw/*
```

`results/report.md` must contain:

1. Executive recommendation.
2. Environment and source revisions.
3. Host architecture, container platform, and whether any result used emulation.
4. Docker Desktop resources used.
5. Data profile used.
6. Correctness results.
7. Benchmark table.
8. Cache and network evidence.
9. chrX/chr22 clarification.
10. GenBank reader-cache result.
11. ASN-cache result.
12. Operational risks.
13. Reproducible commands.
14. Follow-on work, limited to five concrete items.


## 20. Stop conditions and handling failures

- If Docker Desktop is absent, stopped, or still starting, stop and ask the user to install/start it. Do not silently install software or accept license prompts.
- If the Docker context points to an unrelated remote engine, stop before creating images or caches and ask the user which engine to use.
- If Docker VM resources are below the recommended threshold, allow only a minimal smoke build and ask before increasing Docker Desktop resources.
- If a bind mount fails, move the repository under `$HOME` or ask the user to approve a Docker Desktop file-sharing change.
- If container egress fails, run `scripts/diagnose_docker_desktop.sh`; do not disable TLS verification or alter macOS networking without approval.
- If the native ARM build fails, preserve all logs and diagnose dependencies, target linkage, memory, and source errors before considering Intel emulation.
- Do not enable Rosetta or switch Docker Desktop virtualization settings without approval.
- If an amd64 fallback is used, mark its performance measurements non-representative and use it only for functional conclusions.
- If the NCBI build fails, preserve compiler/configure/link logs and verify the pinned in-container compiler before changing toolkit revisions.
- If the pinned toolkit does not build, capture the error, identify the smallest compatible revision change, and retry once.
- If public GenBank/ID2 access fails, verify container DNS/TLS and toolkit configuration. Then record the limitation and continue with FASTA-based or pre-seeded ASN-cache tests.
- If the gnomAD remote index is unavailable, do not download the full object automatically. Record the failed preflight and use a user-provided chunk only as a fallback.
- If chromosome hydration is too expensive for the first run, hydrate a small RefSeq transcript to prove the mechanism, then retry the chromosome with bounded resources.
- If macOS memory pressure becomes high or the laptop begins swapping heavily, stop the build, reduce parallelism, and retry before increasing Docker memory.
- If a requirement cannot be completed, leave a clearly labeled incomplete result and the exact command/output. Do not mark the gate passed.


## 21. Source references

- GKS issue 59: https://github.com/ga4gh/gks-portal/issues/59
- Docker baseline: https://github.com/egchristensen/ncbi_cxx_toolkit_installation_docker
- NCBI toolkit: https://github.com/ncbi/ncbi-cxx-toolkit-public
- Object Manager data loaders: https://ncbi.github.io/cxx-toolkit/pages/ch_objmgr_dtld
- CMake integration: https://ncbi.github.io/cxx-toolkit/pages/ch_cmconfig
- ASN cache loader source: https://www.ncbi.nlm.nih.gov/IEB/ToolBox/CPP_DOC/lxr/source/src/objtools/data_loaders/asn_cache/asn_cache_loader.cpp
- `prime_cache` source: https://github.com/ncbi/ncbi-cxx-toolkit-public/blob/main/src/app/asn_cache/prime_cache.cpp
- gnomAD stripping example: https://github.com/theferrit32/gnomad-gks/blob/main/deployment/cloudrun/entrypoint.sh
- Supplied gnomAD chrX object: https://storage.googleapis.com/gcp-public-data--gnomad/release/4.1/vcf/exomes/gnomad.exomes.v4.1.sites.chrX.vcf.bgz

- Docker Desktop for Mac installation: https://docs.docker.com/desktop/setup/install/mac-install/
- Docker Desktop Mac permission model: https://docs.docker.com/desktop/setup/install/mac-permission-requirements/
- Docker Desktop settings and Apple-silicon emulation: https://docs.docker.com/desktop/settings-and-maintenance/settings/
- Docker Desktop troubleshooting and file sharing: https://docs.docker.com/desktop/troubleshoot-and-support/troubleshoot/topics/
- Codex IDE extension overview: https://help.openai.com/en/articles/11369540-using-codex-with-your-chat

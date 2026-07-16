# MacBook setup for the NCBI-native GKS experiment

## Target

- Apple-silicon MacBook Pro
- M4 Max
- 32 GB unified memory
- 2 TB SSD
- Local VS Code with the Codex extension
- Docker Desktop for Mac
- Primary container platform: `linux/arm64`

The NCBI C++ Toolkit is compiled inside Ubuntu Linux containers. Apple Clang and the macOS SDK are not used for the primary build.

## 1. Put the repository under your home directory

A suitable location is:

```bash
mkdir -p ~/Projects
cd ~/Projects
unzip /path/to/ncbi_native_gks_codex_macbook_bundle.zip
cd ncbi_native_gks_codex_macbook_bundle
```

Keeping the repository under `$HOME` avoids most Docker Desktop file-sharing problems.

## 2. Install and start Docker Desktop

Install the current **Apple silicon** Docker Desktop release from Docker's official Mac installation page. Complete its first-launch setup and wait until Docker Desktop reports that the engine is running.

Codex must not install Docker Desktop or accept its license without your participation.

Verify in Terminal:

```bash
docker context show
docker version
docker info
docker buildx version
docker compose version
docker run --rm hello-world
```

The active context is normally `desktop-linux`, and the server should report Linux on `arm64`/`aarch64`.

## 3. Allocate Docker Desktop resources

Open:

```text
Docker Desktop → Settings → Resources
```

Recommended starting values for a 32 GB M4 Max:

```text
Memory: 16 GB
CPUs: 10
Swap: 2–4 GB, when configurable
Docker disk image maximum: at least 200 GB
```

Do not allocate all host memory or CPU cores. If the native build is killed for lack of memory, raise memory to 20 GB after preserving the failure log.

## 4. Native ARM first

The plan builds:

```text
linux/arm64
```

Do not enable Intel emulation preemptively. A `linux/amd64` image is a controlled fallback only after a documented architecture-specific native failure.

When the fallback is genuinely required, Docker Desktop may offer Rosetta acceleration under its virtualization settings. Ask before installing Rosetta 2 or changing those settings.

## 5. Keep the laptop awake

Connect the laptop to power. Long commands may be run with:

```bash
caffeinate -dimsu -- <command>
```

## 6. Validate the host

From the repository root:

```bash
bash scripts/prepare_host_macos.sh
bash scripts/diagnose_docker_desktop.sh
```

Review:

```text
results/host_bootstrap.txt
results/docker_desktop_diagnostics.txt
```

Do not begin the full NCBI build until the scripts confirm:

- native `linux/arm64` container execution;
- Docker VM memory of at least 14 GiB;
- at least 8 Docker CPUs;
- repository file sharing;
- bridge-container HTTPS;
- BuildKit HTTPS;
- an expected failure under `--network none`.

## 7. Use Codex in VS Code

Open this directory as a local VS Code workspace. Do not use Remote-SSH for this run.

Open `SIDEBAR_PROMPT.md`, copy its contents, and paste them into the Codex sidebar.

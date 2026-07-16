# Run with the Codex VS Code extension on the MacBook

## 1. Open locally

Place the extracted directory under your home folder, for example:

```bash
mkdir -p ~/Projects
cd ~/Projects
unzip /path/to/ncbi_native_gks_codex_macbook_bundle.zip
cd ncbi_native_gks_codex_macbook_bundle
git init
git add .
git commit -m "Add MacBook NCBI-native GKS execution plan"
code .
```

Open this directory in a normal local VS Code window. Do not connect through Remote-SSH.

## 2. Prepare Docker Desktop

Follow `MACBOOK_SETUP.md`.

Run:

```bash
bash scripts/prepare_host_macos.sh
bash scripts/diagnose_docker_desktop.sh
```

Resolve any failing Docker Desktop or resource check before starting the full build.

## 3. Start Codex

Open `SIDEBAR_PROMPT.md`, copy the entire file, and paste it into the Codex sidebar.

The sidebar prompt directs Codex to read the full plan, verify native ARM Docker behavior, and begin implementation.

## 4. During long builds

Keep the MacBook connected to power. Codex may use:

```bash
caffeinate -dimsu -- docker buildx build ...
```

The primary build must remain `linux/arm64`.

## 5. Completion checks

```bash
test -s results/host_bootstrap.txt
test -s results/docker_desktop_diagnostics.txt
test -s results/preflight.txt
test -s results/report.md
test -s results/metrics.csv
git status --short
sed -n '1,260p' results/report.md
```

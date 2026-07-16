# Research notes used to prepare the MacBook plan

Prepared 2026-07-16.

## Experiment sources

- GKS issue 59 asks for transparent reuse where a cached larger interval can satisfy a later contained request.
- The supplied Docker baseline builds `prime_cache`, ASN converters, and `annotwriter`.
- `prime_cache -ifmt ids` retrieves records through the GenBank loader and writes a local ASN cache.
- `CAsnCache_DataLoader` provides the local Object Manager loader path.
- The gnomAD example strips ID, INFO, and FILTER with bcftools.
- The supplied RefSeq path list contains GRCh38 and T2T-CHM13 resources.

## MacBook revision

- Docker Desktop is the supported Docker environment on macOS; the standalone macOS Docker CLI does not provide a Linux runtime.
- Docker Desktop supplies a Linux VM and supports Apple-silicon images.
- The plan uses native `linux/arm64` as the primary target.
- Rosetta is optional and reserved for an approved `linux/amd64` fallback.
- The project remains under the user's home directory to minimize Docker Desktop file-sharing issues.
- Docker VM resources are bounded to leave capacity for macOS and VS Code.
- Codex is used locally through the VS Code extension.

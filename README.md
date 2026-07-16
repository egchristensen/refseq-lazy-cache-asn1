# NCBI-native GKS sequence experiment

This bundle adapts the NCBI-native GKS experiment to an Apple-silicon MacBook.

The default data profile intentionally follows the supplied gnomAD object:
`chrX`, `NC_000023.11`. The ticket text also mentioned chr22, so a selectable
chr22/`NC_000022.11` profile is documented in `PLAN.md`; it was not silently
substituted for the supplied chrX input.

Reproduce the native ARM workflow:

1. Read `MACBOOK_SETUP.md`.
2. Run `scripts/prepare_host_macos.sh`.
3. Run `make build smoke test`.
4. Run `scripts/prepare_vcf.sh` and `scripts/seed_asn_cache.sh`.
5. Run `scripts/run_experiment_matrix.sh`.

Primary platform: `linux/arm64`.

The `linux/amd64` path is an approved fallback only and must not be used for representative performance conclusions.

Generated VCF slices, caches, and raw logs stay under `work/` and `results/`.
The VCF preparation reads indexed regions remotely and never downloads the
complete chromosome object. See `results/report.md` for the measured scope and
the claims supported by cold, warm-new-process, and `--network none` controls.

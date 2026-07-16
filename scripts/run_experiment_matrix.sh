#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
sed -n '1,10001p' work/requests.tsv > work/requests.10k.tsv

NETWORK=on scripts/run_one_case.sh genbank_cold genbank work/one_request.tsv -allow-remote -conffile config/genbank-remote.ini
NETWORK=on scripts/run_one_case.sh genbank_same_process_warm genbank work/one_request.tsv -allow-remote -conffile config/genbank-remote.ini -repeat 2
NETWORK=off scripts/run_one_case.sh asn_offline asn work/one_request.tsv
NETWORK=on scripts/run_one_case.sh hybrid_asn_hit hybrid work/one_request.tsv -allow-remote
NETWORK=off scripts/run_one_case.sh vcf_10k asn work/requests.10k.tsv

# The BDB cache is deliberately prepared separately so cold and warm evidence
# cannot be confused by an old environment.
NETWORK=on scripts/run_one_case.sh genbank_bdb_new_process_warm genbank work/one_request.tsv -allow-remote -conffile work/genbank-bdb3.ini
NETWORK=off scripts/run_one_case.sh genbank_bdb_offline genbank work/one_request.tsv -allow-remote -conffile work/genbank-bdb3.ini

python3 scripts/summarize_results.py

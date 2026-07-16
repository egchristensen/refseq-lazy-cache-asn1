#!/usr/bin/env python3
"""Convert minimal VCF records to probe TSV requests."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

DNA_RE = re.compile(r"^[ACGTN]+$", re.IGNORECASE)


def coordinates(pos: int, ref: str) -> tuple[int, int]:
    if pos < 1:
        raise ValueError("VCF POS must be at least 1")
    if not ref or not DNA_RE.fullmatch(ref):
        raise ValueError("REF must contain only A, C, G, T, or N")
    start = pos - 1
    return start, start + len(ref)


def convert(lines, output, accession: str, contig: str) -> dict[str, int]:
    stats = {"eligible": 0, "symbolic_or_breakend": 0, "malformed_ref": 0,
             "wrong_contig": 0, "malformed_record": 0}
    output.write("request_id\taccession\tstart\tend\texpected_ref\n")
    for raw in lines:
        if not raw or raw.startswith("#"):
            continue
        fields = raw.rstrip("\n").split("\t")
        if len(fields) < 5:
            stats["malformed_record"] += 1
            continue
        chrom, pos_text, _ident, ref, alt = fields[:5]
        if chrom != contig:
            stats["wrong_contig"] += 1
            continue
        if any(token in alt for token in ("<", ">", "[", "]", "*")):
            stats["symbolic_or_breakend"] += 1
            continue
        try:
            start, end = coordinates(int(pos_text), ref)
        except (ValueError, TypeError):
            stats["malformed_ref"] += 1
            continue
        stats["eligible"] += 1
        output.write(f"v{stats['eligible']:06d}\t{accession}\t{start}\t{end}\t{ref.upper()}\n")
    return stats


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--accession", required=True)
    parser.add_argument("--contig", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--stats", type=Path, required=True)
    args = parser.parse_args()
    with args.output.open("w") as output:
        stats = convert(sys.stdin, output, args.accession, args.contig)
    args.stats.write_text(json.dumps(stats, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

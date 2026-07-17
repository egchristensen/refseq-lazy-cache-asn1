#!/usr/bin/env python3
"""Range retrieval and guarded complete-record promotion into SeqRepo."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import Iterable


ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSIONED_REFSEQ = re.compile(r"^[A-Z]{2}_[0-9]+\.[0-9]+$")
SEQUENCE_ALPHABET = re.compile(r"^[A-Z*.-]*$")


class BridgeError(RuntimeError):
    pass


def validate_accession(accession: str) -> str:
    if not VERSIONED_REFSEQ.fullmatch(accession):
        raise BridgeError("a versioned RefSeq accession such as NC_000023.11 is required")
    return accession


def validate_interval(start: int, end: int) -> None:
    if start < 0 or end < start:
        raise BridgeError("coordinates must be a non-negative 0-based half-open interval")


def validate_complete_sequence(sequence: str, expected_length: int) -> str:
    sequence = sequence.upper()
    if len(sequence) != expected_length:
        raise BridgeError(
            f"complete sequence length mismatch: got {len(sequence)}, expected {expected_length}"
        )
    if not SEQUENCE_ALPHABET.fullmatch(sequence):
        raise BridgeError("complete sequence contains characters outside the supported alphabet")
    return sequence


def seqrepo_aliases(accession: str, ncbi_aliases: Iterable[str]) -> list[dict[str, str]]:
    aliases = {("refseq", accession)}
    for value in ncbi_aliases:
        fields = value.split("|")
        if len(fields) >= 2 and fields[0] == "ref" and fields[1]:
            aliases.add(("refseq", fields[1]))
        elif len(fields) >= 2 and fields[0] in {"gi", "gpp"} and fields[1]:
            aliases.add((fields[0], fields[1]))
    return [
        {"namespace": namespace, "alias": alias}
        for namespace, alias in sorted(aliases)
    ]


@dataclass(frozen=True)
class ProbeRequest:
    request_id: str
    accession: str
    start: int
    end: int


class DockerProbe:
    def __init__(self, image: str, mode: str, asn_cache: str, allow_remote: bool):
        self.image = image
        self.mode = mode
        self.asn_cache = asn_cache
        self.allow_remote = allow_remote

    def run(self, requests: list[ProbeRequest]) -> list[dict]:
        work = ROOT / "work"
        work.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="seqrepo-bridge-", dir=work) as tmp:
            tmp_path = pathlib.Path(tmp)
            request_path = tmp_path / "requests.tsv"
            output_path = tmp_path / "results.jsonl"
            with request_path.open("w") as stream:
                stream.write("request_id\taccession\tstart\tend\texpected_ref\n")
                for request in requests:
                    stream.write(
                        f"{request.request_id}\t{request.accession}\t"
                        f"{request.start}\t{request.end}\t\n"
                    )
            request_rel = request_path.relative_to(ROOT)
            output_rel = output_path.relative_to(ROOT)
            command = [
                "docker", "run", "--rm", "--platform", "linux/arm64",
            ]
            if self.mode == "asn" and not self.allow_remote:
                command.extend(["--network", "none"])
            command.extend([
                "-v", f"{ROOT}:/workspace", "-w", "/workspace", self.image,
                "gks_ncbi_sequence_probe", "-mode", self.mode,
                "-requests", str(request_rel), "-output", str(output_rel),
            ])
            if self.mode in {"asn", "hybrid"}:
                command.extend(["-asn-cache", self.asn_cache])
            if self.allow_remote:
                command.append("-allow-remote")
            process = subprocess.run(command, text=True, capture_output=True)
            if process.returncode != 0:
                detail = process.stderr.strip() or process.stdout.strip()
                raise BridgeError(f"NCBI probe failed ({process.returncode}): {detail}")
            records = [json.loads(line) for line in output_path.read_text().splitlines()]
        if len(records) != len(requests):
            raise BridgeError(f"NCBI probe returned {len(records)} records for {len(requests)} requests")
        errors = [record for record in records if "error_type" in record]
        if errors:
            raise BridgeError(errors[0].get("error_message", "NCBI retrieval failed"))
        return records


def open_seqrepo(root: str, writeable: bool = False):
    try:
        from biocommons.seqrepo import SeqRepo
    except ImportError as error:
        raise BridgeError(
            "biocommons.seqrepo is required for SeqRepo access; install it in an isolated adapter environment"
        ) from error
    return SeqRepo(root, writeable=writeable)


def fetch_seqrepo(repo, accession: str, start: int, end: int) -> tuple[str, str] | None:
    for namespace in ("refseq", "NCBI", None):
        try:
            sequence = repo.fetch(
                alias=accession, namespace=namespace, start=start, end=end
            )
            return sequence, namespace or "unqualified"
        except (KeyError, LookupError, ValueError):
            continue
    return None


def fetch_command(args, probe: DockerProbe) -> dict:
    accession = validate_accession(args.accession)
    validate_interval(args.start, args.end)
    if args.seqrepo_root:
        repo = open_seqrepo(args.seqrepo_root)
        try:
            hit = fetch_seqrepo(repo, accession, args.start, args.end)
        finally:
            repo.close()
        if hit is not None:
            sequence, namespace = hit
            return {
                "accession": accession, "start": args.start, "end": args.end,
                "sequence": sequence, "source": "seqrepo", "namespace": namespace,
            }
    record = probe.run([ProbeRequest("fetch", accession, args.start, args.end)])[0]
    return {
        "accession": accession, "start": args.start, "end": args.end,
        "sequence": record["observed_ref"], "source": f"ncbi-{args.mode}",
        "sequence_length": record["sequence_length"], "aliases": record["aliases"],
    }


def retrieve_complete(probe: DockerProbe, accession: str, chunk_size: int):
    metadata = probe.run([ProbeRequest("metadata", accession, 0, 0)])[0]
    length = metadata["sequence_length"]
    requests = [
        ProbeRequest(f"chunk-{start:012d}", accession, start, min(start + chunk_size, length))
        for start in range(0, length, chunk_size)
    ]
    records = probe.run(requests)
    for request, record in zip(requests, records):
        if record["start"] != request.start or record["end"] != request.end:
            raise BridgeError("probe returned chunks out of order")
    sequence = validate_complete_sequence(
        "".join(record["observed_ref"] for record in records), length
    )
    return sequence, metadata


def promote_command(args, probe: DockerProbe) -> dict:
    accession = validate_accession(args.accession)
    if args.chunk_size < 1:
        raise BridgeError("chunk size must be positive")
    sequence, metadata = retrieve_complete(probe, accession, args.chunk_size)
    aliases = seqrepo_aliases(accession, metadata.get("aliases", []))
    manifest = {
        "accession": accession, "length": len(sequence), "aliases": aliases,
        "source": f"ncbi-{args.mode}", "seqrepo_root": args.seqrepo_root,
        "committed": False,
    }
    if args.fasta_output:
        path = pathlib.Path(args.fasta_output)
        with path.open("w") as stream:
            stream.write(f">refseq:{accession}\n")
            for start in range(0, len(sequence), 80):
                stream.write(sequence[start:start + 80] + "\n")
    if not args.write:
        return manifest
    if not args.seqrepo_root:
        raise BridgeError("--seqrepo-root is required with --write")
    repo = open_seqrepo(args.seqrepo_root, writeable=True)
    try:
        existing = fetch_seqrepo(repo, accession, 0, len(sequence))
        if existing is not None and existing[0].upper() != sequence:
            raise BridgeError("existing SeqRepo alias resolves to a different complete sequence")
        added_sequences, added_aliases = repo.store(sequence, aliases)
        repo.commit()
        stored = fetch_seqrepo(repo, accession, 0, len(sequence))
        if stored is None or stored[0].upper() != sequence:
            raise BridgeError("post-commit SeqRepo verification failed")
    finally:
        repo.close()
    manifest.update({
        "committed": True, "sequences_added": added_sequences,
        "aliases_added": added_aliases,
    })
    return manifest


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--image", default="gks-ncbi:arm64")
    result.add_argument("--mode", choices=("asn", "genbank", "hybrid"), default="asn")
    result.add_argument("--asn-cache", default="work/asn_cache_full")
    result.add_argument("--allow-remote", action="store_true")
    sub = result.add_subparsers(dest="command", required=True)
    fetch = sub.add_parser("fetch", help="fetch one 0-based half-open range")
    fetch.add_argument("accession")
    fetch.add_argument("start", type=int)
    fetch.add_argument("end", type=int)
    fetch.add_argument("--seqrepo-root")
    promote = sub.add_parser("promote", help="materialize and optionally store a complete record")
    promote.add_argument("accession")
    promote.add_argument("--seqrepo-root")
    promote.add_argument("--chunk-size", type=int, default=1_000_000)
    promote.add_argument("--fasta-output")
    promote.add_argument("--write", action="store_true", help="commit to a writable SeqRepo")
    return result


def main(argv=None) -> int:
    args = parser().parse_args(argv)
    if args.mode == "genbank" and not args.allow_remote:
        raise BridgeError("genbank mode requires --allow-remote")
    probe = DockerProbe(args.image, args.mode, args.asn_cache, args.allow_remote)
    output = fetch_command(args, probe) if args.command == "fetch" else promote_command(args, probe)
    print(json.dumps(output, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BridgeError as error:
        print(json.dumps({"error_type": "bridge_error", "error_message": str(error)}), file=sys.stderr)
        raise SystemExit(1)

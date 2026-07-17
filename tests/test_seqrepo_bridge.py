import importlib.util
import pathlib
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "seqrepo_bridge", ROOT / "scripts" / "seqrepo_bridge.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class FakeRepo:
    def __init__(self, values):
        self.values = values

    def fetch(self, alias, namespace, start, end):
        key = (namespace, alias)
        if key not in self.values:
            raise KeyError(key)
        return self.values[key][start:end]


class FakeProbe:
    def run(self, requests):
        if requests[0].request_id == "metadata":
            return [{"sequence_length": 8, "aliases": ["ref|NC_000023.11|", "gi|1"]}]
        sequence = "AACCGGTT"
        return [
            {"start": request.start, "end": request.end,
             "observed_ref": sequence[request.start:request.end]}
            for request in requests
        ]


class BridgeTests(unittest.TestCase):
    def test_requires_versioned_refseq_accession(self):
        self.assertEqual(MODULE.validate_accession("NC_000023.11"), "NC_000023.11")
        with self.assertRaises(MODULE.BridgeError):
            MODULE.validate_accession("NC_000023")

    def test_rejects_invalid_interval(self):
        with self.assertRaises(MODULE.BridgeError):
            MODULE.validate_interval(-1, 2)
        with self.assertRaises(MODULE.BridgeError):
            MODULE.validate_interval(3, 2)

    def test_seqrepo_namespace_fallback_and_slice(self):
        repo = FakeRepo({("NCBI", "NC_000023.11"): "AACCGGTT"})
        self.assertEqual(
            MODULE.fetch_seqrepo(repo, "NC_000023.11", 2, 6), ("CCGG", "NCBI")
        )

    def test_aliases_do_not_assign_region_to_full_accession(self):
        aliases = MODULE.seqrepo_aliases(
            "NC_000023.11", ["ref|NC_000023.11|", "gi|568815575", "gnl|NCBI_GENOMES|23"]
        )
        self.assertIn({"namespace": "refseq", "alias": "NC_000023.11"}, aliases)
        self.assertIn({"namespace": "gi", "alias": "568815575"}, aliases)
        self.assertNotIn({"namespace": "refseq-region", "alias": "NC_000023.11"}, aliases)

    def test_complete_sequence_length_is_mandatory(self):
        self.assertEqual(MODULE.validate_complete_sequence("acgt", 4), "ACGT")
        with self.assertRaises(MODULE.BridgeError):
            MODULE.validate_complete_sequence("ACG", 4)

    def test_complete_record_is_reassembled_in_order(self):
        sequence, metadata = MODULE.retrieve_complete(FakeProbe(), "NC_000023.11", 3)
        self.assertEqual(sequence, "AACCGGTT")
        self.assertEqual(metadata["sequence_length"], 8)


if __name__ == "__main__":
    unittest.main()

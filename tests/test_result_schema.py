import json
import unittest

REQUIRED = {
    "request_id", "mode", "accession", "start", "end", "length",
    "expected_ref", "observed_ref", "match", "elapsed_us", "iteration",
    "sequence_length", "aliases",
}


class ResultSchemaTests(unittest.TestCase):
    def test_example_success_record(self):
        record = json.loads(
            '{"request_id":"v000001","mode":"asn","accession":"NC_000023.11",'
            '"start":0,"end":1,"length":1,"expected_ref":"N","observed_ref":"N",'
            '"match":true,"elapsed_us":1,"iteration":1,"sequence_length":156040895,'
            '"aliases":[]}'
        )
        self.assertFalse(REQUIRED - record.keys())
        self.assertEqual(record["end"] - record["start"], record["length"])

    def test_error_record_is_structured(self):
        record = {"request_id": "bad", "error_type": "retrieval_error", "error_message": "miss"}
        self.assertIn("error_type", record)
        self.assertIn("error_message", record)


if __name__ == "__main__":
    unittest.main()

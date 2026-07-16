import importlib.util
import io
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "vcf_to_requests", ROOT / "scripts" / "vcf_to_requests.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CoordinateConversionTests(unittest.TestCase):
    def test_position_one_maps_to_zero(self):
        self.assertEqual(MODULE.coordinates(1, "A"), (0, 1))

    def test_insertion_anchor(self):
        self.assertEqual(MODULE.coordinates(10, "A"), (9, 10))

    def test_deletion_anchor(self):
        self.assertEqual(MODULE.coordinates(10, "ACG"), (9, 12))

    def test_deliberate_off_by_one_is_detected(self):
        start, _ = MODULE.coordinates(253593, "G")
        self.assertNotEqual(start, 253593)
        self.assertEqual(start, 253592)

    def test_invalid_ref_rejected(self):
        with self.assertRaises(ValueError):
            MODULE.coordinates(1, "<DEL>")

    def test_converter_counts_exclusions(self):
        source = ["chrX\t1\t.\tA\tC\t.\t.\t.\n", "chrX\t2\t.\tA\t<DEL>\t.\t.\t.\n"]
        output = io.StringIO()
        stats = MODULE.convert(source, output, "NC_000023.11", "chrX")
        self.assertEqual(stats["eligible"], 1)
        self.assertEqual(stats["symbolic_or_breakend"], 1)
        self.assertIn("v000001\tNC_000023.11\t0\t1\tA", output.getvalue())


if __name__ == "__main__":
    unittest.main()

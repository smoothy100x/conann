from __future__ import annotations

import sys
import unittest


class ImportBehaviorTest(unittest.TestCase):
    def test_import_conann_without_faiss_alias(self) -> None:
        sys.modules.pop("faiss", None)

        import conann

        self.assertEqual(conann.__version__, "0.1.1")
        self.assertEqual(conann.__faiss_version__, "1.9.0")
        self.assertTrue(hasattr(conann, "IndexFlatL2"))
        self.assertTrue(hasattr(conann, "IndexIVFFlat"))
        self.assertTrue(hasattr(conann, "METRIC_L2"))
        self.assertNotIn("faiss", sys.modules)

    def test_ivf_has_conann_methods(self) -> None:
        import conann

        quantizer = conann.IndexFlatL2(8)
        index = conann.IndexIVFFlat(quantizer, 8, 4, conann.METRIC_L2)

        self.assertTrue(hasattr(index, "calibrate_conann"))
        self.assertTrue(hasattr(index, "search_conann"))
        self.assertTrue(hasattr(index, "conann_time_report"))
        self.assertTrue(hasattr(index, "evaluate_conann"))


if __name__ == "__main__":
    unittest.main()


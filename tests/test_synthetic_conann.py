from __future__ import annotations

import unittest

import numpy as np


class SyntheticConannTest(unittest.TestCase):
    def test_standard_and_conann_ivf_search(self) -> None:
        import conann

        conann.omp_set_num_threads(1)

        rng = np.random.default_rng(123)
        d = 16
        nlist = 8
        k = 4
        nb = 800
        nt = 400
        nq_cal = 40
        nq_test = 20

        xb = rng.random((nb, d), dtype=np.float32)
        xt = rng.random((nt, d), dtype=np.float32)
        xq_cal = rng.random((nq_cal, d), dtype=np.float32)
        xq_test = rng.random((nq_test, d), dtype=np.float32)

        flat = conann.IndexFlatL2(d)
        flat.add(xb)
        _, gt_cal = flat.search(xq_cal, k)
        _, gt_test = flat.search(xq_test, k)

        quantizer = conann.IndexFlatL2(d)
        index = conann.IndexIVFFlat(quantizer, d, nlist, conann.METRIC_L2)
        index.train(xt)
        index.add(xb)
        index.nprobe = 2

        distances, labels = index.search(xq_test, k)
        self.assertEqual(distances.shape, (nq_test, k))
        self.assertEqual(labels.shape, (nq_test, k))
        self.assertEqual(index.ntotal, nb)
        self.assertEqual(index.nlist, nlist)
        self.assertEqual(index.nprobe, 2)

        calibration = index.calibrate_conann(
            alpha=0.3,
            k=k,
            xq=xq_cal,
            ground_truth=gt_cal,
            calib_sz=0.5,
            tune_sz=0.5,
            dataset_key="synthetic-package-test",
        )
        self.assertIn("params", calibration)
        self.assertIn("lamhat", calibration)

        conann_distances, conann_labels = index.search_conann(
            xq_test, calibration, k=k)
        self.assertEqual(conann_distances.shape, (nq_test, k))
        self.assertEqual(conann_labels.shape, (nq_test, k))
        self.assertTrue(np.isfinite(conann_distances).all())

        metrics = index.evaluate_conann(conann_labels, gt_test)
        self.assertIn("fnr", metrics)
        self.assertGreaterEqual(metrics["fnr"], 0.0)
        self.assertLessEqual(metrics["fnr"], 1.0)
        self.assertIsInstance(index.conann_time_report(), dict)


if __name__ == "__main__":
    unittest.main()


from __future__ import annotations

import numpy as np
import conann


def recall_at_k(labels: np.ndarray, ground_truth: np.ndarray) -> float:
    hits = 0
    for got, expected in zip(labels, ground_truth):
        expected_set = set(int(x) for x in expected)
        hits += sum(1 for x in got if int(x) in expected_set)
    return hits / float(labels.size)


def main() -> None:
    conann.omp_set_num_threads(1)

    rng = np.random.default_rng(23)
    d, nb, nt, nq, nlist, k = 32, 6000, 2500, 240, 64, 10

    xb = rng.random((nb, d), dtype=np.float32)
    xt = rng.random((nt, d), dtype=np.float32)
    xq = rng.random((nq, d), dtype=np.float32)

    xq_cal = xq[:160]
    xq_test = xq[160:]

    exact = conann.IndexFlatL2(d)
    exact.add(xb)
    _, gt_cal = exact.search(xq_cal, k)
    _, gt_test = exact.search(xq_test, k)

    quantizer = conann.IndexFlatL2(d)
    index = conann.IndexIVFFlat(quantizer, d, nlist, conann.METRIC_L2)
    index.train(xt)
    index.add(xb)

    index.nprobe = 8
    _, baseline_labels = index.search(xq_test, k)
    baseline_recall = recall_at_k(baseline_labels, gt_test)

    calibration = index.calibrate_conann(
        alpha=0.2,
        k=k,
        xq=xq_cal,
        ground_truth=gt_cal,
        calib_sz=0.5,
        tune_sz=0.25,
        dataset_key="full-example",
    )

    distances, labels = index.search_conann(xq_test, calibration, k=k)
    metrics = index.evaluate_conann(labels, gt_test)
    timing = index.conann_time_report()

    print("baseline recall@k:", round(baseline_recall, 4))
    print("conann labels shape:", labels.shape)
    print("conann distances finite:", bool(np.isfinite(distances).all()))
    print("calibration keys:", sorted(calibration.keys()))
    print("metrics:", metrics)
    print("timing keys:", sorted(timing.keys()))


if __name__ == "__main__":
    main()

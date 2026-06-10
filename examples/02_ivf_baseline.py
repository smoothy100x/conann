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

    rng = np.random.default_rng(11)
    d, nb, nt, nq, nlist, k = 32, 5000, 3000, 200, 64, 10

    xb = rng.random((nb, d), dtype=np.float32)
    xt = rng.random((nt, d), dtype=np.float32)
    xq = rng.random((nq, d), dtype=np.float32)

    exact = conann.IndexFlatL2(d)
    exact.add(xb)
    _, ground_truth = exact.search(xq, k)

    quantizer = conann.IndexFlatL2(d)
    index = conann.IndexIVFFlat(quantizer, d, nlist, conann.METRIC_L2)
    index.train(xt)
    index.add(xb)

    print("nprobe recall")
    for nprobe in [1, 2, 4, 8, 16, 32, 64]:
        index.nprobe = nprobe
        _, labels = index.search(xq, k)
        print(f"{nprobe:>6} {recall_at_k(labels, ground_truth):.4f}")


if __name__ == "__main__":
    main()

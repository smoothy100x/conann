from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import conann as faiss


def recall_at_k(labels: np.ndarray, ground_truth: np.ndarray) -> float:
    hits = 0
    for got, expected in zip(labels, ground_truth):
        expected_set = set(int(x) for x in expected)
        hits += sum(1 for x in got if int(x) in expected_set)
    return hits / float(labels.size)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--python-version", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    rng = np.random.default_rng(123)
    d, nb, nq, nlist, k = 16, 1200, 160, 32, 5
    xb = rng.random((nb, d), dtype=np.float32)
    xq = rng.random((nq, d), dtype=np.float32)

    exact = faiss.IndexFlatL2(d)
    exact.add(xb)
    _, gt = exact.search(xq, k)
    gt = np.ascontiguousarray(gt, dtype=np.int64)

    quantizer = faiss.IndexFlatL2(d)
    index = faiss.IndexIVFFlat(quantizer, d, nlist, faiss.METRIC_L2)
    index.train(xb)
    index.add(xb)

    method_checks = {
        "has_calibrate_conann": hasattr(index, "calibrate_conann"),
        "has_search_conann": hasattr(index, "search_conann"),
        "has_conann_time_report": hasattr(index, "conann_time_report"),
        "has_evaluate_conann": hasattr(index, "evaluate_conann"),
        "has_standard_search": hasattr(index, "search"),
    }
    missing = [name for name, ok in method_checks.items() if not ok]
    if missing:
        raise RuntimeError(f"missing wrapper methods: {', '.join(missing)}")

    index.nprobe = 8
    base_d, base_i = index.search(xq, k)
    base_recall = recall_at_k(base_i, gt)

    params = index.calibrate_conann(
        0.2,
        k,
        xq,
        gt,
        calib_sz=0.5,
        tune_sz=0.25,
        max_distance=100000.0,
        dataset_key=f"wheel-smoke-{args.python_version}",
    )
    conann_d, conann_i = index.search_conann(xq[:24], params, k=k)

    report = {
        "python": args.python_version,
        "conann_file": getattr(faiss, "__file__", None),
        "faiss_file": getattr(faiss, "__file__", None),
        "faiss_version": getattr(faiss, "__version__", None),
        "method_checks": method_checks,
        "ntotal": int(index.ntotal),
        "nlist": int(index.nlist),
        "baseline_shape": list(base_d.shape),
        "baseline_recall_at_k": float(base_recall),
        "conann_shape": list(conann_d.shape),
        "conann_first_labels": [int(x) for x in conann_i[0]],
        "lamhat": float(params["lamhat"]),
        "kreg": float(params["kreg"]),
        "reg_lambda": float(params["reg_lambda"]),
        "time_report": params.get("time_report", {}),
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

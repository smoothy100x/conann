from __future__ import annotations

import numpy as np
import conann


def main() -> None:
    rng = np.random.default_rng(7)
    d, nb, nq, k = 16, 1000, 5, 4

    xb = rng.random((nb, d), dtype=np.float32)
    xq = rng.random((nq, d), dtype=np.float32)

    index = conann.IndexFlatL2(d)
    index.add(xb)

    distances, labels = index.search(xq, k)

    print("conann", conann.__version__)
    print("index ntotal:", index.ntotal)
    print("distances shape:", distances.shape)
    print("labels shape:", labels.shape)
    print("first query neighbors:", labels[0].tolist())


if __name__ == "__main__":
    main()

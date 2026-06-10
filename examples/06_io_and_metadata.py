from __future__ import annotations

import tempfile
from pathlib import Path

import numpy as np
import conann


def main() -> None:
    rng = np.random.default_rng(59)
    d, nb, k = 12, 500, 3
    xb = rng.random((nb, d), dtype=np.float32)
    xq = rng.random((2, d), dtype=np.float32)

    index = conann.IndexFlatL2(d)
    index.add(xb)

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "flat.index"
        conann.write_index(index, str(path))
        restored = conann.read_index(str(path))

        distances, labels = restored.search(xq, k)

    print("conann version:", conann.__version__)
    print("bundled faiss version:", conann.__faiss_version__)
    print("restored ntotal:", restored.ntotal)
    print("labels:", labels.tolist())
    print("distances:", np.round(distances, 4).tolist())


if __name__ == "__main__":
    main()

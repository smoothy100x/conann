from __future__ import annotations

import numpy as np
import conann

try:
    from sklearn.decomposition import TruncatedSVD
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import Normalizer
except ImportError as exc:
    raise SystemExit(
        "Install the optional dependency first: pip install scikit-learn"
    ) from exc


DOCUMENTS = [
    "vector search powers retrieval augmented generation",
    "nearest neighbor indexes make embedding search faster",
    "faiss provides efficient similarity search over dense vectors",
    "conann adds calibrated adaptive search over ivf indexes",
    "pytorch models can produce embeddings for images and text",
    "transformers are commonly used to encode natural language",
    "databases can store vectors for semantic search applications",
    "approximate search trades exactness for speed and scale",
    "calibration can control retrieval error in adaptive systems",
    "python packaging makes native research systems easier to use",
]

QUERIES = [
    "adaptive vector retrieval",
    "python native package",
    "embedding model search",
]


def main() -> None:
    pipeline = make_pipeline(
        TfidfVectorizer(),
        TruncatedSVD(n_components=8, random_state=41),
        Normalizer(copy=False),
    )

    xb = pipeline.fit_transform(DOCUMENTS).astype("float32")
    xq = pipeline.transform(QUERIES).astype("float32")

    index = conann.IndexFlatL2(xb.shape[1])
    index.add(np.ascontiguousarray(xb))

    _, labels = index.search(np.ascontiguousarray(xq), k=3)

    for query, ids in zip(QUERIES, labels):
        print(f"\nquery: {query}")
        for doc_id in ids:
            print(f"- {DOCUMENTS[int(doc_id)]}")


if __name__ == "__main__":
    main()

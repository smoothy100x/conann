from __future__ import annotations

import numpy as np
import conann

try:
    import torch
except ImportError as exc:
    raise SystemExit("Install the optional dependency first: pip install torch") from exc


class TinyEmbedder(torch.nn.Module):
    def __init__(self, in_dim: int, out_dim: int) -> None:
        super().__init__()
        self.net = torch.nn.Sequential(
            torch.nn.Linear(in_dim, 64),
            torch.nn.ReLU(),
            torch.nn.Linear(64, out_dim),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


def main() -> None:
    torch.manual_seed(31)
    in_dim, d, nb, nq, k = 24, 16, 1000, 8, 5

    model = TinyEmbedder(in_dim, d).eval()
    base_features = torch.randn(nb, in_dim)
    query_features = torch.randn(nq, in_dim)

    with torch.no_grad():
        xb = model(base_features).cpu().numpy().astype("float32")
        xq = model(query_features).cpu().numpy().astype("float32")

    index = conann.IndexFlatL2(d)
    index.add(xb)
    distances, labels = index.search(xq, k)

    print("base embeddings:", xb.shape)
    print("query embeddings:", xq.shape)
    print("nearest ids for query 0:", labels[0].tolist())
    print("distances for query 0:", np.round(distances[0], 4).tolist())


if __name__ == "__main__":
    main()

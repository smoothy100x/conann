# conann

`conann` is a CPU-focused Python package for the ConANN-enabled FAISS bindings.
It exposes the familiar FAISS-style Python API under:

```python
import conann
```

The package is intended for approximate nearest-neighbor search workflows where
vectors are produced in Python, NumPy, PyTorch, Transformers, CLIP, sentence
embedding models, or similar ML pipelines, and then searched through an IVF index.

This project packages the ConANN-modified FAISS CPU path so it can be installed
and used directly from Python without asking users to build the research fork by
hand.

## Install

```bash
pip install conann
```

Supported wheels are built for:

- Python `3.10`, `3.11`, `3.12`, `3.13`, `3.14`
- Linux `x86_64`
- Windows `win_amd64`
- CPU-only execution

## Quick Start

```python
import numpy as np
import conann

d = 32
nb = 5000
nq = 100
nlist = 32
k = 5

rng = np.random.default_rng(123)
xb = rng.random((nb, d), dtype=np.float32)
xq = rng.random((nq, d), dtype=np.float32)

index = conann.IndexFlatL2(d)
index.add(xb)

distances, labels = index.search(xq, k)
print(labels.shape)
```

## IVF Search

```python
quantizer = conann.IndexFlatL2(d)
ivf = conann.IndexIVFFlat(quantizer, d, nlist, conann.METRIC_L2)

ivf.train(xb)
ivf.add(xb)
ivf.nprobe = 8

distances, labels = ivf.search(xq, k)
```

## ConANN Calibration And Search

ConANN-specific methods are exposed on supported IVF indexes:

```python
exact = conann.IndexFlatL2(d)
exact.add(xb)
_, ground_truth = exact.search(xq, k)

calibration = ivf.calibrate_conann(
    alpha=0.2,
    k=k,
    xq=xq,
    ground_truth=ground_truth,
    calib_sz=0.5,
    tune_sz=0.25,
    dataset_key="example",
)

distances, labels = ivf.search_conann(xq, calibration, k=k)
metrics = ivf.evaluate_conann(labels, ground_truth)
timing = ivf.conann_time_report()

print(metrics)
print(timing)
```

The main ConANN additions are:

- `calibrate_conann(...)`
- `search_conann(...)`
- `evaluate_conann(...)`
- `conann_time_report()`

Standard FAISS-style index classes such as `IndexFlatL2` and `IndexIVFFlat` are
also available through the `conann` module.

## PyTorch Embeddings

`conann` works with PyTorch-generated embeddings after converting tensors to
CPU `float32` NumPy arrays:

```python
embeddings = model_output.detach().cpu().numpy().astype("float32")
```

Those arrays can then be added to a `conann` index in the same way as regular
NumPy vectors.

## Package Metadata

```python
import conann

print(conann.__version__)        # 0.1.1
print(conann.__faiss_version__)  # 1.9.0
```

This package intentionally uses `import conann`; it does not install a top-level
`import faiss` alias. Internal SWIG modules remain private implementation
details of the package.

## Scope

This package is currently:

- CPU-only
- focused on the ConANN-enabled IVF path
- distributed as prebuilt wheels for supported CPython versions
- intended for research, experimentation, and practical Python access to ConANN

It is not a complete replacement for every FAISS feature. In particular, it does
not provide GPU FAISS support, and not every FAISS index family is part of the
ConANN-specific workflow.

## Development

The package root is:

```text
conann/
```

The ConANN/FAISS C++ source used by the build lives at:

```text
../conann-main/conann
```

Useful scripts:

```text
scripts/build_manylinux_wheels.sh
scripts/build_all_pythons.sh
scripts/build_all_pythons_windows.ps1
scripts/verify_wheels.sh
scripts/verify_wheels_windows.ps1
```

Release wheels and smoke-test records are kept under:

```text
wheels/linux_x86_64/
wheels/win_amd64/
results/
```

## License And Attribution

This package is built from a ConANN-modified FAISS codebase. Keep upstream
license notices and attribution intact when redistributing or modifying the
package.

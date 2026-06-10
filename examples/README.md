# conann examples

These examples show the main ways to use `conann` from Python.

Run them after installing the package:

```bash
pip install conann
```

Examples:

```text
01_simple_flat_search.py       Basic exact vector search with NumPy
02_ivf_baseline.py             Standard IVF indexing and nprobe tuning
03_full_conann_workflow.py     Calibration, adaptive search, metrics, timing
04_pytorch_embeddings.py       PyTorch tensor embeddings searched with conann
05_sklearn_text_search.py      scikit-learn text vectors searched with conann
06_io_and_metadata.py          Save/load index files and inspect package metadata
```

Optional dependencies:

```bash
pip install torch scikit-learn
```

The core examples only require `numpy` and `conann`.

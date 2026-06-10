# Release Artifacts

This directory is the package root for `conann`.

The current release artifacts for `conann==0.1.1` are stored under `wheels/`.

## Linux Wheels

Current Linux wheels:

```text
wheels/linux_x86_64/
  conann-0.1.1-cp310-cp310-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl
  conann-0.1.1-cp311-cp311-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl
  conann-0.1.1-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl
  conann-0.1.1-cp313-cp313-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl
  conann-0.1.1-cp314-cp314-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl
```

Verification results:

```text
results/linux_wheel_smoke_matrix.csv
results/linux_wheel_smoke/
```

## Windows Wheels

Current Windows wheels:

```text
wheels/win_amd64/
  conann-0.1.1-cp310-cp310-win_amd64.whl
  conann-0.1.1-cp311-cp311-win_amd64.whl
  conann-0.1.1-cp312-cp312-win_amd64.whl
  conann-0.1.1-cp313-cp313-win_amd64.whl
  conann-0.1.1-cp314-cp314-win_amd64.whl
```

Verification results:

```text
results/windows_wheel_smoke_matrix.csv
results/windows_wheel_smoke/
```

## Upload Set

For PyPI/TestPyPI upload, use only the `0.1.1` wheels:

```text
wheels/linux_x86_64/conann-0.1.1-*.whl
wheels/win_amd64/conann-0.1.1-*.whl
```

Do not re-upload `0.1.0` files. PyPI files are immutable, and the `0.1.1`
release carries the updated README metadata.

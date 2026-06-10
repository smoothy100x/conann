#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$(cd "${PACKAGE_DIR}/.." && pwd)"
SRC_DIR="${ROOT_DIR}/conann-main/conann"
BUILD_DIR="${PACKAGE_DIR}/build"
DIST_DIR="${PACKAGE_DIR}/dist"
WHEEL_DIR="${DIST_DIR}/linux_x86_64"

if [[ -n "${CONANN_PYTHON:-}" ]]; then
  PYTHON_BIN="${CONANN_PYTHON}"
else
  PYTHON_BIN="$(command -v python3)"
fi

PYTHON_DIR="${BUILD_DIR}/faiss/python"
TMP_WHEEL_DIR="${BUILD_DIR}/wheelhouse-local"
PYTAG="$("${PYTHON_BIN}" - <<'PY'
import sys
print(f"cp{sys.version_info.major}{sys.version_info.minor}")
PY
)"

mkdir -p "${BUILD_DIR}" "${DIST_DIR}" "${WHEEL_DIR}"
rm -rf "${TMP_WHEEL_DIR}"
mkdir -p "${TMP_WHEEL_DIR}"
rm -f "${WHEEL_DIR}"/conann-0.1.1-"${PYTAG}"-*.whl

export PATH="$(dirname "${PYTHON_BIN}"):${PATH}"

cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
  -DFAISS_ENABLE_GPU=OFF \
  -DFAISS_ENABLE_PYTHON=ON \
  -DFAISS_ENABLE_C_API=OFF \
  -DBUILD_TESTING=OFF \
  -DCONANN_ENABLE_EXTRAS=OFF \
  -DFAISS_OPT_LEVEL=avx2 \
  -DPython_EXECUTABLE="${PYTHON_BIN}"

cmake --build "${BUILD_DIR}" --target swigfaiss_avx2 -j"$(nproc)"
cmake --build "${BUILD_DIR}" --target faiss_python_callbacks -j"$(nproc)"

"${PYTHON_BIN}" "${PACKAGE_DIR}/tools/stage_conann_package.py" \
  --source-python-dir "${PYTHON_DIR}" \
  --package-dir "${PACKAGE_DIR}/src/conann"

"${PYTHON_BIN}" -m pip wheel "${PACKAGE_DIR}" \
  --no-build-isolation \
  --no-deps \
  --wheel-dir "${TMP_WHEEL_DIR}"

cp "${TMP_WHEEL_DIR}"/conann-0.1.1-"${PYTAG}"-*.whl "${WHEEL_DIR}/"

echo "Built wheel:"
ls -1 "${WHEEL_DIR}"/conann-0.1.1-"${PYTAG}"-*.whl

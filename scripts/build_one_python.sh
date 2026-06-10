#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 PYTHON_VERSION" >&2
  exit 2
fi

PYVER="$1"
PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$(cd "${PACKAGE_DIR}/.." && pwd)"
SRC_DIR="${ROOT_DIR}/conann-main/conann"
BUILD_ROOT="${PACKAGE_DIR}/build"
DIST_DIR="${PACKAGE_DIR}/dist"
WHEEL_DIR="${DIST_DIR}/linux_x86_64"
LOG_DIR="${PACKAGE_DIR}/logs"
PYTHON_BIN="${HOME}/.pyenv/versions/${PYVER}/bin/python"
BUILD_DIR="${BUILD_ROOT}/py${PYVER}"
PYTHON_DIR="${BUILD_DIR}/faiss/python"
TMP_WHEEL_DIR="${BUILD_DIR}/wheelhouse"

if [ ! -x "${PYTHON_BIN}" ]; then
  echo "missing Python: ${PYTHON_BIN}" >&2
  exit 1
fi

PYTAG="$("${PYTHON_BIN}" - <<'PY'
import sys
print(f"cp{sys.version_info.major}{sys.version_info.minor}")
PY
)"

mkdir -p "${BUILD_DIR}" "${DIST_DIR}" "${WHEEL_DIR}" "${LOG_DIR}"
rm -rf "${TMP_WHEEL_DIR}"
mkdir -p "${TMP_WHEEL_DIR}"
rm -f "${WHEEL_DIR}"/conann-0.1.1-"${PYTAG}"-*.whl

export PATH="$(dirname "${PYTHON_BIN}"):${PATH}"

echo "== Python ${PYVER} (${PYTAG}) =="
"${PYTHON_BIN}" - <<'PY'
import sys, numpy, packaging, setuptools, wheel
print("python", sys.version.split()[0])
print("executable", sys.executable)
print("numpy", numpy.__version__)
PY

cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
  -DFAISS_ENABLE_GPU=OFF \
  -DFAISS_ENABLE_PYTHON=ON \
  -DFAISS_ENABLE_C_API=OFF \
  -DBUILD_TESTING=OFF \
  -DCONANN_ENABLE_EXTRAS=OFF \
  -DFAISS_OPT_LEVEL=avx2 \
  -DPython_EXECUTABLE="${PYTHON_BIN}" \
  2>&1 | tee "${LOG_DIR}/configure-py${PYVER}.log"

cmake --build "${BUILD_DIR}" --target swigfaiss_avx2 -j"$(nproc)" \
  2>&1 | tee "${LOG_DIR}/build-py${PYVER}.log"

cmake --build "${BUILD_DIR}" --target faiss_python_callbacks -j"$(nproc)" \
  2>&1 | tee -a "${LOG_DIR}/build-py${PYVER}.log"

"${PYTHON_BIN}" "${PACKAGE_DIR}/tools/stage_conann_package.py" \
  --source-python-dir "${PYTHON_DIR}" \
  --package-dir "${PACKAGE_DIR}/src/conann"

"${PYTHON_BIN}" -m pip wheel "${PACKAGE_DIR}" \
  --no-build-isolation \
  --no-deps \
  --wheel-dir "${TMP_WHEEL_DIR}" \
  2>&1 | tee "${LOG_DIR}/package-py${PYVER}.log"

cp "${TMP_WHEEL_DIR}"/conann-0.1.1-"${PYTAG}"-*.whl "${WHEEL_DIR}/"

echo "built wheel:"
ls -lh "${WHEEL_DIR}"/conann-0.1.1-"${PYTAG}"-*.whl

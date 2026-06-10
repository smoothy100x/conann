#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHEEL_DIR="${ROOT}/dist/linux_x86_64"
RESULT_DIR="${ROOT}/results/wheel_smoke"
VENV_DIR="${ROOT}/venvs"
CSV="${ROOT}/results/wheel_smoke_matrix.csv"
PYTHONS=(3.10.19 3.11.14 3.12.12 3.13.9 3.14.0)

mkdir -p "${RESULT_DIR}" "${VENV_DIR}" "$(dirname "${CSV}")"
printf "python,wheel,install_ok,smoke_ok,notes\n" > "${CSV}"

for PYVER in "${PYTHONS[@]}"; do
  PY="${HOME}/.pyenv/versions/${PYVER}/bin/python"
  PYTAG="$("${PY}" -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")')"
  WHEEL="$(find "${WHEEL_DIR}" -maxdepth 1 -name "conann-0.1.1-${PYTAG}-${PYTAG}-linux_x86_64.whl" -print -quit)"
  VENV="${VENV_DIR}/py${PYVER}"
  OUT="${RESULT_DIR}/py${PYVER}.json"
  LOG="${RESULT_DIR}/py${PYVER}.log"

  if [ ! -f "${WHEEL}" ]; then
    printf "%s,,false,false,missing wheel\n" "${PYVER}" >> "${CSV}"
    continue
  fi

  rm -rf "${VENV}"
  "${PY}" -m venv --system-site-packages "${VENV}"
  if ! "${VENV}/bin/python" -m pip install --force-reinstall --no-deps --no-index "${WHEEL}" > "${LOG}" 2>&1; then
    printf "%s,%s,false,false,install failed\n" "${PYVER}" "$(basename "${WHEEL}")" >> "${CSV}"
    continue
  fi

  if "${VENV}/bin/python" "${ROOT}/tests/test_synthetic_conann.py" >> "${LOG}" 2>&1; then
    "${VENV}/bin/python" - <<'PY' > "${OUT}"
import json
import conann
result = {
    "module": getattr(conann, "__file__", None),
    "version": getattr(conann, "__version__", None),
    "faiss_version": getattr(conann, "__faiss_version__", None),
}
print(json.dumps(result, indent=2))
PY
    printf "%s,%s,true,true,ok\n" "${PYVER}" "$(basename "${WHEEL}")" >> "${CSV}"
  else
    printf "%s,%s,true,false,smoke failed\n" "${PYVER}" "$(basename "${WHEEL}")" >> "${CSV}"
  fi
done

cat "${CSV}"

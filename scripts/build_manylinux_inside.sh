#!/bin/bash
set -euo pipefail

ROOT=/work/conann
SRC=/work/conann-main/conann
OUT="${ROOT}/wheels/linux_x86_64"
BUILD_ROOT="${ROOT}/build-manylinux"
LOG_DIR="${ROOT}/logs"

mkdir -p "${OUT}" "${BUILD_ROOT}" "${LOG_DIR}"

log_step() {
  printf '\n[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

install_blas_deps() {
  if rpm -q openblas-devel lapack-devel >/dev/null 2>&1; then
    log_step "BLAS/LAPACK deps already present; skipping install"
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    log_step "installing BLAS/LAPACK deps with dnf"
    dnf install -y openblas-devel lapack-devel
    return
  fi
  if command -v yum >/dev/null 2>&1; then
    log_step "installing BLAS/LAPACK deps with yum"
    yum install -y openblas-devel lapack-devel
    return
  fi
  if command -v microdnf >/dev/null 2>&1; then
    log_step "installing BLAS/LAPACK deps with microdnf"
    microdnf install -y openblas-devel lapack-devel
    return
  fi
  echo "no supported package manager found for BLAS/LAPACK install" >&2
  exit 1
}

install_blas_deps

PY_TAGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --python-tag)
      PY_TAGS+=("$2")
      shift 2
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [ "${#PY_TAGS[@]}" -eq 0 ]; then
  PY_TAGS=(cp310-cp310 cp311-cp311 cp312-cp312 cp313-cp313 cp314-cp314)
fi

log_step "manylinux source root: ${SRC}"
log_step "output wheel dir: ${OUT}"
log_step "python tags: ${PY_TAGS[*]}"

for py in "${PY_TAGS[@]}"; do
  pybin="/opt/python/${py}/bin/python"
  pyroot="/opt/python/${py}"
  if [ ! -x "${pybin}" ]; then
    echo "missing Python ${pybin}" >&2
    exit 1
  fi

  build_dir="${BUILD_ROOT}/${py}"
  pyver="$("${pybin}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')"
  pytag="$("${pybin}" -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")')"
  wheelhouse="${build_dir}/wheelhouse"

  log_step "starting build for ${py} (${pyver})"
  rm -rf "${build_dir}"
  mkdir -p "${build_dir}" "${wheelhouse}"
  rm -f "${OUT}"/conann-0.1.1-"${pytag}"-*.whl

  log_step "installing Python build deps for ${py}"
  "${pybin}" -m pip install -U pip setuptools wheel packaging numpy auditwheel

  log_step "configuring CMake for ${py}"
  cmake -S "${SRC}" -B "${build_dir}" \
    -DFAISS_ENABLE_GPU=OFF \
    -DFAISS_ENABLE_PYTHON=ON \
    -DFAISS_ENABLE_C_API=OFF \
    -DBUILD_TESTING=OFF \
    -DCONANN_ENABLE_EXTRAS=OFF \
    -DFAISS_OPT_LEVEL=avx2 \
    -DBLA_VENDOR=OpenBLAS \
    -DPython_ROOT_DIR="${pyroot}" \
    -DPython_EXECUTABLE="${pybin}" \
    -DPython3_ROOT_DIR="${pyroot}" \
    -DPython3_EXECUTABLE="${pybin}" \
    -DPython_FIND_STRATEGY=LOCATION \
    2>&1 | tee "${LOG_DIR}/manylinux-configure-${pyver}.log"

  log_step "building swigfaiss_avx2 for ${py}"
  cmake --build "${build_dir}" --target swigfaiss_avx2 -j"$(nproc)" \
    2>&1 | tee "${LOG_DIR}/manylinux-build-${pyver}.log"
  log_step "building faiss_python_callbacks for ${py}"
  cmake --build "${build_dir}" --target faiss_python_callbacks -j"$(nproc)" \
    2>&1 | tee -a "${LOG_DIR}/manylinux-build-${pyver}.log"

  log_step "staging Python package files for ${py}"
  "${pybin}" "${ROOT}/tools/stage_conann_package.py" \
    --source-python-dir "${build_dir}/faiss/python" \
    --package-dir "${ROOT}/src/conann"

  log_step "building wheel for ${py}"
  "${pybin}" -m pip wheel "${ROOT}" \
    --no-build-isolation \
    --no-deps \
    --wheel-dir "${wheelhouse}" \
    2>&1 | tee "${LOG_DIR}/manylinux-package-${pyver}.log"

  log_step "repairing wheel with auditwheel for ${py}"
  "${pybin}" -m auditwheel repair \
    --plat manylinux_2_28_x86_64 \
    --wheel-dir "${OUT}" \
    "${wheelhouse}"/conann-0.1.1-"${pytag}"-*.whl \
    2>&1 | tee "${LOG_DIR}/manylinux-repair-${pyver}.log"

  log_step "finished ${py}"
done

log_step "all manylinux builds finished"

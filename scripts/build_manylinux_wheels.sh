#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${MANYLINUX_IMAGE:-quay.io/pypa/manylinux_2_28_x86_64}"
if [ "$#" -gt 0 ]; then
  PYTHONS=("$@")
else
  PYTHONS=(cp310-cp310 cp311-cp311 cp312-cp312 cp313-cp313 cp314-cp314)
fi
PYTHON_ARGS=()
for py in "${PYTHONS[@]}"; do
  PYTHON_ARGS+=("--python-tag" "$py")
done

echo "manylinux image: ${IMAGE}"
echo "python tags: ${PYTHONS[*]}"
echo "workspace: ${ROOT}"
echo "starting containerized manylinux build..."

podman run --rm \
  -v "${ROOT}:/work/conann:Z" \
  -v "$(cd "${ROOT}/.." && pwd)/conann-main:/work/conann-main:Z" \
  -w /work/conann \
  "${IMAGE}" \
  /bin/bash /work/conann/scripts/build_manylinux_inside.sh "${PYTHON_ARGS[@]}"

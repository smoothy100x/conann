#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for v in 3.10.19 3.11.14 3.12.12 3.13.9 3.14.0; do
  "${ROOT}/scripts/build_one_python.sh" "$v"
done

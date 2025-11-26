#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

mapfile -t COMPILE_SCRIPTS < <(find "${ROOT_DIR}" -maxdepth 2 -type f -name 'compile.sh' | sort)

if [[ "${#COMPILE_SCRIPTS[@]}" -eq 0 ]]; then
  echo "compile.sh が見つかりませんでした。" >&2
  exit 1
fi

for script_path in "${COMPILE_SCRIPTS[@]}"; do
  project_dir="$(dirname "${script_path}")"
  project_name="$(basename "${project_dir}")"

  echo "=============================="
  echo "${project_name} をビルド中..."
  echo "=============================="

  pushd "${project_dir}" > /dev/null
  ./compile.sh
  popd > /dev/null
done
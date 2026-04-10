#!/bin/bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [project_dir]" >&2
  exit 1
fi

SOURCE_DIR="${1:-$(pwd)}"
SOURCE_DIR="$(cd "${SOURCE_DIR}" && pwd)"
BUILD_DIR="${SOURCE_DIR}/build"

echo "クリーンビルドを準備中: ${SOURCE_DIR}"

rm -rf \
  "${BUILD_DIR}" \
  "${SOURCE_DIR}/CMakeFiles" \
  "${SOURCE_DIR}/CMakeCache.txt" \
  "${SOURCE_DIR}/Makefile" \
  "${SOURCE_DIR}/cmake_install.cmake" \
  "${SOURCE_DIR}/compile_commands.json" \
  "${SOURCE_DIR}/libcommon.a"

shopt -s nullglob
for path in "${SOURCE_DIR}"/bench*; do
  if [[ -d "${path}" || "${path}" == *.cpp ]]; then
    continue
  fi
  rm -f "${path}"
done
shopt -u nullglob

cmake \
  -S "${SOURCE_DIR}" \
  -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

cmake --build "${BUILD_DIR}" --parallel

if [[ -f "${BUILD_DIR}/compile_commands.json" ]]; then
  ln -sfn "build/compile_commands.json" "${SOURCE_DIR}/compile_commands.json"
fi

shopt -s nullglob
for binary_path in "${BUILD_DIR}"/bench*; do
  if [[ -d "${binary_path}" || ! -x "${binary_path}" ]]; then
    continue
  fi
  ln -sfn "build/$(basename "${binary_path}")" "${SOURCE_DIR}/$(basename "${binary_path}")"
done
shopt -u nullglob

echo "ビルド完了: ${SOURCE_DIR}"

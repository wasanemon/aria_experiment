#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

baseline_dir="${ROOT}/ariaer"
if [ "$#" -gt 0 ]; then
  candidate_dirs=("$@")
else
  candidate_dirs=(
    "${ROOT}/ariaer_cache_fix"
    "${ROOT}/ariaer_cache_fix_v2"
  )
fi

run_test() {
  local project_dir="$1"
  local target="$2"
  local prefix="$3"
  local label
  label="$(basename "${project_dir}")"

  if [ ! -x "${project_dir}/compile.sh" ]; then
    echo "missing compile script: ${project_dir}/compile.sh" >&2
    return 1
  fi

  pushd "${project_dir}" > /dev/null
  rm -rf CMakeFiles/ CMakeCache.txt goo* > /dev/null 2>&1 || true
  cmake -DCMAKE_BUILD_TYPE=Release . > /dev/null
  make -j "${target}" > /dev/null
  local output
  output="$(./"${target}" 2>&1)"
  popd > /dev/null

  local signature
  signature="$(printf '%s\n' "${output}" | sed -n "s/^${prefix}=//p")"
  if [ -z "${signature}" ]; then
    echo "equivalence signature not found for ${label}/${target}" >&2
    printf '%s\n' "${output}" >&2
    return 1
  fi

  printf '%s\n' "${signature}"
}

baseline_logic_signature="$(run_test "${baseline_dir}" "bench_equivalence_test" "EQUIVALENCE_SIGNATURE")"
baseline_ycsb_signature="$(run_test "${baseline_dir}" "bench_ycsb_seed_equivalence_test" "YCSB_EQUIVALENCE_SIGNATURE")"
echo "baseline(ariaer) logic: ${baseline_logic_signature}"
echo "baseline(ariaer) ycsb : ${baseline_ycsb_signature}"

failed=0
for project_dir in "${candidate_dirs[@]}"; do
  candidate_logic_signature="$(run_test "${project_dir}" "bench_equivalence_test" "EQUIVALENCE_SIGNATURE")"
  candidate_ycsb_signature="$(run_test "${project_dir}" "bench_ycsb_seed_equivalence_test" "YCSB_EQUIVALENCE_SIGNATURE")"
  label="$(basename "${project_dir}")"
  if [ "${candidate_logic_signature}" != "${baseline_logic_signature}" ]; then
    echo "FAIL ${label}" >&2
    echo "  logic baseline : ${baseline_logic_signature}" >&2
    echo "  logic candidate: ${candidate_logic_signature}" >&2
    failed=1
  fi
  if [ "${candidate_ycsb_signature}" != "${baseline_ycsb_signature}" ]; then
    echo "FAIL ${label}" >&2
    echo "  ycsb baseline : ${baseline_ycsb_signature}" >&2
    echo "  ycsb candidate: ${candidate_ycsb_signature}" >&2
    failed=1
  fi
  if [ "${candidate_logic_signature}" = "${baseline_logic_signature}" ] &&
     [ "${candidate_ycsb_signature}" = "${baseline_ycsb_signature}" ]; then
    echo "PASS ${label}: logic=${candidate_logic_signature} ycsb=${candidate_ycsb_signature}"
  fi
done

exit "${failed}"

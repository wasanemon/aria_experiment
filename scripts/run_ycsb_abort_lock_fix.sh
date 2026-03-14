#!/usr/bin/env bash
set -euo pipefail

# YCSB sweep for abort_lock fix variants.
# Results are stored under a dedicated timestamped directory separate from result/.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARIA="${ROOT}/aria_abort_lock_fix/bench_ycsb"
ARIAER="${ROOT}/ariaer_abort_lock_fix/bench_ycsb"
#ARIAER_CACHE_FIX="${ROOT}/ariaer_cache_fix_abort_lock_fix/bench_ycsb"
ARIAER_CACHE_FIX_V2="${ROOT}/ariaer_cache_fix_v2_abort_lock_fix/bench_ycsb"
POSTPROCESS_SCRIPT="${SCRIPT_DIR}/ycsb_logs_to_csv.sh"
RESULTS_ROOT="${RESULTS_ROOT:-${ROOT}/result_abort_lock_fix_ycsb}"
RUN_ID="${RUN_ID:-$(date +"%Y%m%d_%H%M%S")}"
OUT="${OUT_DIR:-${RESULTS_ROOT}/${RUN_ID}}"
LATEST_LINK="${RESULTS_ROOT}/latest"

threads=${THREADS:-12}
parts=${PARTITIONS:-12}
keys=${KEYS:-40000}
ariafb_lock_manager=${ARIAFB_LOCK_MANAGER:-1}

zipfs=(0.0 0.2 0.4 0.6 0.8 0.9)
ratios=(80 50)
ops_list=(10 100)
batch_sizes=(1000 4000)

prepare_run_dir () {
  mkdir -p "${RESULTS_ROOT}"
  mkdir -p "${OUT}"
  ln -sfn "${OUT}" "${LATEST_LINK}"
}

summarize_dir () {
  local target_dir="$1"
  local summary_file="${target_dir}/summary.tsv"
  local found_logs=0

  mkdir -p "${target_dir}"
  echo "zipf\tengine\tkeys\trw\tops\tbatch_size\taverage_commit" | tee "${summary_file}"

  shopt -s nullglob
  for f in "${target_dir}"/*.log; do
    found_logs=1
    base=$(basename "$f" .log)
    z=$(echo "$base" | sed -E 's/.*zipf_([0-9.]+)$/\1/')
    label="${base%%_p*}"
    k=$(echo "$base" | sed -E 's/.*_k([0-9]+)_.*/\1/')
    rw=$(echo "$base" | sed -E 's/.*_rw([0-9]+)_.*/\1/')
    ops=$(echo "$base" | sed -E 's/.*_ops([0-9]+)_.*/\1/')
    bs=$(echo "$base" | sed -E 's/.*_bs([0-9]+)_.*/\1/')
    avg=$(grep -o "average commit: [0-9.eE+\\-]*" "$f" | tail -1 | awk '{print $3}')
    echo -e "${z}\t${label}\t${k}\t${rw}\t${ops}\t${bs}\t${avg:-NA}" | tee -a "${summary_file}"
  done
  shopt -u nullglob

  if [ "${found_logs}" -eq 0 ]; then
    echo "!! no log files found in ${target_dir}" >&2
    return 1
  fi
}

postprocess_dir () {
  local target_dir="$1"

  summarize_dir "${target_dir}"

  if [ ! -x "${POSTPROCESS_SCRIPT}" ]; then
    echo "!! postprocess script not found at ${POSTPROCESS_SCRIPT}" >&2
    return 1
  fi

  "${POSTPROCESS_SCRIPT}" "${target_dir}" "${target_dir}/summary.csv"
}

resolve_summary_dir () {
  if [ "${#}" -ge 1 ]; then
    printf '%s\n' "$1"
  elif [ -L "${LATEST_LINK}" ]; then
    readlink -f "${LATEST_LINK}"
  else
    echo "!! summary target not found. pass a results directory or run the benchmark first." >&2
    return 1
  fi
}

run_one () { # bin label protocol extra_arg_string rw ops bs zipf
  local bin="$1" label="$2" proto="$3" extra_args="$4" rw="$5" ops="$6" bs="$7" z="$8"
  local tag="${label}_p${parts}_t${threads}_k${keys}_rw${rw}_ops${ops}_bs${bs}_zipf_${z}"
  local log="${OUT}/${tag}.log"

  echo "=== ${tag} ==="
  if ! "${bin}" --logtostderr=1 --protocol="${proto}" --id=0 --servers="127.0.0.1:10010" \
    --partition_num="${parts}" --threads="${threads}" --batch_size="${bs}" \
    --read_write_ratio="${rw}" --skew_pattern=both --zipf="${z}" \
    --ops_per_txn="${ops}" --keys="${keys}" \
    ${extra_args} \
    --global_key_space=True --cross_ratio=100 2>&1 | tee "${log}"; then
    echo "!! ${tag} failed" | tee -a "${log}" >&2
    return 1
  fi
}

run_engine () { # bin label protocol [extra_arg_string]
  local bin="$1" label="$2" proto="$3" extra_args="${4:-}"
  local failed=0

  if [ ! -x "$bin" ]; then
    echo "!! skip ${label}: binary not found at ${bin}" >&2
    return 1
  fi

  for z in "${zipfs[@]}"; do
    for rw in "${ratios[@]}"; do
      for ops in "${ops_list[@]}"; do
        for bs in "${batch_sizes[@]}"; do
          run_one "${bin}" "${label}" "${proto}" "${extra_args}" "${rw}" "${ops}" "${bs}" "${z}" || failed=1
        done
      done
    done
  done

  return "${failed}"
}

case "${1:-run}" in
  run)
    prepare_run_dir
    echo "results directory: ${OUT}"

    failed=0
    run_engine "${ARIA}" "aria_abort_lock_fix" "Aria" || failed=1
    run_engine "${ARIA}" "ariafb_abort_lock_fix" "AriaFB" "--ariaFB_lock_manager=${ariafb_lock_manager}" || failed=1
    run_engine "${ARIAER}" "ariaer_abort_lock_fix" "Aria" || failed=1
    run_engine "${ARIAER}" "ariaer_ariafb_abort_lock_fix" "AriaFB" "--ariaFB_lock_manager=${ariafb_lock_manager}" || failed=1
    #run_engine "${ARIAER_CACHE_FIX}" "ariaer_cache_fix_abort_lock_fix" "Aria" || failed=1
    run_engine "${ARIAER_CACHE_FIX_V2}" "ariaer_cache_fix_v2_abort_lock_fix" "Aria" || failed=1
    run_engine "${ARIAER_CACHE_FIX_V2}" "ariaer_cache_fix_v2_ariafb_abort_lock_fix" "AriaFB" "--ariaFB_lock_manager=${ariafb_lock_manager}" || failed=1
    postprocess_dir "${OUT}" || failed=1
    exit "${failed}"
    ;;
  summarize)
    target_dir="$(resolve_summary_dir "${2:-}")"
    echo "summarizing: ${target_dir}"
    postprocess_dir "${target_dir}"
    ;;
  *)
    echo "Usage: $0 [run|summarize] [results_dir]" >&2
    exit 1
    ;;
esac

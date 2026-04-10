#!/usr/bin/env bash
set -euo pipefail

# TPCC sweep for aria, ariaer, and ariaer_cache_fix_v2.
# Default settings are intentionally small and can be overridden by env vars.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ARIA="${ROOT}/aria/bench_tpcc"
ARIAER="${ROOT}/ariaer/bench_tpcc"
ARIAER_CACHE_FIX_V2="${ROOT}/ariaer_cache_fix_v2/bench_tpcc"
POSTPROCESS_SCRIPT="${SCRIPT_DIR}/tpcc_logs_to_csv.sh"

RESULTS_ROOT="${RESULTS_ROOT:-${ROOT}/result_tpcc_journal}"
RUN_ID="${RUN_ID:-$(date +"%Y%m%d_%H%M%S")}"
OUT="${OUT_DIR:-${RESULTS_ROOT}/${RUN_ID}}"
LATEST_LINK="${RESULTS_ROOT}/latest"

threads="${THREADS:-12}"
n_district="${N_DISTRICT:-10}"
write_to_w_ytd="${WRITE_TO_W_YTD:-true}"
payment_look_up="${PAYMENT_LOOK_UP:-false}"
operation_replication="${OPERATION_REPLICATION:-false}"
ariafb_lock_manager="${ARIAFB_LOCK_MANAGER:-1}"

partitions_list=(1 4 8 12 36 60 84 108 132 156 180)
queries=(mixed)
batch_sizes=(1000)
neworder_dists=(10)
payment_dists=(15)

prepare_run_dir() {
  mkdir -p "${RESULTS_ROOT}"
  mkdir -p "${OUT}"
  ln -sfn "${OUT}" "${LATEST_LINK}"
}

summarize_dir() {
  local target_dir="$1"
  local summary_file="${target_dir}/summary.tsv"
  local found_logs=0

  mkdir -p "${target_dir}"
  echo -e "query\tengine\tpartitions\tthreads\tbatch_size\tneworder_dist\tpayment_dist\tn_district\taverage_commit" | tee "${summary_file}"

  shopt -s nullglob
  for f in "${target_dir}"/*.log; do
    found_logs=1
    local base
    base="$(basename "$f" .log)"
    local query label p t bs nd pd dist avg
    query="$(echo "$base" | sed -E 's/.*_q([a-z]+)_.*/\1/')"
    label="${base%%_p*}"
    p="$(echo "$base" | sed -E 's/.*_p([0-9]+)_.*/\1/')"
    t="$(echo "$base" | sed -E 's/.*_t([0-9]+)_.*/\1/')"
    bs="$(echo "$base" | sed -E 's/.*_bs([0-9]+)_.*/\1/')"
    nd="$(echo "$base" | sed -E 's/.*_nd([0-9]+)$/\1/')"
    pd="$(echo "$base" | sed -E 's/.*_payd([0-9]+)_.*/\1/')"
    dist="$(echo "$base" | sed -E 's/.*_nord([0-9]+)_.*/\1/')"
    avg="$(grep -o "average commit: [0-9.eE+\\-]*" "$f" | tail -1 | awk '{print $3}')"
    echo -e "${query}\t${label}\t${p}\t${t}\t${bs}\t${dist}\t${pd}\t${nd}\t${avg:-NA}" | tee -a "${summary_file}"
  done
  shopt -u nullglob

  if [ "${found_logs}" -eq 0 ]; then
    echo "!! no log files found in ${target_dir}" >&2
    return 1
  fi
}

postprocess_dir() {
  local target_dir="$1"

  summarize_dir "${target_dir}"

  if [ ! -x "${POSTPROCESS_SCRIPT}" ]; then
    echo "!! postprocess script not found at ${POSTPROCESS_SCRIPT}" >&2
    return 1
  fi

  "${POSTPROCESS_SCRIPT}" "${target_dir}" "${target_dir}/summary.csv"
}

resolve_summary_dir() {
  if [ "$#" -ge 1 ]; then
    printf '%s\n' "$1"
  elif [ -L "${LATEST_LINK}" ]; then
    readlink -f "${LATEST_LINK}"
  else
    echo "!! summary target not found. pass a results directory or run the benchmark first." >&2
    return 1
  fi
}

run_one() { # bin label protocol extra_arg_string query batch_size neworder_dist payment_dist
  local bin="$1" label="$2" proto="$3" extra_args="$4" query="$5" bs="$6" nord="$7" payd="$8"
  local tag="${label}_p${parts}_t${threads}_q${query}_bs${bs}_nord${nord}_payd${payd}_nd${n_district}"
  local log="${OUT}/${tag}.log"

  echo "=== ${tag} ==="
  if ! "${bin}" --logtostderr=1 --protocol="${proto}" --id=0 --servers="127.0.0.1:10010" \
    --partition_num="${parts}" --threads="${threads}" --batch_size="${bs}" \
    --query="${query}" --neworder_dist="${nord}" --payment_dist="${payd}" \
    --n_district="${n_district}" --write_to_w_ytd="${write_to_w_ytd}" \
    --payment_look_up="${payment_look_up}" --operation_replication="${operation_replication}" \
    ${extra_args} \
    2>&1 | tee "${log}"; then
    echo "!! ${tag} failed" | tee -a "${log}" >&2
    return 1
  fi
}

run_engine() { # bin label protocol [extra_arg_string]
  local bin="$1" label="$2" proto="$3" extra_args="${4:-}"
  local failed=0

  if [ ! -x "${bin}" ]; then
    echo "!! skip ${label}: binary not found at ${bin}" >&2
    return 1
  fi

  for parts in "${partitions_list[@]}"; do
    for query in "${queries[@]}"; do
      for bs in "${batch_sizes[@]}"; do
        for nord in "${neworder_dists[@]}"; do
          for payd in "${payment_dists[@]}"; do
            run_one "${bin}" "${label}" "${proto}" "${extra_args}" "${query}" "${bs}" "${nord}" "${payd}" || failed=1
          done
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
    run_engine "${ARIA}" "aria" "Aria" || failed=1
    #run_engine "${ARIA}" "ariafb" "AriaFB" "--ariaFB_lock_manager=${ariafb_lock_manager}" || failed=1
    #run_engine "${ARIAER}" "ariaer" "Aria" || failed=1
    #run_engine "${ARIAER}" "ariaer_ariafb" "AriaFB" "--ariaFB_lock_manager=${ariafb_lock_manager}" || failed=1
    run_engine "${ARIAER_CACHE_FIX_V2}" "ariaer_cache_fix_v2" "Aria" || failed=1
    #run_engine "${ARIAER_CACHE_FIX_V2}" "ariaer_cache_fix_v2_ariafb" "AriaFB" "--ariaFB_lock_manager=${ariafb_lock_manager}" || failed=1
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

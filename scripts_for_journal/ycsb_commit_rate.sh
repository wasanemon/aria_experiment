#!/usr/bin/env bash
set -euo pipefail

# Commit rate experiment: measures per-batch commit/abort counts.
# Conditions match the abort_commit experiment:
#   rw=80, ops=100, bs=1000, threads=12, partitions=12, keys=40000

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARIA="${ROOT}/aria_commit_rate/build/bench_ycsb"
ARIAER="${ROOT}/ariaer_cache_fix_v2_commit_rate/build/bench_ycsb"
RESULTS_ROOT="${RESULTS_ROOT:-${ROOT}/result_for_journal/ycsb_commit_rate}"
RUN_ID="${RUN_ID:-$(date +"%Y%m%d_%H%M%S")}"
OUT="${OUT_DIR:-${RESULTS_ROOT}/${RUN_ID}}"
LATEST_LINK="${RESULTS_ROOT}/latest"

threads=${THREADS:-12}
parts=${PARTITIONS:-12}
keys=${KEYS:-40000}

zipfs=(0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 0.99)
batch_size=1000
rw=80
ops=100

prepare_run_dir () {
  mkdir -p "${RESULTS_ROOT}"
  mkdir -p "${OUT}"
  ln -sfn "${OUT}" "${LATEST_LINK}"
}

run_one () {
  local bin="$1" label="$2" proto="$3" z="$4"
  local tag="${label}_p${parts}_t${threads}_k${keys}_rw${rw}_ops${ops}_bs${batch_size}_zipf_${z}"
  local log="${OUT}/${tag}.log"

  echo "=== ${tag} ==="
  if ! "${bin}" --logtostderr=1 --protocol="${proto}" --id=0 --servers="127.0.0.1:10010" \
    --partition_num="${parts}" --threads="${threads}" --batch_size="${batch_size}" \
    --read_write_ratio="${rw}" --skew_pattern=both --zipf="${z}" \
    --ops_per_txn="${ops}" --keys="${keys}" \
    --global_key_space=True --cross_ratio=100 2>&1 | tee "${log}"; then
    echo "!! ${tag} failed" | tee -a "${log}" >&2
    return 1
  fi
}

run_engine () {
  local bin="$1" label="$2" proto="$3"
  local failed=0

  if [ ! -x "$bin" ]; then
    echo "!! skip ${label}: binary not found at ${bin}" >&2
    return 1
  fi

  for z in "${zipfs[@]}"; do
    run_one "${bin}" "${label}" "${proto}" "${z}" || failed=1
  done

  return "${failed}"
}

postprocess_dir () {
  local target_dir="$1"
  local out_csv="${target_dir}/commit_rate.csv"

  echo "zipf,engine,commit_rate,avg_batch_commit,avg_batch_abort,total_batches" > "${out_csv}"

  shopt -s nullglob
  for f in "${target_dir}"/*.log; do
    base=$(basename "$f" .log)
    label=$(echo "$base" | sed -E 's/_p[0-9]+_t.*//')
    z=$(echo "$base" | sed -E 's/.*zipf_([0-9.]+)$/\1/')

    line=$(grep "batch stats:" "$f" | tail -1) || line=""
    if [ -z "$line" ]; then
      echo "${z},${label},NA,NA,NA,NA" >> "${out_csv}"
      continue
    fi

    total_batches=$(echo "$line" | grep -oP 'total_batches=\K[0-9.eE+\-]+')
    avg_commit=$(echo "$line" | grep -oP 'avg_batch_commit=\K[0-9.eE+\-]+')
    avg_abort=$(echo "$line" | grep -oP 'avg_batch_abort=\K[0-9.eE+\-]+')
    commit_rate=$(echo "$line" | grep -oP 'commit_rate=\K[0-9.eE+\-]+')

    echo "${z},${label},${commit_rate},${avg_commit},${avg_abort},${total_batches}" >> "${out_csv}"
  done
  shopt -u nullglob

  echo "Wrote: ${out_csv}"
}

resolve_summary_dir () {
  if [ "${#}" -ge 1 ]; then
    printf '%s\n' "$1"
  elif [ -L "${LATEST_LINK}" ]; then
    readlink -f "${LATEST_LINK}"
  else
    echo "!! summary target not found." >&2
    return 1
  fi
}

case "${1:-run}" in
  run)
    prepare_run_dir
    echo "results directory: ${OUT}"

    failed=0
    run_engine "${ARIA}" "aria" "Aria" || failed=1
    run_engine "${ARIAER}" "ariaer_cache_fix_v2" "Aria" || failed=1
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

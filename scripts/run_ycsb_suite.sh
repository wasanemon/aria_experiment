#!/usr/bin/env bash

# YCSB sweep for aria and ariaer
# - threads: 16
# - partitions: 16
# - zipf: 0.0..0.9
# - read_write_ratio: 80, 50
# - ops_per_txn: 10, 100

ROOT="/home/wasanemon/project/aria_experiment"
ARIA="$ROOT/aria/bench_ycsb"
ARIAER="$ROOT/ariaer/bench_ycsb"
ARIAER_SPLIT_NO_ABORT="$ROOT/ariaer_split_reservation_without_abort_list/bench_ycsb"
ARIAER_NOSPLIT_NO_ABORT="$ROOT/ariaer_without_split_reservation_without_abort_list/bench_ycsb"
ARIAER_NOSPLIT_ABORT="$ROOT/ariaer_without_split_reservation_with_abort_list/bench_ycsb"
OUT="$ROOT/results_suite"

mkdir -p "$OUT"

threads=${THREADS:-16}
parts=${PARTITIONS:-16}

zipfs=(0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9)
ratios=(80 50)
ops_list=(10 100)
batch_sizes=(1024 2048 4096 16000)


run_one () { # bin label protocol rw ops bs zipf
  local bin="$1" label="$2" proto="$3" rw="$4" ops="$5" bs="$6" z="$7"
  local tag="${label}_p${parts}_t${threads}_rw${rw}_ops${ops}_bs${bs}_zipf_${z}"
  local log="${OUT}/${tag}.log"
  echo "=== ${tag} ==="
  "${bin}" --logtostderr=1 --protocol="${proto}" --id=0 --servers="127.0.0.1:10010" \
    --partition_num="${parts}" --threads="${threads}" --batch_size="${bs}" \
    --read_write_ratio="${rw}" --skew_pattern=both --zipf="${z}" \
    --ops_per_txn="${ops}" 2>&1 | tee "${log}" || true
}

run_engine () { # bin label
  local bin="$1" label="$2"
  if [ ! -x "$bin" ]; then
    echo "!! skip ${label}: binary not found at ${bin}" >&2
    return
  fi
  for z in "${zipfs[@]}"; do
    for rw in "${ratios[@]}"; do
      for ops in "${ops_list[@]}"; do
        for bs in "${batch_sizes[@]}"; do
          run_one "${bin}" "${label}" "Aria" "${rw}" "${ops}" "${bs}" "${z}"
        done
      done
    done
  done
}

case "${1:-run}" in
  run)
    run_engine "${ARIA}" "aria"
    run_engine "${ARIAER}" "ariaer"
    run_engine "${ARIAER_SPLIT_NO_ABORT}" "ariaer_split_no_abort_list"
    run_engine "${ARIAER_NOSPLIT_NO_ABORT}" "ariaer_without_split_no_abort_list"
    run_engine "${ARIAER_NOSPLIT_ABORT}" "ariaer_without_split_with_abort_list"
    ;;
  summarize)
    echo "zipf\tengine\trw\tops\tbatch_size\taverage_commit" | tee "${OUT}/summary.tsv"
    for f in "${OUT}"/*.log; do
      [ -e "$f" ] || continue
      base=$(basename "$f" .log)
      z=$(echo "$base" | sed -E 's/.*zipf_([0-9.]+)$/\1/')
      label="${base%%_p*}"
      rw=$(echo "$base" | sed -E 's/.*_rw([0-9]+)_.*/\1/')
      ops=$(echo "$base" | sed -E 's/.*_ops([0-9]+)_.*/\1/')
      bs=$(echo "$base" | sed -E 's/.*_bs([0-9]+)_.*/\1/')
      avg=$(grep -o "average commit: [0-9.]*" "$f" | tail -1 | awk '{print $3}')
      echo -e "${z}\t${label}\t${rw}\t${ops}\t${bs}\t${avg:-NA}" | tee -a "${OUT}/summary.tsv"
    done
    ;;
  *)
    echo "Usage: $0 [run|summarize]" >&2
    exit 1
    ;;
esac



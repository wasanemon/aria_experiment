#!/usr/bin/env bash
set -euo pipefail

# Convert YCSB log files to CSV.
# Usage:
#   ycsb_logs_to_csv.sh [RESULTS_DIR] [OUT_CSV]
# Defaults:
#   RESULTS_DIR=/home/wasanemon/project/aria_experiment/results_suite
#   OUT_CSV=$RESULTS_DIR/summary.csv

RESULTS_DIR="${1:-/home/wasanemon/project/aria_experiment/results_suite}"
OUT_CSV="${2:-${RESULTS_DIR}/summary.csv}"

mkdir -p "${RESULTS_DIR}"
echo "zipf,engine,read_write_ratio,ops_per_txn,batch_size,threads,partitions,average_commit,total_commit" > "${OUT_CSV}"

shopt -s nullglob
for f in "${RESULTS_DIR}"/*.log; do
  base=$(basename "$f" .log)
  # Expected name pattern: <label>_p<P>_t<T>_rw<RW>_ops<OPS>_zipf_<Z>
  label=$(echo "$base" | cut -d_ -f1)
  parts=$(echo "$base" | sed -E 's/.*_p([0-9]+)_t.*/\1/')
  threads=$(echo "$base" | sed -E 's/.*_t([0-9]+)_rw.*/\1/')
  rw=$(echo "$base" | sed -E 's/.*_rw([0-9]+)_.*/\1/')
  ops=$(echo "$base" | sed -E 's/.*_ops([0-9]+)_.*/\1/')
  bs=$(echo "$base" | sed -E 's/.*_bs([0-9]+)_.*/\1/')
  zipf=$(echo "$base" | sed -E 's/.*zipf_([0-9.]+)$/\1/')

  avg=$(grep -o "average commit: [0-9.]*" "$f" | tail -1 | awk '{print $3}') || avg=""
  total=$(grep -o "total commit: [0-9.]*" "$f" | tail -1 | awk '{print $3}') || total=""
  avg=${avg:-NA}
  total=${total:-NA}

  echo "${zipf},${label},${rw},${ops},${bs},${threads},${parts},${avg},${total}" >> "${OUT_CSV}"
done

echo "Wrote: ${OUT_CSV}"



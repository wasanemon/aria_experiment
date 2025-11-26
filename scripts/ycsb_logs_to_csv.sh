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
  # Expected name pattern: <label>_p<P>_t<T>_rw<RW>_ops<OPS>_bs<BS>_zipf_<Z>
  # label ends before _p<number> (partition count)
  label=$(echo "$base" | sed -E 's/_p[0-9]+_t.*//')
  parts=$(echo "$base" | sed -E 's/.*_p([0-9]+)_t.*/\1/')
  threads=$(echo "$base" | sed -E 's/.*_t([0-9]+)_.*/\1/')
  rw=$(echo "$base" | sed -E 's/.*_rw([0-9]+)_.*/\1/')
  ops=$(echo "$base" | sed -E 's/.*_ops([0-9]+)_.*/\1/')
  bs=$(echo "$base" | sed -E 's/.*_bs([0-9]+)_.*/\1/')
  zipf=$(echo "$base" | sed -E 's/.*zipf_([0-9.]+)$/\1/')

  avg=$(grep -o "average commit: [0-9.eE+\\-]*" "$f" | tail -1 | awk '{print $3}') || avg=""
  total=$(grep -o "total commit: [0-9.eE+\\-]*" "$f" | tail -1 | awk '{print $3}') || total=""
  avg=${avg:-NA}
  total=${total:-NA}

  echo "${zipf},${label},${rw},${ops},${bs},${threads},${parts},${avg},${total}" >> "${OUT_CSV}"
done

# Generate per-condition summaries (skew vs throughput by engine).
COND_DIR="${RESULTS_DIR}/condition_summaries"
rm -rf "${COND_DIR}"
mkdir -p "${COND_DIR}"

SUMMARY_PATH="${OUT_CSV}" CONDITION_DIR="${COND_DIR}" python3 <<'PY'
import csv
import os
from collections import defaultdict

summary_path = os.environ["SUMMARY_PATH"]
condition_dir = os.environ["CONDITION_DIR"]

with open(summary_path, newline="") as f:
    rows = list(csv.DictReader(f))

grouped = defaultdict(list)
for row in rows:
    key = (
        row["read_write_ratio"],
        row["ops_per_txn"],
        row["batch_size"],
        row["threads"],
        row["partitions"],
    )
    grouped[key].append(row)

for key, items in grouped.items():
    rw, ops, bs, threads, parts = key
    per_zipf = defaultdict(dict)
    engines = set()

    for item in items:
        zipf = item["zipf"]
        engines.add(item["engine"])
        per_zipf[zipf][item["engine"]] = item["average_commit"]

    engines = sorted(engines)
    header = ["zipf"] + engines
    rows_out = []
    for zipf in sorted(per_zipf.keys(), key=lambda v: float(v)):
        row = [zipf]
        for engine in engines:
            row.append(per_zipf[zipf].get(engine, "NA"))
        rows_out.append(row)

    filename = f"rw{rw}_ops{ops}_bs{bs}_t{threads}_p{parts}.csv"
    out_path = os.path.join(condition_dir, filename)
    with open(out_path, "w", newline="") as out_f:
        writer = csv.writer(out_f)
        writer.writerow(header)
        writer.writerows(rows_out)

print(f"Wrote condition summaries to {condition_dir}")
PY

echo "Wrote: ${OUT_CSV}"



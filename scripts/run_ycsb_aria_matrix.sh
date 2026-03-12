#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="${1:-help}"

SERVER="${SERVER:-127.0.0.1:10010}"
PARTITIONS="${PARTITIONS:-12}"
KEYS="${KEYS:-40000}"
IO_THREADS="${IO_THREADS:-1}"
CPU_AFFINITY="${CPU_AFFINITY:-true}"
GLOBAL_KEY_SPACE="${GLOBAL_KEY_SPACE:-True}"
CROSS_RATIO="${CROSS_RATIO:-100}"
SKEW_PATTERN="${SKEW_PATTERN:-both}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 8)}"

BUILD_ROOT="${BUILD_ROOT:-${ROOT_DIR}/.experiment_builds/ycsb_aria_matrix}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/results/ycsb_aria_matrix}"

VARIANTS=(current retry-fixed)
ENGINES=(aria ariaer)

THREADS_FULL=(1 2 4 8 16 32 48 62)
ZIPFS_FULL=(0.0 0.2 0.4 0.6 0.8 0.9)
READ_WRITE_FULL=(50 80)
OPS_FULL=(10 100)
BATCH_FULL=(1024 2048 4096)

THREADS_SMOKE=(1)
ZIPFS_SMOKE=(0.0)
READ_WRITE_SMOKE=(50)
OPS_SMOKE=(10)
BATCH_SMOKE=(1024)

usage() {
  cat <<'EOF'
Usage:
  scripts/run_ycsb_aria_matrix.sh smoke
  scripts/run_ycsb_aria_matrix.sh full
  scripts/run_ycsb_aria_matrix.sh build
  scripts/run_ycsb_aria_matrix.sh summarize <run_dir>

What it does:
  - Builds 4 binaries:
    - aria current
    - aria retry-fixed
    - ariaer current
    - ariaer retry-fixed
  - Runs YCSB experiments for the requested matrix
  - Writes logs and summary CSV/TSV files

Environment overrides:
  SERVER, PARTITIONS, KEYS, IO_THREADS, CPU_AFFINITY, JOBS
  BUILD_ROOT, RESULT_ROOT

Notes:
  - retry-fixed means protocol/Aria/Aria.h::abort() sets txn.abort_lock = true;
  - smoke is a tiny pipeline check before the full sweep.
EOF
}

patch_retry_abort() {
  local file_path="$1"
  python3 - "$file_path" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = """  void abort(TransactionType &txn,\n             std::vector<std::unique_ptr<Message>> &messages) {\n    // nothing needs to be done\n  }\n"""
new = """  void abort(TransactionType &txn,\n             std::vector<std::unique_ptr<Message>> &messages) {\n    txn.abort_lock = true;\n  }\n"""
if old not in text:
    raise SystemExit(f"patch target not found in {path}")
path.write_text(text.replace(old, new, 1))
PY
}

prepare_variant() {
  local variant="$1"
  local engine="$2"
  local src_dir="${ROOT_DIR}/${engine}"
  local dst_dir="${BUILD_ROOT}/${variant}/${engine}"

  rm -rf "${dst_dir}"
  mkdir -p "$(dirname "${dst_dir}")"
  cp -a "${src_dir}" "${dst_dir}"

  if [[ "${variant}" == "retry-fixed" ]]; then
    patch_retry_abort "${dst_dir}/protocol/Aria/Aria.h"
  fi

  echo "== build ${engine} (${variant}) =="
  (
    cd "${dst_dir}"
    rm -rf CMakeFiles CMakeCache.txt goo*
    cmake -DCMAKE_BUILD_TYPE=Release .
    make -j"${JOBS}" bench_ycsb
  )
}

build_all() {
  mkdir -p "${BUILD_ROOT}"
  for variant in "${VARIANTS[@]}"; do
    for engine in "${ENGINES[@]}"; do
      prepare_variant "${variant}" "${engine}"
    done
  done
}

select_matrix() {
  case "${MODE}" in
    smoke)
      THREADS=("${THREADS_SMOKE[@]}")
      ZIPFS=("${ZIPFS_SMOKE[@]}")
      READ_WRITES=("${READ_WRITE_SMOKE[@]}")
      OPS=("${OPS_SMOKE[@]}")
      BATCHES=("${BATCH_SMOKE[@]}")
      ;;
    full)
      THREADS=("${THREADS_FULL[@]}")
      ZIPFS=("${ZIPFS_FULL[@]}")
      READ_WRITES=("${READ_WRITE_FULL[@]}")
      OPS=("${OPS_FULL[@]}")
      BATCHES=("${BATCH_FULL[@]}")
      ;;
    *)
      echo "invalid mode for matrix selection: ${MODE}" >&2
      exit 1
      ;;
  esac

  if [[ -n "${THREADS_OVERRIDE:-}" ]]; then
    # shellcheck disable=SC2206
    THREADS=(${THREADS_OVERRIDE})
  fi
}

count_runs() {
  local total=0
  for _variant in "${VARIANTS[@]}"; do
    for _engine in "${ENGINES[@]}"; do
      for _thread in "${THREADS[@]}"; do
        for _zipf in "${ZIPFS[@]}"; do
          for _rw in "${READ_WRITES[@]}"; do
            for _op in "${OPS[@]}"; do
              for _batch in "${BATCHES[@]}"; do
                total=$((total + 1))
              done
            done
          done
        done
      done
    done
  done
  echo "${total}"
}

init_summary_files() {
  mkdir -p "${RUN_DIR}"
  SUMMARY_CSV="${RUN_DIR}/summary.csv"
  SUMMARY_TSV="${RUN_DIR}/summary.tsv"
  cat > "${SUMMARY_CSV}" <<'EOF'
variant,engine,threads,zipf,read_write_ratio,ops_per_txn,batch_size,exit_code,elapsed_sec,average_commit,average_abort,total_commit,log_path
EOF
  printf "variant\tengine\tthreads\tzipf\trw\tops\tbatch_size\texit_code\telapsed_sec\taverage_commit\taverage_abort\ttotal_commit\tlog_path\n" > "${SUMMARY_TSV}"
}

append_summary() {
  local log_path="$1"
  local variant="$2"
  local engine="$3"
  local threads="$4"
  local zipf="$5"
  local rw="$6"
  local ops="$7"
  local batch="$8"
  local exit_code="$9"
  local elapsed_sec="${10}"

  python3 - "${SUMMARY_CSV}" "${SUMMARY_TSV}" "${log_path}" "${variant}" "${engine}" \
    "${threads}" "${zipf}" "${rw}" "${ops}" "${batch}" "${exit_code}" "${elapsed_sec}" <<'PY'
import csv
import re
import sys
from pathlib import Path

summary_csv = Path(sys.argv[1])
summary_tsv = Path(sys.argv[2])
log_path = Path(sys.argv[3])
variant, engine, threads, zipf, rw, ops, batch, exit_code, elapsed = sys.argv[4:]

text = log_path.read_text(errors="replace")

avg_commit_matches = re.findall(r"average commit:\s*([0-9.]+)", text)
avg_abort_matches = re.findall(r"average commit:\s*[0-9.]+\s*abort:\s*([0-9.]+)", text)
total_commit_matches = re.findall(r"total commit:\s*([0-9.]+)", text)

avg_commit = avg_commit_matches[-1] if avg_commit_matches else "NA"
avg_abort = avg_abort_matches[-1] if avg_abort_matches else "NA"
total_commit = total_commit_matches[-1] if total_commit_matches else "NA"

row = [
    variant,
    engine,
    threads,
    zipf,
    rw,
    ops,
    batch,
    exit_code,
    elapsed,
    avg_commit,
    avg_abort,
    total_commit,
    str(log_path),
]

with summary_csv.open("a", newline="") as f:
    csv.writer(f).writerow(row)

with summary_tsv.open("a") as f:
    f.write("\t".join(row) + "\n")
PY
}

run_case() {
  local variant="$1"
  local engine="$2"
  local threads="$3"
  local zipf="$4"
  local rw="$5"
  local ops="$6"
  local batch="$7"

  local bin="${BUILD_ROOT}/${variant}/${engine}/bench_ycsb"
  local tag="${variant}_${engine}_p${PARTITIONS}_t${threads}_k${KEYS}_rw${rw}_ops${ops}_bs${batch}_zipf_${zipf}"
  local log_path="${RUN_DIR}/${tag}.log"

  if [[ ! -x "${bin}" ]]; then
    echo "missing binary: ${bin}" >&2
    exit 1
  fi

  echo "=== ${tag} ==="
  local start_ts
  start_ts="$(date +%s)"

  set +e
  "${bin}" \
    --logtostderr=1 \
    --protocol=Aria \
    --id=0 \
    --servers="${SERVER}" \
    --partition_num="${PARTITIONS}" \
    --threads="${threads}" \
    --io="${IO_THREADS}" \
    --cpu_affinity="${CPU_AFFINITY}" \
    --batch_size="${batch}" \
    --read_write_ratio="${rw}" \
    --read_only_ratio=0 \
    --skew_pattern="${SKEW_PATTERN}" \
    --zipf="${zipf}" \
    --ops_per_txn="${ops}" \
    --keys="${KEYS}" \
    --global_key_space="${GLOBAL_KEY_SPACE}" \
    --cross_ratio="${CROSS_RATIO}" \
    2>&1 | tee "${log_path}"
  local exit_code=${PIPESTATUS[0]}
  set -e

  local end_ts
  end_ts="$(date +%s)"
  local elapsed_sec=$((end_ts - start_ts))

  append_summary "${log_path}" "${variant}" "${engine}" "${threads}" "${zipf}" "${rw}" "${ops}" "${batch}" "${exit_code}" "${elapsed_sec}"
}

run_matrix() {
  select_matrix
  local total_runs
  total_runs="$(count_runs)"
  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  RUN_DIR="${RESULT_ROOT}/${MODE}_${timestamp}"

  init_summary_files

  cat > "${RUN_DIR}/README.txt" <<EOF
mode=${MODE}
server=${SERVER}
partitions=${PARTITIONS}
keys=${KEYS}
io_threads=${IO_THREADS}
cpu_affinity=${CPU_AFFINITY}
global_key_space=${GLOBAL_KEY_SPACE}
cross_ratio=${CROSS_RATIO}
skew_pattern=${SKEW_PATTERN}
threads=${THREADS[*]}
zipfs=${ZIPFS[*]}
read_write_ratios=${READ_WRITES[*]}
ops_per_txn=${OPS[*]}
batch_sizes=${BATCHES[*]}
total_runs=${total_runs}
EOF

  echo "run directory: ${RUN_DIR}"
  echo "total runs: ${total_runs}"

  for variant in "${VARIANTS[@]}"; do
    for engine in "${ENGINES[@]}"; do
      for threads in "${THREADS[@]}"; do
        for zipf in "${ZIPFS[@]}"; do
          for rw in "${READ_WRITES[@]}"; do
            for ops in "${OPS[@]}"; do
              for batch in "${BATCHES[@]}"; do
                run_case "${variant}" "${engine}" "${threads}" "${zipf}" "${rw}" "${ops}" "${batch}"
              done
            done
          done
        done
      done
    done
  done

  echo "done: ${RUN_DIR}"
  echo "summary: ${SUMMARY_CSV}"
}

summarize_existing() {
  local run_dir="${1:-}"
  if [[ -z "${run_dir}" || ! -d "${run_dir}" ]]; then
    echo "Usage: $0 summarize <run_dir>" >&2
    exit 1
  fi

  local summary_csv="${run_dir}/summary_rescanned.csv"
  local summary_tsv="${run_dir}/summary_rescanned.tsv"

  cat > "${summary_csv}" <<'EOF'
variant,engine,threads,zipf,read_write_ratio,ops_per_txn,batch_size,exit_code,elapsed_sec,average_commit,average_abort,total_commit,log_path
EOF
  printf "variant\tengine\tthreads\tzipf\trw\tops\tbatch_size\texit_code\telapsed_sec\taverage_commit\taverage_abort\ttotal_commit\tlog_path\n" > "${summary_tsv}"

  local log_path base variant engine threads zipf rw ops batch
  shopt -s nullglob
  for log_path in "${run_dir}"/*.log; do
    base="$(basename "${log_path}" .log)"
    variant="${base%%_*}"
    engine="$(echo "${base}" | awk -F_ '{print $2}')"
    threads="$(echo "${base}" | sed -E 's/.*_t([0-9]+)_.*/\1/')"
    zipf="$(echo "${base}" | sed -E 's/.*zipf_([0-9.]+)$/\1/')"
    rw="$(echo "${base}" | sed -E 's/.*_rw([0-9]+)_.*/\1/')"
    ops="$(echo "${base}" | sed -E 's/.*_ops([0-9]+)_.*/\1/')"
    batch="$(echo "${base}" | sed -E 's/.*_bs([0-9]+)_.*/\1/')"
    python3 - "${summary_csv}" "${summary_tsv}" "${log_path}" "${variant}" "${engine}" \
      "${threads}" "${zipf}" "${rw}" "${ops}" "${batch}" "NA" "NA" <<'PY'
import csv
import re
import sys
from pathlib import Path

summary_csv = Path(sys.argv[1])
summary_tsv = Path(sys.argv[2])
log_path = Path(sys.argv[3])
variant, engine, threads, zipf, rw, ops, batch, exit_code, elapsed = sys.argv[4:]

text = log_path.read_text(errors="replace")
avg_commit_matches = re.findall(r"average commit:\s*([0-9.]+)", text)
avg_abort_matches = re.findall(r"average commit:\s*[0-9.]+\s*abort:\s*([0-9.]+)", text)
total_commit_matches = re.findall(r"total commit:\s*([0-9.]+)", text)

avg_commit = avg_commit_matches[-1] if avg_commit_matches else "NA"
avg_abort = avg_abort_matches[-1] if avg_abort_matches else "NA"
total_commit = total_commit_matches[-1] if total_commit_matches else "NA"

row = [
    variant,
    engine,
    threads,
    zipf,
    rw,
    ops,
    batch,
    exit_code,
    elapsed,
    avg_commit,
    avg_abort,
    total_commit,
    str(log_path),
]

with summary_csv.open("a", newline="") as f:
    csv.writer(f).writerow(row)

with summary_tsv.open("a") as f:
    f.write("\t".join(row) + "\n")
PY
  done
}

case "${MODE}" in
  smoke|full)
    build_all
    run_matrix
    ;;
  build)
    build_all
    ;;
  summarize)
    summarize_existing "${2:-}"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac

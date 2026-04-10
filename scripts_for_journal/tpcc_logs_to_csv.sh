#!/usr/bin/env bash
set -euo pipefail

# Convert TPCC log files to CSV and plots.
# Usage:
#   tpcc_logs_to_csv.sh [RESULTS_DIR] [OUT_CSV]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_RESULTS_DIR="${ROOT_DIR}/result_tpcc/latest"
RESULTS_DIR="${1:-${DEFAULT_RESULTS_DIR}}"
OUT_CSV="${2:-${RESULTS_DIR}/summary.csv}"

mkdir -p "${RESULTS_DIR}"
echo "query,engine,threads,partitions,batch_size,neworder_dist,payment_dist,n_district,average_commit,total_commit" > "${OUT_CSV}"

shopt -s nullglob
for f in "${RESULTS_DIR}"/*.log; do
  base=$(basename "$f" .log)
  label=$(echo "$base" | sed -E 's/_p[0-9]+_t.*//')
  parts=$(echo "$base" | sed -E 's/.*_p([0-9]+)_.*/\1/')
  threads=$(echo "$base" | sed -E 's/.*_t([0-9]+)_.*/\1/')
  query=$(echo "$base" | sed -E 's/.*_q([a-z]+)_.*/\1/')
  bs=$(echo "$base" | sed -E 's/.*_bs([0-9]+)_.*/\1/')
  nord=$(echo "$base" | sed -E 's/.*_nord([0-9]+)_.*/\1/')
  payd=$(echo "$base" | sed -E 's/.*_payd([0-9]+)_.*/\1/')
  nd=$(echo "$base" | sed -E 's/.*_nd([0-9]+)$/\1/')

  avg=$(grep -o "average commit: [0-9.eE+\\-]*" "$f" | tail -1 | awk '{print $3}') || avg=""
  total=$(grep -o "total commit: [0-9.eE+\\-]*" "$f" | tail -1 | awk '{print $3}') || total=""
  avg=${avg:-NA}
  total=${total:-NA}

  echo "${query},${label},${threads},${parts},${bs},${nord},${payd},${nd},${avg},${total}" >> "${OUT_CSV}"
done
shopt -u nullglob

COND_DIR="${RESULTS_DIR}/condition_summaries"
PLOTS_DIR="${RESULTS_DIR}/plots"
rm -rf "${COND_DIR}" "${PLOTS_DIR}"
mkdir -p "${COND_DIR}" "${PLOTS_DIR}"

SUMMARY_PATH="${OUT_CSV}" CONDITION_DIR="${COND_DIR}" PLOTS_DIR="${PLOTS_DIR}" python3 <<'PY'
import csv
import os
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

summary_path = os.environ["SUMMARY_PATH"]
condition_dir = os.environ["CONDITION_DIR"]
plots_dir = os.environ["PLOTS_DIR"]

ENGINE_DISPLAY = {
    "aria": "Aria",
    "ariaer_cache_fix_v2": "AriaER",
}

COLORS = {
    "Aria": "#1f77b4",
    "AriaER": "#d62728",
}

plt.rcParams.update({
    "font.family": "serif",
    "font.size": 12,
    "axes.labelsize": 14,
    "axes.titlesize": 14,
    "legend.fontsize": 11,
    "xtick.labelsize": 11,
    "ytick.labelsize": 11,
    "figure.figsize": (7, 4.2),
    "figure.dpi": 300,
    "savefig.bbox": "tight",
    "savefig.pad_inches": 0.05,
})


def parse_number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


MARKERS = {
    "Aria": "o",
    "AriaER": "s",
}


def line_chart(title, partitions, series_map, out_path):
    fig, ax = plt.subplots()

    engines = sorted(series_map.keys(), key=lambda e: ENGINE_DISPLAY.get(e, e))
    x = partitions

    for engine in engines:
        display = ENGINE_DISPLAY.get(engine, engine)
        vals = [series_map[engine].get(p) for p in partitions]
        ax.plot(x, vals, label=display,
                color=COLORS.get(display, None),
                marker=MARKERS.get(display, "o"),
                markeredgecolor="white", markeredgewidth=0.8)

    ax.set_xlabel("Number of warehouses (partitions)")
    ax.set_ylabel("Throughput (commits/sec)")
    ax.set_xticks(partitions)
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda v, _: f"{v:,.0f}"))
    ax.legend()
    ax.grid(True, alpha=0.3)

    fig.savefig(out_path)
    plt.close(fig)


with open(summary_path, newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

grouped = defaultdict(list)
for row in rows:
    key = (
        row["batch_size"],
        row["query"],
        row["threads"],
        row["neworder_dist"],
        row["payment_dist"],
        row["n_district"],
    )
    grouped[key].append(row)

for key, items in sorted(grouped.items()):
    bs, query, threads, nord, payd, nd = key

    per_part = defaultdict(dict)
    all_engines = set()
    for item in items:
        p = int(item["partitions"])
        engine = item["engine"]
        avg = parse_number(item["average_commit"])
        per_part[p][engine] = avg
        all_engines.add(engine)

    partitions = sorted(per_part.keys())
    engines = sorted(all_engines)
    display_engines = [ENGINE_DISPLAY.get(e, e) for e in engines]

    header = ["partitions"] + display_engines
    rows_out = []
    series_map = defaultdict(dict)
    for p in partitions:
        row = [str(p)]
        for engine in engines:
            val = per_part[p].get(engine)
            row.append(str(val) if val is not None else "NA")
            series_map[engine][p] = val
        rows_out.append(row)

    stem = f"bs{bs}_q{query}_t{threads}_nord{nord}_payd{payd}_nd{nd}"
    csv_path = os.path.join(condition_dir, f"{stem}.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as out_f:
        writer = csv.writer(out_f)
        writer.writerow(header)
        writer.writerows(rows_out)

    plot_path = os.path.join(plots_dir, f"{stem}.pdf")
    title = (f"TPC-C {query}: batch={bs}, threads={threads}, "
             f"neworder_dist={nord}, payment_dist={payd}, n_district={nd}")
    line_chart(title, partitions, series_map, plot_path)

print(f"Wrote condition summaries to {condition_dir}")
print(f"Wrote plots to {plots_dir}")
PY

echo "Wrote: ${OUT_CSV}"

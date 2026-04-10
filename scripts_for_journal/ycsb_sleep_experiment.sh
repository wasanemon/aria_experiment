#!/usr/bin/env bash
set -euo pipefail

# Sleep experiment: demonstrates AriaER's advantage in skipping
# ReadReservation for WAW-aborted transactions.
#
# The first 25 transactions in the batch all write to the same key.
# The 25th transaction (index 24) sleeps 1 second during ReadReservation.
# In Aria, this sleep occurs every batch (~25 times).
# In AriaER, the sleep only occurs in the batch where the 25th transaction
# finally commits (once), because WAW-aborted txns skip ReadReservation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARIA="${ROOT}/aria_sleep/build/bench_ycsb"
ARIAER="${ROOT}/ariaer_cache_fix_v2_sleep/build/bench_ycsb"
RESULTS_ROOT="${RESULTS_ROOT:-${ROOT}/result_for_journal/ycsb_sleep_experiment}"
RUN_ID="${RUN_ID:-$(date +"%Y%m%d_%H%M%S")}"
OUT="${OUT_DIR:-${RESULTS_ROOT}/${RUN_ID}}"
LATEST_LINK="${RESULTS_ROOT}/latest"

threads=${THREADS:-12}
parts=${PARTITIONS:-12}
keys=${KEYS:-40000}

zipfs=(0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 0.99)
batch_size=1000
rw=80
ops=10

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
  local out_csv="${target_dir}/summary.csv"

  echo "zipf,engine,keys,read_write_ratio,ops_per_txn,batch_size,threads,partitions,average_commit,total_commit" > "${out_csv}"

  shopt -s nullglob
  for f in "${target_dir}"/*.log; do
    base=$(basename "$f" .log)
    label=$(echo "$base" | sed -E 's/_p[0-9]+_t.*//')
    p=$(echo "$base" | sed -E 's/.*_p([0-9]+)_t.*/\1/')
    t=$(echo "$base" | sed -E 's/.*_t([0-9]+)_.*/\1/')
    k=$(echo "$base" | sed -E 's/.*_k([0-9]+)_.*/\1/')
    r=$(echo "$base" | sed -E 's/.*_rw([0-9]+)_.*/\1/')
    o=$(echo "$base" | sed -E 's/.*_ops([0-9]+)_.*/\1/')
    b=$(echo "$base" | sed -E 's/.*_bs([0-9]+)_.*/\1/')
    z=$(echo "$base" | sed -E 's/.*zipf_([0-9.]+)$/\1/')

    avg=$(grep -o "average commit: [0-9.eE+\\-]*" "$f" | tail -1 | awk '{print $3}') || avg=""
    total=$(grep -o "total commit: [0-9.eE+\\-]*" "$f" | tail -1 | awk '{print $3}') || total=""
    avg=${avg:-NA}
    total=${total:-NA}

    echo "${z},${label},${k},${r},${o},${b},${t},${p},${avg},${total}" >> "${out_csv}"
  done
  shopt -u nullglob

  local cond_dir="${target_dir}/condition_summaries"
  local plots_dir="${target_dir}/plots"
  rm -rf "${cond_dir}" "${plots_dir}"
  mkdir -p "${cond_dir}" "${plots_dir}"

  SUMMARY_PATH="${out_csv}" CONDITION_DIR="${cond_dir}" PLOTS_DIR="${plots_dir}" python3 <<'PY'
import csv
import math
import os
from collections import defaultdict
from html import escape

summary_path = os.environ["SUMMARY_PATH"]
condition_dir = os.environ["CONDITION_DIR"]
plots_dir = os.environ["PLOTS_DIR"]

ENGINE_DISPLAY = {
    "ariaer_sleep": "AriaER",
    "aria_sleep": "Aria",
}


def parse_number(value: str):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def format_x_value(value: float):
    if math.isclose(value, round(value)):
        return str(int(round(value)))
    s = f"{value:.2f}".rstrip("0").rstrip(".")
    return s


def svg_chart(title, x_values, series_map, out_path, x_label, y_label="average commit/sec"):
    width = 960
    height = 540
    margin_left = 100
    margin_right = 30
    margin_top = 70
    margin_bottom = 70
    plot_width = width - margin_left - margin_right
    plot_height = height - margin_top - margin_bottom
    colors = [
        "#1f77b4",
        "#d62728",
        "#2ca02c",
        "#9467bd",
        "#ff7f0e",
        "#8c564b",
    ]

    valid_points = [
        y
        for points in series_map.values()
        for (_, y) in points
        if y is not None
    ]
    if not valid_points:
        y_min = 0.0
        y_max = 1.0
    else:
        y_min = min(valid_points)
        y_max = max(valid_points)
        if math.isclose(y_min, y_max):
            y_min = 0.0
            y_max = y_max * 1.1 if y_max else 1.0
        else:
            pad = (y_max - y_min) * 0.1
            y_min = max(0.0, y_min - pad)
            y_max += pad

    x_min = min(x_values) if x_values else 0.0
    x_max = max(x_values) if x_values else 1.0
    if math.isclose(x_min, x_max):
        x_min = 0.0
        x_max = x_max + 1.0

    def sx(x):
        return margin_left + ((x - x_min) / (x_max - x_min)) * plot_width

    def sy(y):
        return margin_top + plot_height - ((y - y_min) / (y_max - y_min)) * plot_height

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<style>',
        'svg { background: #fff; }',
        'text { font-family: Arial, sans-serif; fill: #000; }',
        '.axis { stroke: #333; stroke-width: 1.5; }',
        '.grid { stroke: #ddd; stroke-width: 1; }',
        '.series { fill: none; stroke-width: 2.5; }',
        '.point { stroke: white; stroke-width: 1.5; }',
        '</style>',
        f'<rect x="0" y="0" width="{width}" height="{height}" fill="#fff" />',
    ]

    y_ticks = 5
    for i in range(y_ticks + 1):
        value = y_min + (y_max - y_min) * (i / y_ticks)
        py = sy(value)
        lines.append(f'<line class="grid" x1="{margin_left}" y1="{py:.2f}" x2="{width - margin_right}" y2="{py:.2f}" />')
        lines.append(f'<text x="{margin_left - 10}" y="{py + 4:.2f}" text-anchor="end" font-size="12">{value:,.0f}</text>')

    for x in x_values:
        px = sx(x)
        lines.append(f'<line class="grid" x1="{px:.2f}" y1="{margin_top}" x2="{px:.2f}" y2="{height - margin_bottom}" />')
        lines.append(f'<text x="{px:.2f}" y="{height - margin_bottom + 22}" text-anchor="middle" font-size="12">{escape(format_x_value(x))}</text>')

    lines.extend([
        f'<line class="axis" x1="{margin_left}" y1="{height - margin_bottom}" x2="{width - margin_right}" y2="{height - margin_bottom}" />',
        f'<line class="axis" x1="{margin_left}" y1="{margin_top}" x2="{margin_left}" y2="{height - margin_bottom}" />',
        f'<text x="{width / 2}" y="{height - 18}" text-anchor="middle" font-size="14">{escape(x_label)}</text>',
        f'<text x="24" y="{height / 2}" text-anchor="middle" font-size="14" transform="rotate(-90 24 {height / 2})">{escape(y_label)}</text>',
    ])

    legend_x = width - margin_right - 200
    legend_y = margin_top + 10

    for idx, engine in enumerate(sorted(series_map.keys())):
        color = colors[idx % len(colors)]
        points = sorted(series_map[engine], key=lambda item: item[0])
        drawable = [(sx(x), sy(y)) for x, y in points if y is not None]
        if drawable:
            path = " ".join(
                ("M" if i == 0 else "L") + f" {px:.2f} {py:.2f}"
                for i, (px, py) in enumerate(drawable)
            )
            lines.append(f'<path class="series" stroke="{color}" d="{path}" />')
            for px, py in drawable:
                lines.append(f'<circle class="point" cx="{px:.2f}" cy="{py:.2f}" r="4" fill="{color}" />')

        legend_row = legend_y + idx * 24
        lines.append(f'<line x1="{legend_x}" y1="{legend_row}" x2="{legend_x + 22}" y2="{legend_row}" stroke="{color}" stroke-width="3" />')
        lines.append(f'<text x="{legend_x + 30}" y="{legend_row + 4}" font-size="13">{escape(engine)}</text>')

    lines.append("</svg>")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


# ---- main ----
with open(summary_path, newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

# --- throughput plot ---
key = ("80", "10", "1000", "12", "12", "40000")
series_map = defaultdict(list)
x_values = set()

for row in rows:
    z = parse_number(row["zipf"])
    avg = parse_number(row["average_commit"])
    engine = ENGINE_DISPLAY.get(row["engine"], row["engine"])
    if z is not None:
        x_values.add(z)
        series_map[engine].append((z, avg))

# condition csv
engines = sorted(series_map.keys())
per_x = defaultdict(dict)
for engine, pts in series_map.items():
    for x, y in pts:
        per_x[format_x_value(x)][engine] = y if y is not None else "NA"

csv_path = os.path.join(condition_dir, "sleep_experiment.csv")
with open(csv_path, "w", newline="", encoding="utf-8") as cf:
    writer = csv.writer(cf)
    writer.writerow(["zipf"] + engines)
    for xk in sorted(per_x.keys(), key=float):
        writer.writerow([xk] + [per_x[xk].get(e, "NA") for e in engines])

# throughput SVG
throughput_path = os.path.join(plots_dir, "sleep_throughput.svg")
svg_chart(
    "Sleep Experiment: Throughput (rw=80, ops=10, batch=1000)",
    sorted(x_values), series_map, throughput_path,
    x_label="Zipf coefficient",
    y_label="average commit/sec",
)

# --- ratio plot (AriaER/Aria) ---
aria_map = {}
ariaer_map = {}
for engine, pts in series_map.items():
    for z, y in pts:
        if y is None:
            continue
        if "ariaer" in engine.lower():
            ariaer_map[z] = y
        elif "aria" in engine.lower():
            aria_map[z] = y

ratio_series = defaultdict(list)
ratio_x = set()
for z in sorted(set(aria_map.keys()) & set(ariaer_map.keys())):
    if aria_map[z] and aria_map[z] > 0:
        ratio = ariaer_map[z] / aria_map[z]
        ratio_series["AriaER / Aria"].append((z, ratio))
        ratio_x.add(z)

if ratio_series:
    ratio_path = os.path.join(plots_dir, "sleep_throughput_ratio.svg")
    svg_chart(
        "Sleep Experiment: Throughput Ratio (AriaER / Aria)",
        sorted(ratio_x), ratio_series, ratio_path,
        x_label="Zipf coefficient",
        y_label="throughput ratio",
    )

# index.html
index_path = os.path.join(plots_dir, "index.html")
with open(index_path, "w", encoding="utf-8") as idx:
    idx.write('<!DOCTYPE html>\n<html><head><meta charset="utf-8"><title>Sleep Experiment</title></head><body>\n')
    idx.write("<h1>Sleep Experiment Plots</h1>\n")
    idx.write('<h2>Throughput</h2>\n<img src="sleep_throughput.svg" />\n')
    if ratio_series:
        idx.write('<h2>Throughput Ratio (AriaER / Aria)</h2>\n<img src="sleep_throughput_ratio.svg" />\n')
    idx.write("</body></html>\n")

print(f"Wrote condition summary: {csv_path}")
print(f"Wrote plots to {plots_dir}")
PY

  echo "Wrote: ${out_csv}"
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

case "${1:-run}" in
  run)
    prepare_run_dir
    echo "results directory: ${OUT}"

    failed=0
    run_engine "${ARIA}" "aria_sleep" "Aria" || failed=1
    run_engine "${ARIAER}" "ariaer_sleep" "Aria" || failed=1
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

#!/usr/bin/env bash
set -euo pipefail

# Convert YCSB log files to CSV and plots.
# Usage:
#   ycsb_logs_to_csv.sh [RESULTS_DIR] [OUT_CSV]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [ -e "${ROOT_DIR}/result/latest" ]; then
  DEFAULT_RESULTS_DIR="${ROOT_DIR}/result/latest"
else
  DEFAULT_RESULTS_DIR="${ROOT_DIR}/results_suite/latest"
fi
RESULTS_DIR="${1:-${DEFAULT_RESULTS_DIR}}"
OUT_CSV="${2:-${RESULTS_DIR}/summary.csv}"

mkdir -p "${RESULTS_DIR}"
echo "zipf,engine,keys,read_write_ratio,ops_per_txn,batch_size,threads,partitions,average_commit,total_commit" > "${OUT_CSV}"

shopt -s nullglob
for f in "${RESULTS_DIR}"/*.log; do
  base=$(basename "$f" .log)
  label=$(echo "$base" | sed -E 's/_p[0-9]+_t.*//')
  parts=$(echo "$base" | sed -E 's/.*_p([0-9]+)_t.*/\1/')
  threads=$(echo "$base" | sed -E 's/.*_t([0-9]+)_.*/\1/')
  keys=$(echo "$base" | sed -E 's/.*_k([0-9]+)_.*/\1/')
  rw=$(echo "$base" | sed -E 's/.*_rw([0-9]+)_.*/\1/')
  ops=$(echo "$base" | sed -E 's/.*_ops([0-9]+)_.*/\1/')
  bs=$(echo "$base" | sed -E 's/.*_bs([0-9]+)_.*/\1/')
  zipf=$(echo "$base" | sed -E 's/.*zipf_([0-9.]+)$/\1/')

  avg=$(grep -o "average commit: [0-9.eE+\\-]*" "$f" | tail -1 | awk '{print $3}') || avg=""
  total=$(grep -o "total commit: [0-9.eE+\\-]*" "$f" | tail -1 | awk '{print $3}') || total=""
  avg=${avg:-NA}
  total=${total:-NA}

  echo "${zipf},${label},${keys},${rw},${ops},${bs},${threads},${parts},${avg},${total}" >> "${OUT_CSV}"
done
shopt -u nullglob

COND_DIR="${RESULTS_DIR}/condition_summaries"
PLOTS_DIR="${RESULTS_DIR}/plots"
rm -rf "${COND_DIR}" "${PLOTS_DIR}"
mkdir -p "${COND_DIR}" "${PLOTS_DIR}"

SUMMARY_PATH="${OUT_CSV}" CONDITION_DIR="${COND_DIR}" PLOTS_DIR="${PLOTS_DIR}" python3 <<'PY'
import csv
import math
import os
from collections import defaultdict
from html import escape


summary_path = os.environ["SUMMARY_PATH"]
condition_dir = os.environ["CONDITION_DIR"]
plots_dir = os.environ["PLOTS_DIR"]


def parse_number(value: str):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def svg_chart(title, x_values, series_map, out_path):
    width = 960
    height = 540
    margin_left = 80
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
        f'<text x="{width / 2}" y="32" text-anchor="middle" font-size="20" font-weight="bold">{escape(title)}</text>',
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
        lines.append(f'<text x="{px:.2f}" y="{height - margin_bottom + 22}" text-anchor="middle" font-size="12">{x:.1f}</text>')

    lines.extend([
        f'<line class="axis" x1="{margin_left}" y1="{height - margin_bottom}" x2="{width - margin_right}" y2="{height - margin_bottom}" />',
        f'<line class="axis" x1="{margin_left}" y1="{margin_top}" x2="{margin_left}" y2="{height - margin_bottom}" />',
        f'<text x="{width / 2}" y="{height - 18}" text-anchor="middle" font-size="14">zipf</text>',
        f'<text x="24" y="{height / 2}" text-anchor="middle" font-size="14" transform="rotate(-90 24 {height / 2})">average commit</text>',
    ])

    legend_x = width - margin_right - 180
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


with open(summary_path, newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

grouped = defaultdict(list)
for row in rows:
    key = (
        row["read_write_ratio"],
        row["ops_per_txn"],
        row["batch_size"],
        row["threads"],
        row["partitions"],
        row["keys"],
    )
    grouped[key].append(row)

index_rows = []
for key, items in sorted(grouped.items()):
    rw, ops, bs, threads, parts, keys = key
    per_zipf = defaultdict(dict)
    engines = set()
    x_values = set()
    series_map = defaultdict(list)

    for item in items:
      zipf_value = parse_number(item["zipf"])
      avg_value = parse_number(item["average_commit"])
      engines.add(item["engine"])
      if zipf_value is not None:
          x_values.add(zipf_value)
          per_zipf[f"{zipf_value:.1f}"][item["engine"]] = item["average_commit"]
          series_map[item["engine"]].append((zipf_value, avg_value))

    engines = sorted(engines)
    header = ["zipf"] + engines
    rows_out = []
    for zipf in sorted(per_zipf.keys(), key=float):
        row = [zipf]
        for engine in engines:
            row.append(per_zipf[zipf].get(engine, "NA"))
        rows_out.append(row)

    stem = f"rw{rw}_ops{ops}_bs{bs}_t{threads}_p{parts}_k{keys}"
    csv_path = os.path.join(condition_dir, f"{stem}.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as out_f:
        writer = csv.writer(out_f)
        writer.writerow(header)
        writer.writerows(rows_out)

    plot_filename = f"{stem}.svg"
    plot_path = os.path.join(plots_dir, plot_filename)
    title = f"YCSB average commit: rw={rw}, ops={ops}, batch={bs}, threads={threads}, partitions={parts}, keys={keys}"
    svg_chart(title, sorted(x_values), series_map, plot_path)
    index_rows.append((stem, title, plot_filename))

index_path = os.path.join(plots_dir, "index.html")
with open(index_path, "w", encoding="utf-8") as index_f:
    index_f.write("<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>YCSB plots</title></head><body>\n")
    index_f.write("<h1>YCSB plots</h1>\n<ul>\n")
    for stem, title, plot_filename in index_rows:
        index_f.write(f'<li><a href="{escape(plot_filename)}">{escape(title)}</a></li>\n')
    index_f.write("</ul>\n</body></html>\n")

print(f"Wrote condition summaries to {condition_dir}")
print(f"Wrote plots to {plots_dir}")
PY

echo "Wrote: ${OUT_CSV}"



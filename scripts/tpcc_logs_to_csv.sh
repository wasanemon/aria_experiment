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


def svg_bar_chart(title, categories, series_map, out_path):
    width = 960
    height = 540
    margin_left = 80
    margin_right = 30
    margin_top = 70
    margin_bottom = 90
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

    engines = sorted(series_map.keys())
    valid_points = [
        y
        for points in series_map.values()
        for y in points.values()
        if y is not None
    ]
    y_max = max(valid_points) if valid_points else 1.0
    if math.isclose(y_max, 0.0):
        y_max = 1.0
    else:
        y_max *= 1.1

    def sy(y):
        return margin_top + plot_height - (y / y_max) * plot_height

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<style>',
        'svg { background: #fff; }',
        'text { font-family: Arial, sans-serif; fill: #000; }',
        '.axis { stroke: #333; stroke-width: 1.5; }',
        '.grid { stroke: #ddd; stroke-width: 1; }',
        '</style>',
        f'<rect x="0" y="0" width="{width}" height="{height}" fill="#fff" />',
        f'<text x="{width / 2}" y="32" text-anchor="middle" font-size="20" font-weight="bold">{escape(title)}</text>',
    ]

    y_ticks = 5
    for i in range(y_ticks + 1):
        value = y_max * (i / y_ticks)
        py = sy(value)
        lines.append(f'<line class="grid" x1="{margin_left}" y1="{py:.2f}" x2="{width - margin_right}" y2="{py:.2f}" />')
        lines.append(f'<text x="{margin_left - 10}" y="{py + 4:.2f}" text-anchor="end" font-size="12">{value:,.0f}</text>')

    lines.extend([
        f'<line class="axis" x1="{margin_left}" y1="{height - margin_bottom}" x2="{width - margin_right}" y2="{height - margin_bottom}" />',
        f'<line class="axis" x1="{margin_left}" y1="{margin_top}" x2="{margin_left}" y2="{height - margin_bottom}" />',
        f'<text x="{width / 2}" y="{height - 18}" text-anchor="middle" font-size="14">query</text>',
        f'<text x="24" y="{height / 2}" text-anchor="middle" font-size="14" transform="rotate(-90 24 {height / 2})">average commit</text>',
    ])

    if categories and engines:
        group_width = plot_width / len(categories)
        bar_width = min(48, (group_width * 0.75) / len(engines))
        group_inner = bar_width * len(engines)
        for idx, category in enumerate(categories):
            group_start = margin_left + idx * group_width + (group_width - group_inner) / 2
            center_x = margin_left + idx * group_width + group_width / 2
            lines.append(f'<text x="{center_x:.2f}" y="{height - margin_bottom + 22}" text-anchor="middle" font-size="12">{escape(category)}</text>')
            for engine_idx, engine in enumerate(engines):
                value = series_map[engine].get(category)
                if value is None:
                    continue
                x = group_start + engine_idx * bar_width
                y = sy(value)
                h = margin_top + plot_height - y
                color = colors[engine_idx % len(colors)]
                lines.append(f'<rect x="{x:.2f}" y="{y:.2f}" width="{bar_width - 4:.2f}" height="{h:.2f}" fill="{color}" />')

    legend_x = width - margin_right - 180
    legend_y = margin_top + 10
    for idx, engine in enumerate(engines):
        color = colors[idx % len(colors)]
        legend_row = legend_y + idx * 24
        lines.append(f'<rect x="{legend_x}" y="{legend_row - 8}" width="20" height="12" fill="{color}" />')
        lines.append(f'<text x="{legend_x + 30}" y="{legend_row + 2}" font-size="13">{escape(engine)}</text>')

    lines.append("</svg>")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


with open(summary_path, newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

grouped = defaultdict(list)
for row in rows:
    key = (
        row["threads"],
        row["partitions"],
        row["batch_size"],
        row["neworder_dist"],
        row["payment_dist"],
        row["n_district"],
    )
    grouped[key].append(row)

index_rows = []
for key, items in sorted(grouped.items()):
    threads, parts, bs, nord, payd, nd = key
    per_query = defaultdict(dict)
    engines = set()
    series_map = defaultdict(dict)

    for item in items:
        query = item["query"]
        avg_value = parse_number(item["average_commit"])
        engines.add(item["engine"])
        per_query[query][item["engine"]] = item["average_commit"]
        series_map[item["engine"]][query] = avg_value

    categories = [q for q in ["mixed", "neworder", "payment"] if q in per_query]
    engines = sorted(engines)
    header = ["query"] + engines
    rows_out = []
    for query in categories:
        row = [query]
        for engine in engines:
            row.append(per_query[query].get(engine, "NA"))
        rows_out.append(row)

    stem = f"bs{bs}_t{threads}_p{parts}_nord{nord}_payd{payd}_nd{nd}"
    csv_path = os.path.join(condition_dir, f"{stem}.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as out_f:
        writer = csv.writer(out_f)
        writer.writerow(header)
        writer.writerows(rows_out)

    plot_filename = f"{stem}.svg"
    plot_path = os.path.join(plots_dir, plot_filename)
    title = f"TPCC average commit: batch={bs}, threads={threads}, partitions={parts}, neworder_dist={nord}, payment_dist={payd}, n_district={nd}"
    svg_bar_chart(title, categories, series_map, plot_path)
    index_rows.append((stem, title, plot_filename))

index_path = os.path.join(plots_dir, "index.html")
with open(index_path, "w", encoding="utf-8") as index_f:
    index_f.write("<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>TPCC plots</title></head><body>\n")
    index_f.write("<h1>TPCC plots</h1>\n<ul>\n")
    for stem, title, plot_filename in index_rows:
        index_f.write(f'<li><a href="{escape(plot_filename)}">{escape(title)}</a></li>\n')
    index_f.write("</ul>\n</body></html>\n")

print(f"Wrote condition summaries to {condition_dir}")
print(f"Wrote plots to {plots_dir}")
PY

echo "Wrote: ${OUT_CSV}"

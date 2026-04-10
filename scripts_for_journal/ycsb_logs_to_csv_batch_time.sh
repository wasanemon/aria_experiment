#!/usr/bin/env bash
set -euo pipefail

# Convert YCSB time-experiment logs to CSV and plots.
# Usage:
#   ycsb_logs_to_csv_batch_time.sh [RESULTS_DIR] [OUT_CSV]

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
echo "zipf,engine,keys,read_write_ratio,ops_per_txn,batch_size,threads,partitions,average_batch_time_ms" > "${OUT_CSV}"

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

  avg_batch_ms=$(grep -o "average batch time: [0-9.eE+\\-]*" "$f" | tail -1 | awk '{print $4}') || avg_batch_ms=""
  avg_batch_ms=${avg_batch_ms:-NA}

  echo "${zipf},${label},${keys},${rw},${ops},${bs},${threads},${parts},${avg_batch_ms}" >> "${OUT_CSV}"
done
shopt -u nullglob

COND_DIR="${RESULTS_DIR}/condition_summaries"
PLOTS_DIR="${RESULTS_DIR}/plots"
DIFF_SUMMARIES_DIR="${RESULTS_DIR}/diff_summaries"
DIFF_PLOTS_DIR="${RESULTS_DIR}/diff_plots"
RATIO_SUMMARIES_DIR="${RESULTS_DIR}/ratio_summaries"
RATIO_PLOTS_DIR="${RESULTS_DIR}/ratio_plots"
rm -rf "${COND_DIR}" "${PLOTS_DIR}" "${DIFF_SUMMARIES_DIR}" "${DIFF_PLOTS_DIR}" "${RATIO_SUMMARIES_DIR}" "${RATIO_PLOTS_DIR}"
mkdir -p "${COND_DIR}" "${PLOTS_DIR}" "${DIFF_SUMMARIES_DIR}" "${DIFF_PLOTS_DIR}" "${RATIO_SUMMARIES_DIR}" "${RATIO_PLOTS_DIR}"

SUMMARY_PATH="${OUT_CSV}" CONDITION_DIR="${COND_DIR}" PLOTS_DIR="${PLOTS_DIR}" DIFF_SUMMARIES_DIR="${DIFF_SUMMARIES_DIR}" DIFF_PLOTS_DIR="${DIFF_PLOTS_DIR}" RATIO_SUMMARIES_DIR="${RATIO_SUMMARIES_DIR}" RATIO_PLOTS_DIR="${RATIO_PLOTS_DIR}" python3 <<'PY'
import csv
import math
import os
from collections import defaultdict
from html import escape


summary_path = os.environ["SUMMARY_PATH"]
condition_dir = os.environ["CONDITION_DIR"]
plots_dir = os.environ["PLOTS_DIR"]
diff_summaries_dir = os.environ["DIFF_SUMMARIES_DIR"]
diff_plots_dir = os.environ["DIFF_PLOTS_DIR"]
ratio_summaries_dir = os.environ["RATIO_SUMMARIES_DIR"]
ratio_plots_dir = os.environ["RATIO_PLOTS_DIR"]

ENGINE_DISPLAY = {
    "ariaer_cache_fix_v2_time_experiment": "AriaER",
    "aria_time_experiment": "Aria",
}


def parse_number(value: str):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def format_x_value(value: float):
    if math.isclose(value, round(value)):
        return str(int(round(value)))
    return f"{value:.2f}".rstrip("0").rstrip(".")


def svg_chart(title, x_values, series_map, out_path, y_label="average batch time (ms)"):
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
        "<style>",
        "svg { background: #fff; }",
        "text { font-family: Arial, sans-serif; fill: #000; }",
        ".axis { stroke: #333; stroke-width: 1.5; }",
        ".grid { stroke: #ddd; stroke-width: 1; }",
        ".series { fill: none; stroke-width: 2.5; }",
        ".point { stroke: white; stroke-width: 1.5; }",
        "</style>",
        f'<rect x="0" y="0" width="{width}" height="{height}" fill="#fff" />',
    ]

    y_ticks = 5
    for i in range(y_ticks + 1):
        value = y_min + (y_max - y_min) * (i / y_ticks)
        py = sy(value)
        lines.append(f'<line class="grid" x1="{margin_left}" y1="{py:.2f}" x2="{width - margin_right}" y2="{py:.2f}" />')
        lines.append(f'<text x="{margin_left - 10}" y="{py + 4:.2f}" text-anchor="end" font-size="12">{value:,.2f}</text>')

    for x in x_values:
        px = sx(x)
        lines.append(f'<line class="grid" x1="{px:.2f}" y1="{margin_top}" x2="{px:.2f}" y2="{height - margin_bottom}" />')
        lines.append(f'<text x="{px:.2f}" y="{height - margin_bottom + 22}" text-anchor="middle" font-size="12">{escape(format_x_value(x))}</text>')

    lines.extend([
        f'<line class="axis" x1="{margin_left}" y1="{height - margin_bottom}" x2="{width - margin_right}" y2="{height - margin_bottom}" />',
        f'<line class="axis" x1="{margin_left}" y1="{margin_top}" x2="{margin_left}" y2="{height - margin_bottom}" />',
        f'<text x="{width / 2}" y="{height - 18}" text-anchor="middle" font-size="14">zipf</text>',
        f'<text x="24" y="{height / 2}" text-anchor="middle" font-size="14" transform="rotate(-90 24 {height / 2})">{escape(y_label)}</text>',
    ])

    legend_x = width - margin_right - 220
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


def dual_axis_chart(title, x_values, left_series_map, right_series, left_label, right_label,
                    left_colors, right_color, right_dashed, out_path):
    width = 960
    height = 540
    margin_left = 90
    margin_right = 90
    margin_top = 70
    margin_bottom = 70
    plot_width = width - margin_left - margin_right
    plot_height = height - margin_top - margin_bottom

    left_points = [
        y
        for points in left_series_map.values()
        for (_, y) in points
        if y is not None
    ]
    if not left_points:
        left_min = 0.0
        left_max = 1.0
    else:
        left_min = min(left_points)
        left_max = max(left_points)
        if math.isclose(left_min, left_max):
            left_min = 0.0
            left_max = left_max * 1.1 if left_max else 1.0
        else:
            pad = (left_max - left_min) * 0.1
            left_min = max(0.0, left_min - pad)
            left_max += pad

    right_points = [y for (_, y) in right_series if y is not None]
    if not right_points:
        right_min = 0.0
        right_max = 1.0
    else:
        right_min = min(right_points)
        right_max = max(right_points)
        if math.isclose(right_min, right_max):
            right_min = 0.0
            right_max = right_max * 1.1 if right_max else 1.0
        else:
            pad = (right_max - right_min) * 0.1
            right_min = min(0.0, right_min - pad) if right_min < 0 else max(0.0, right_min - pad)
            right_max += pad

    x_min = min(x_values) if x_values else 0.0
    x_max = max(x_values) if x_values else 1.0
    if math.isclose(x_min, x_max):
        x_min = 0.0
        x_max = x_max + 1.0

    def sx(x):
        return margin_left + ((x - x_min) / (x_max - x_min)) * plot_width

    def sly(y):
        return margin_top + plot_height - ((y - left_min) / (left_max - left_min)) * plot_height

    def sry(y):
        return margin_top + plot_height - ((y - right_min) / (right_max - right_min)) * plot_height

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        "<style>",
        "svg { background: #fff; }",
        "text { font-family: Arial, sans-serif; fill: #000; }",
        ".axis { stroke: #333; stroke-width: 1.5; }",
        ".grid { stroke: #ddd; stroke-width: 1; }",
        ".series { fill: none; stroke-width: 2.5; }",
        ".point { stroke: white; stroke-width: 1.5; }",
        "</style>",
        f'<rect x="0" y="0" width="{width}" height="{height}" fill="#fff" />',
    ]

    y_ticks = 5
    for i in range(y_ticks + 1):
        left_value = left_min + (left_max - left_min) * (i / y_ticks)
        right_value = right_min + (right_max - right_min) * (i / y_ticks)
        py = sly(left_value)
        lines.append(f'<line class="grid" x1="{margin_left}" y1="{py:.2f}" x2="{width - margin_right}" y2="{py:.2f}" />')
        lines.append(f'<text x="{margin_left - 10}" y="{py + 4:.2f}" text-anchor="end" font-size="12">{left_value:,.2f}</text>')
        lines.append(f'<text x="{width - margin_right + 10}" y="{py + 4:.2f}" text-anchor="start" font-size="12">{right_value:,.3f}</text>')

    for x in x_values:
        px = sx(x)
        lines.append(f'<line class="grid" x1="{px:.2f}" y1="{margin_top}" x2="{px:.2f}" y2="{height - margin_bottom}" />')
        lines.append(f'<text x="{px:.2f}" y="{height - margin_bottom + 22}" text-anchor="middle" font-size="12">{escape(format_x_value(x))}</text>')

    lines.extend([
        f'<line class="axis" x1="{margin_left}" y1="{height - margin_bottom}" x2="{width - margin_right}" y2="{height - margin_bottom}" />',
        f'<line class="axis" x1="{margin_left}" y1="{margin_top}" x2="{margin_left}" y2="{height - margin_bottom}" />',
        f'<line class="axis" x1="{width - margin_right}" y1="{margin_top}" x2="{width - margin_right}" y2="{height - margin_bottom}" />',
        f'<text x="{width / 2}" y="{height - 18}" text-anchor="middle" font-size="14">zipf</text>',
        f'<text x="24" y="{height / 2}" text-anchor="middle" font-size="14" transform="rotate(-90 24 {height / 2})">{escape(left_label)}</text>',
        f'<text x="{width - 24}" y="{height / 2}" text-anchor="middle" font-size="14" transform="rotate(90 {width - 24} {height / 2})">{escape(right_label)}</text>',
    ])

    legend_x = width - margin_right - 250
    legend_y = margin_top + 10
    for idx, engine in enumerate(sorted(left_series_map.keys())):
        color = left_colors[idx % len(left_colors)]
        points = sorted(left_series_map[engine], key=lambda item: item[0])
        drawable = [(sx(x), sly(y)) for x, y in points if y is not None]
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

    right_drawable = [(sx(x), sry(y)) for x, y in right_series if y is not None]
    if right_drawable:
        path = " ".join(
            ("M" if i == 0 else "L") + f" {px:.2f} {py:.2f}"
            for i, (px, py) in enumerate(right_drawable)
        )
        dash_attr = ' stroke-dasharray="6 4"' if right_dashed else ""
        lines.append(f'<path class="series" stroke="{right_color}" d="{path}"{dash_attr} />')
        for px, py in right_drawable:
            lines.append(f'<circle class="point" cx="{px:.2f}" cy="{py:.2f}" r="4" fill="{right_color}" />')
        legend_row = legend_y + len(left_series_map) * 24
        dash_attr = ' stroke-dasharray="6 4"' if right_dashed else ""
        lines.append(f'<line x1="{legend_x}" y1="{legend_row}" x2="{legend_x + 22}" y2="{legend_row}" stroke="{right_color}" stroke-width="3"{dash_attr} />')
        lines.append(f'<text x="{legend_x + 30}" y="{legend_row + 4}" font-size="13">{escape(right_label)}</text>')

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
    rw, ops, batch_size, threads, parts, keys = key
    per_zipf = defaultdict(dict)
    engines = set()
    x_values = set()
    series_map = defaultdict(list)

    for item in items:
        zipf_value = parse_number(item["zipf"])
        batch_time_value = parse_number(item["average_batch_time_ms"])
        display_name = ENGINE_DISPLAY.get(item["engine"], item["engine"])
        engines.add(display_name)
        if zipf_value is not None:
            x_values.add(zipf_value)
            per_zipf[format_x_value(zipf_value)][display_name] = item["average_batch_time_ms"]
            series_map[display_name].append((zipf_value, batch_time_value))

    engines = sorted(engines)
    header = ["zipf"] + engines
    rows_out = []
    for zipf in sorted(per_zipf.keys(), key=float):
        row = [zipf]
        for engine in engines:
            row.append(per_zipf[zipf].get(engine, "NA"))
        rows_out.append(row)

    stem = f"rw{rw}_ops{ops}_bs{batch_size}_t{threads}_p{parts}_k{keys}"
    csv_path = os.path.join(condition_dir, f"{stem}.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as out_f:
        writer = csv.writer(out_f)
        writer.writerow(header)
        writer.writerows(rows_out)

    plot_filename = f"{stem}.svg"
    plot_path = os.path.join(plots_dir, plot_filename)
    title = f"YCSB average batch time: rw={rw}, ops={ops}, batch={batch_size}, threads={threads}, partitions={parts}, keys={keys}"
    svg_chart(title, sorted(x_values), series_map, plot_path)
    index_rows.append((stem, title, plot_filename))

    if len(engines) == 2:
        left_engine = engines[0]
        right_engine = engines[1]

        diff_csv_path = os.path.join(diff_summaries_dir, f"{stem}_{left_engine}_minus_{right_engine}.csv")
        ratio_csv_path = os.path.join(ratio_summaries_dir, f"{stem}_{left_engine}_over_{right_engine}.csv")
        diff_svg_path = os.path.join(diff_plots_dir, f"{stem}_{left_engine}_minus_{right_engine}.svg")
        ratio_svg_path = os.path.join(ratio_plots_dir, f"{stem}_{left_engine}_over_{right_engine}.svg")
        dual_svg_path = os.path.join(plots_dir, f"{stem}_with_diff_dual_axis.svg")

        diff_rows = []
        ratio_rows = []
        diff_series = []
        ratio_series = []
        for zipf_value in sorted(x_values):
            left_value = next((y for x, y in series_map[left_engine] if x == zipf_value), None)
            right_value = next((y for x, y in series_map[right_engine] if x == zipf_value), None)
            if left_value is None or right_value is None:
                continue
            diff_value = left_value - right_value
            ratio_value = left_value / right_value if right_value else None
            zipf_label = format_x_value(zipf_value)
            diff_rows.append([zipf_label, left_value, right_value, diff_value])
            ratio_rows.append([zipf_label, left_value, right_value, ratio_value if ratio_value is not None else "NA"])
            diff_series.append((zipf_value, diff_value))
            if ratio_value is not None:
                ratio_series.append((zipf_value, ratio_value))

        with open(diff_csv_path, "w", newline="", encoding="utf-8") as out_f:
            writer = csv.writer(out_f)
            writer.writerow(["zipf", left_engine, right_engine, "time_diff_ms"])
            writer.writerows(diff_rows)

        with open(ratio_csv_path, "w", newline="", encoding="utf-8") as out_f:
            writer = csv.writer(out_f)
            writer.writerow(["zipf", f"{left_engine}_over_{right_engine}"])
            for row in ratio_rows:
                writer.writerow([row[0], row[3]])

        svg_chart(
            f"YCSB batch time ratio: rw={rw}, ops={ops}, batch={batch_size}, threads={threads}, partitions={parts}, keys={keys}",
            sorted(x_values),
            {f"{left_engine}/{right_engine}": ratio_series},
            ratio_svg_path,
            y_label=f"{left_engine}/{right_engine}",
        )

        svg_chart(
            f"YCSB batch time difference: rw={rw}, ops={ops}, batch={batch_size}, threads={threads}, partitions={parts}, keys={keys}",
            sorted(x_values),
            {f"{left_engine}-{right_engine}": diff_series},
            diff_svg_path,
            y_label=f"{left_engine} - {right_engine} batch time (ms)",
        )

        dual_axis_chart(
            title,
            sorted(x_values),
            {left_engine: series_map[left_engine], right_engine: series_map[right_engine]},
            diff_series,
            "average batch time (ms)",
            f"{left_engine} - {right_engine} batch time (ms)",
            ["#1f77b4", "#d62728"],
            "#2ca02c",
            True,
            dual_svg_path,
        )

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

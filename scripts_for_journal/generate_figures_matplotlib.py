#!/usr/bin/env python3
"""Generate all evaluation figures from CSV data using matplotlib.

Outputs publication-quality PDFs directly to aria_journal/figure_pdf_python/.
"""

import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

ROOT = Path(__file__).resolve().parent.parent
FIGURE = ROOT / "aria_journal" / "figure"
RESULT = ROOT / "result_for_journal"
OUT_DIR = ROOT / "aria_journal" / "figure_pdf_python"

ENGINE_DISPLAY = {
    "aria": "Aria",
    "ariaer_cache_fix_v2": "Cantata",
    "aria_time_experiment": "Aria",
    "ariaer_cache_fix_v2_time_experiment": "Cantata",
    "aria_sleep": "Aria",
    "ariaer_sleep": "Cantata",
}

COLORS = {
    "Aria": "#1f77b4",
    "Cantata": "#d62728",
}

MARKERS = {
    "Aria": "o",
    "Cantata": "s",
}

plt.rcParams.update({
    "font.family": "serif",
    "font.size": 12,
    "axes.labelsize": 14,
    "axes.titlesize": 14,
    "legend.fontsize": 11,
    "xtick.labelsize": 11,
    "ytick.labelsize": 11,
    "lines.linewidth": 2,
    "lines.markersize": 6,
    "figure.figsize": (7, 4.2),
    "figure.dpi": 300,
    "savefig.bbox": "tight",
    "savefig.pad_inches": 0.05,
})


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def parse_floats(rows, key):
    return [float(r[key]) for r in rows]


def two_series_plot(csv_path, x_col, engines, x_label, y_label, out_name,
                    y_formatter=None, legend_loc="best", ylim_bottom=None):
    rows = read_csv(csv_path)
    x = parse_floats(rows, x_col)

    fig, ax = plt.subplots()
    for raw_name in engines:
        display = ENGINE_DISPLAY.get(raw_name, raw_name)
        y = parse_floats(rows, raw_name)
        ax.plot(x, y, label=display,
                color=COLORS.get(display, None),
                marker=MARKERS.get(display, "o"),
                markeredgecolor="white", markeredgewidth=0.8)

    ax.set_xlabel(x_label)
    ax.set_ylabel(y_label)
    ax.legend(loc=legend_loc)
    ax.grid(True, alpha=0.3)
    if y_formatter:
        ax.yaxis.set_major_formatter(y_formatter)
    if ylim_bottom is not None:
        ax.set_ylim(bottom=ylim_bottom)

    fig.savefig(OUT_DIR / out_name)
    plt.close(fig)
    print(f"  {out_name}")


def single_series_plot(csv_path, x_col, y_col, x_label, y_label, out_name,
                       label=None, color="#1f77b4"):
    rows = read_csv(csv_path)
    x = parse_floats(rows, x_col)
    y = parse_floats(rows, y_col)

    fig, ax = plt.subplots()
    ax.plot(x, y, color=color, marker="o",
            markeredgecolor="white", markeredgewidth=0.8,
            label=label)
    ax.set_xlabel(x_label)
    ax.set_ylabel(y_label)
    if label:
        ax.legend()
    ax.grid(True, alpha=0.3)

    fig.savefig(OUT_DIR / out_name)
    plt.close(fig)
    print(f"  {out_name}")


# ---------------------------------------------------------------------------

def fig_medium_high():
    """Throughput comparison: rw=80, ops=100, bs=1000 (medium-to-high contention)."""
    csv_path = (FIGURE / "medium_to_high_contention/ycsb_vary_zipf_op_100"
                "/20260319_081820/condition_summaries"
                "/rw80_ops100_bs1000_t12_p12_k40000.csv")
    two_series_plot(
        csv_path, "zipf",
        ["aria", "ariaer_cache_fix_v2"],
        "Zipf coefficient", "Throughput (commits/sec)",
        "medium_high.pdf",
        y_formatter=ticker.FuncFormatter(lambda v, _: f"{v:,.0f}"),
        ylim_bottom=0,
    )


def fig_same_condition():
    """Throughput under the same conditions as the original Aria paper."""
    csv_path = (FIGURE / "same_condition/ycsb_vary_zipf/20260318_162848"
                "/condition_summaries/rw80_ops10_bs1000_t12_p12_k40000.csv")
    two_series_plot(
        csv_path, "zipf",
        ["aria", "ariaer_cache_fix_v2"],
        "Zipf coefficient", "Throughput (commits/sec)",
        "same_condition.pdf",
        y_formatter=ticker.FuncFormatter(lambda v, _: f"{v:,.0f}"),
        ylim_bottom=0,
    )


def fig_vary_batch():
    """Throughput with varying batch size (zipf=0.9)."""
    csv_path = (FIGURE / "vary_batch/ycsb_op_100_vary_zipf_vary_batch"
                "/20260319_084212/condition_summaries"
                "/rw95_ops100_zipf0.9_t12_p12_k40000.csv")
    two_series_plot(
        csv_path, "batch_size",
        ["aria", "ariaer_cache_fix_v2"],
        "Batch size", "Throughput (commits/sec)",
        "vary_batch.pdf",
        y_formatter=ticker.FuncFormatter(lambda v, _: f"{v:,.0f}"),
        ylim_bottom=0,
    )


def fig_vary_batch_ratio():
    """Throughput ratio (Cantata/Aria) as a function of batch size."""
    csv_path = (FIGURE / "vary_batch/ycsb_op_100_vary_zipf_vary_batch_ratio"
                "/rw95_ops100_zipf0.9_t12_p12_k40000/ratio.csv")
    rows = read_csv(csv_path)
    x = parse_floats(rows, "batch_size")
    y = parse_floats(rows, "performance_ratio")

    fig, ax = plt.subplots()
    ax.plot(x, y, color="#9467bd", marker="o",
            markeredgecolor="white", markeredgewidth=0.8)
    ax.set_xlabel("Batch size")
    ax.set_ylabel("Performance ratio (Cantata / Aria)")
    ax.grid(True, alpha=0.3)
    ax.axhline(y=1.0, color="gray", linestyle="--", linewidth=0.8, alpha=0.5)

    fig.savefig(OUT_DIR / "vary_batch_ratio.pdf")
    plt.close(fig)
    print("  vary_batch_ratio.pdf")


def fig_commit_rate():
    """Commit rate (commit / batch_size) comparison across Zipf coefficients."""
    csv_dirs = sorted(
        (RESULT / "ycsb_commit_rate").glob("*/commit_rate.csv")
    )
    if not csv_dirs:
        print("  SKIP: commit_rate.pdf (no CSV found)")
        return
    csv_path = csv_dirs[-1]

    rows = read_csv(csv_path)
    aria_rows = [r for r in rows if r["engine"] == "aria"]
    ariaer_rows = [r for r in rows if r["engine"] == "ariaer_cache_fix_v2"]

    fig, ax = plt.subplots()
    for label, data, display in [
        ("aria", aria_rows, "Aria"),
        ("ariaer_cache_fix_v2", ariaer_rows, "Cantata"),
    ]:
        x = [float(r["zipf"]) for r in data]
        y = [float(r["commit_rate"]) for r in data]
        ax.plot(x, y, label=display,
                color=COLORS.get(display),
                marker=MARKERS.get(display, "o"),
                markeredgecolor="white", markeredgewidth=0.8)

    ax.set_xlabel("Zipf coefficient")
    ax.set_ylabel("Commit rate (commit / batch size)")
    ax.yaxis.set_major_formatter(ticker.PercentFormatter(xmax=1.0))
    ax.legend()
    ax.grid(True, alpha=0.3)

    fig.savefig(OUT_DIR / "commit_rate.pdf")
    plt.close(fig)
    print("  commit_rate.pdf")


def fig_commit_rate_log():
    """Commit rate (log scale) comparison across Zipf coefficients."""
    csv_dirs = sorted(
        (RESULT / "ycsb_commit_rate").glob("*/commit_rate.csv")
    )
    if not csv_dirs:
        print("  SKIP: commit_rate_log.pdf (no CSV found)")
        return
    csv_path = csv_dirs[-1]

    rows = read_csv(csv_path)
    aria_rows = [r for r in rows if r["engine"] == "aria"]
    ariaer_rows = [r for r in rows if r["engine"] == "ariaer_cache_fix_v2"]

    fig, ax = plt.subplots()
    for label, data, display in [
        ("aria", aria_rows, "Aria"),
        ("ariaer_cache_fix_v2", ariaer_rows, "Cantata"),
    ]:
        x = [float(r["zipf"]) for r in data]
        y = [float(r["commit_rate"]) for r in data]
        ax.plot(x, y, label=display,
                color=COLORS.get(display),
                marker=MARKERS.get(display, "o"),
                markeredgecolor="white", markeredgewidth=0.8)

    ax.set_yscale("log")
    ax.set_xlabel("Zipf coefficient")
    ax.set_ylabel("Commit rate (commit / batch size)")
    ax.legend()
    ax.grid(True, alpha=0.3, which="both")

    fig.savefig(OUT_DIR / "commit_rate_log.pdf")
    plt.close(fig)
    print("  commit_rate_log.pdf")


def fig_abort_commit_ratio():
    """Abort/commit ratio comparison across Zipf coefficients."""
    csv_path = (FIGURE / "abort_ratio/ycsb_vary_zipf_op_100_abort_commit"
                "/20260319_081820/abort_commit_ratio.csv")
    two_series_plot(
        csv_path, "zipf",
        ["aria", "ariaer_cache_fix_v2"],
        "Zipf coefficient", "Abort / Commit ratio",
        "abort_commit_ratio.pdf",
    )


def fig_abort_commit_ratio_log():
    """Abort/commit ratio comparison (log scale)."""
    csv_path = (FIGURE / "abort_ratio/ycsb_vary_zipf_op_100_abort_commit"
                "/20260319_081820/abort_commit_ratio.csv")
    rows = read_csv(csv_path)
    x = parse_floats(rows, "zipf")

    fig, ax = plt.subplots()
    for raw_name in ["aria", "ariaer_cache_fix_v2"]:
        display = ENGINE_DISPLAY.get(raw_name, raw_name)
        y = parse_floats(rows, raw_name)
        ax.plot(x, y, label=display,
                color=COLORS.get(display),
                marker=MARKERS.get(display, "o"),
                markeredgecolor="white", markeredgewidth=0.8)

    ax.set_yscale("log")
    ax.set_xlabel("Zipf coefficient")
    ax.set_ylabel("Abort / Commit ratio")
    ax.legend()
    ax.grid(True, alpha=0.3, which="both")

    fig.savefig(OUT_DIR / "abort_commit_ratio_log.pdf")
    plt.close(fig)
    print("  abort_commit_ratio_log.pdf")


def fig_abort_commit_aria_over_ariaer():
    """Ratio of Aria's abort/commit to Cantata's abort/commit."""
    csv_path = (FIGURE / "abort_ratio/ycsb_vary_zipf_op_100_abort_commit"
                "/20260319_081820/abort_commit_aria_over_ariaer.csv")
    single_series_plot(
        csv_path, "zipf", "aria_over_ariaer_abort_commit",
        "Zipf coefficient",
        "Aria / Cantata (abort/commit ratio)",
        "abort_commit_aria_over_ariaer.pdf",
    )


def fig_batch_time():
    """Average execution time per batch."""
    csv_path = (FIGURE / "batch_execution_time/ycsb_vary_zipf_op_100_batch_time"
                "/20260319_212347/condition_summaries"
                "/rw80_ops100_bs1000_t12_p12_k40000.csv")
    two_series_plot(
        csv_path, "zipf",
        ["aria_time_experiment", "ariaer_cache_fix_v2_time_experiment"],
        "Zipf coefficient", "Average batch time (ms)",
        "batch_time.pdf",
    )


def fig_batch_time_diff():
    """Difference in average batch execution time (Aria - Cantata)."""
    csv_path = (FIGURE / "batch_execution_time/ycsb_vary_zipf_op_100_batch_time"
                "/20260319_212347/diff_summaries"
                "/rw80_ops100_bs1000_t12_p12_k40000"
                "_aria_time_experiment_minus_ariaer_cache_fix_v2_time_experiment.csv")
    single_series_plot(
        csv_path, "zipf", "time_diff_ms",
        "Zipf coefficient",
        "Batch time difference: Aria $-$ Cantata (ms)",
        "batch_time_diff.pdf",
        color="#2ca02c",
    )


def fig_batch_time_dual_axis():
    """Batch time (left axis) and time difference (right axis)."""
    cond_csv = (FIGURE / "batch_execution_time/ycsb_vary_zipf_op_100_batch_time"
                "/20260319_212347/condition_summaries"
                "/rw80_ops100_bs1000_t12_p12_k40000.csv")
    diff_csv = (FIGURE / "batch_execution_time/ycsb_vary_zipf_op_100_batch_time"
                "/20260319_212347/diff_summaries"
                "/rw80_ops100_bs1000_t12_p12_k40000"
                "_aria_time_experiment_minus_ariaer_cache_fix_v2_time_experiment.csv")

    cond_rows = read_csv(cond_csv)
    diff_rows = read_csv(diff_csv)

    x = parse_floats(cond_rows, "zipf")
    y_aria = parse_floats(cond_rows, "aria_time_experiment")
    y_ariaer = parse_floats(cond_rows, "ariaer_cache_fix_v2_time_experiment")
    y_diff = parse_floats(diff_rows, "time_diff_ms")

    fig, ax1 = plt.subplots()

    ax1.plot(x, y_aria, label="Aria", color=COLORS["Aria"],
             marker="o", markeredgecolor="white", markeredgewidth=0.8)
    ax1.plot(x, y_ariaer, label="Cantata", color=COLORS["Cantata"],
             marker="s", markeredgecolor="white", markeredgewidth=0.8)
    ax1.set_xlabel("Zipf coefficient")
    ax1.set_ylabel("Average batch time (ms)")
    ax1.grid(True, alpha=0.3)

    ax2 = ax1.twinx()
    ax2.plot(x, y_diff, label="Aria $-$ Cantata", color="#2ca02c",
             marker="^", linestyle="--",
             markeredgecolor="white", markeredgewidth=0.8)
    ax2.set_ylabel("Batch time difference (ms)")

    lines1, labels1 = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, labels1 + labels2, loc="upper left")

    fig.savefig(OUT_DIR / "batch_time_dual_axis.pdf")
    plt.close(fig)
    print("  batch_time_dual_axis.pdf")


def fig_sleep_throughput():
    """Throughput comparison in the sleep experiment."""
    sleep_dirs = sorted(
        (RESULT / "ycsb_sleep_experiment").glob("*/condition_summaries/sleep_experiment.csv")
    )
    if not sleep_dirs:
        print("  SKIP: sleep_throughput.pdf (no CSV found)")
        return
    csv_path = sleep_dirs[-1]

    two_series_plot(
        csv_path, "zipf",
        ["aria_sleep", "ariaer_sleep"],
        "Zipf coefficient", "Throughput (commits/sec)",
        "sleep_throughput.pdf",
        y_formatter=ticker.FuncFormatter(lambda v, _: f"{v:,.0f}"),
        ylim_bottom=0,
    )


def fig_vary_thread():
    """Throughput comparison with varying thread count (zipf=0, ops=100, bs=1000)."""
    csv_dirs = sorted(
        (RESULT / "ycsb_zipf_09_vary_thread_for_journal").glob(
            "*/condition_summaries/rw80_ops100_bs1000_zipf0_p12_k40000.csv"
        )
    )
    if not csv_dirs:
        print("  SKIP: vary_thread.pdf (no CSV found)")
        return
    csv_path = csv_dirs[-1]

    rows = read_csv(csv_path)
    x = parse_floats(rows, "threads")

    fig, ax = plt.subplots()
    for display in ["Aria", "Cantata"]:
        y = parse_floats(rows, display)
        ax.plot(x, y, label=display,
                color=COLORS[display],
                marker=MARKERS[display],
                markeredgecolor="white", markeredgewidth=0.8)

    ax.set_xlabel("Threads")
    ax.set_ylabel("Throughput (commits/sec)")
    ax.set_xticks(x)
    ax.set_xticklabels([str(int(v)) for v in x])
    ax.yaxis.set_major_formatter(
        ticker.FuncFormatter(lambda v, _: f"{v:,.0f}"))
    ax.set_ylim(bottom=0)
    ax.legend()
    ax.grid(True, alpha=0.3)

    fig.savefig(OUT_DIR / "vary_thread.pdf")
    plt.close(fig)
    print("  vary_thread.pdf")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Output directory: {OUT_DIR}\n")

    print("Generating figures:")
    fig_medium_high()
    fig_same_condition()
    fig_vary_batch()
    fig_vary_batch_ratio()
    fig_commit_rate()
    fig_commit_rate_log()
    fig_abort_commit_ratio()
    fig_abort_commit_ratio_log()
    fig_abort_commit_aria_over_ariaer()
    fig_batch_time()
    fig_batch_time_diff()
    fig_batch_time_dual_axis()
    fig_sleep_throughput()
    fig_vary_thread()

    print(f"\nDone. {len(list(OUT_DIR.glob('*.pdf')))} PDFs written to {OUT_DIR}")


if __name__ == "__main__":
    main()

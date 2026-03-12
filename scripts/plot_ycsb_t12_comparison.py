#!/usr/bin/env python3
from __future__ import annotations

import csv
import sys
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt


def load_rows(summary_path: Path) -> list[dict[str, str]]:
    with summary_path.open() as f:
        return list(csv.DictReader(f))


def to_float(value: str) -> float | None:
    if value in ("", "NA", None):
        return None
    return float(value)


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "Usage: plot_ycsb_t12_comparison.py <summary.csv> <output_dir>",
            file=sys.stderr,
        )
        return 1

    summary_path = Path(sys.argv[1]).resolve()
    output_dir = Path(sys.argv[2]).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = load_rows(summary_path)
    rows = [
        r
        for r in rows
        if r["threads"] == "12" and to_float(r["average_commit"]) is not None
    ]

    grouped: dict[tuple[int, int, int], dict[tuple[str, str], list[tuple[float, float]]]] = (
        defaultdict(lambda: defaultdict(list))
    )

    for row in rows:
        key = (
            int(row["read_write_ratio"]),
            int(row["ops_per_txn"]),
            int(row["batch_size"]),
        )
        line_key = (row["variant"], row["engine"])
        grouped[key][line_key].append(
            (float(row["zipf"]), float(row["average_commit"]))
        )

    colors = {
        ("current", "aria"): "#d95f02",
        ("current", "ariaer"): "#1b9e77",
        ("retry-fixed", "aria"): "#7570b3",
        ("retry-fixed", "ariaer"): "#1f78b4",
    }
    labels = {
        ("current", "aria"): "current aria",
        ("current", "ariaer"): "current ariaer",
        ("retry-fixed", "aria"): "retry-fixed aria",
        ("retry-fixed", "ariaer"): "retry-fixed ariaer",
    }
    line_order = [
        ("current", "aria"),
        ("current", "ariaer"),
        ("retry-fixed", "aria"),
        ("retry-fixed", "ariaer"),
    ]

    # Per-condition plots.
    for (rw, ops, batch), series_map in sorted(grouped.items()):
        fig, ax = plt.subplots(figsize=(8, 5))
        for line_key in line_order:
            points = sorted(series_map.get(line_key, []))
            if not points:
                continue
            xs = [p[0] for p in points]
            ys = [p[1] for p in points]
            ax.plot(
                xs,
                ys,
                marker="o",
                linewidth=2,
                color=colors[line_key],
                label=labels[line_key],
            )

        ax.set_title(f"threads=12, rw={rw}:{100-rw}, ops={ops}, batch={batch}")
        ax.set_xlabel("zipf")
        ax.set_ylabel("throughput (average_commit)")
        ax.grid(True, alpha=0.25)
        ax.legend()
        plt.tight_layout()
        out_name = f"t12_rw{rw}_ops{ops}_bs{batch}_zipf_vs_throughput.png"
        plt.savefig(output_dir / out_name, dpi=170)
        plt.close(fig)

    # Overview plot with all conditions.
    all_keys = sorted(grouped.keys())
    fig, axes = plt.subplots(4, 3, figsize=(15, 16), sharex=True)
    axes = axes.flatten()
    for ax, key in zip(axes, all_keys):
        rw, ops, batch = key
        series_map = grouped[key]
        for line_key in line_order:
            points = sorted(series_map.get(line_key, []))
            if not points:
                continue
            xs = [p[0] for p in points]
            ys = [p[1] for p in points]
            ax.plot(
                xs,
                ys,
                marker="o",
                linewidth=2,
                color=colors[line_key],
                label=labels[line_key],
            )
        ax.set_title(f"rw={rw}:{100-rw}, ops={ops}, bs={batch}")
        ax.set_xlabel("zipf")
        ax.set_ylabel("throughput")
        ax.grid(True, alpha=0.25)
        ax.legend(fontsize=8)

    for ax in axes[len(all_keys) :]:
        ax.axis("off")

    plt.tight_layout()
    plt.savefig(output_dir / "overview_t12_zipf_vs_throughput.png", dpi=170)
    plt.close(fig)

    with (output_dir / "README.txt").open("w") as f:
        f.write(f"source_summary={summary_path}\n")
        f.write("description=threads=12, zipf_vs_throughput comparison plots\n")
        f.write("x=zipf\n")
        f.write("y=average_commit\n")
        f.write(
            "lines=current aria,current ariaer,retry-fixed aria,retry-fixed ariaer\n"
        )
        f.write("one_file_per_condition=rw,ops,batch\n")

    print(output_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

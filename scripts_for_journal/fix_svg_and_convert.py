#!/usr/bin/env python3
"""Remove chart titles and rename engine labels in SVG files, then convert to PDF."""

import re
import shutil
import cairosvg
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIGURE = ROOT / "aria_journal" / "figure"
RESULT = ROOT / "result_for_journal"
FIGURE_PDF = ROOT / "aria_journal" / "figure_pdf"

LABEL_MAP = {
    "ariaer_cache_fix_v2_time_experiment": "AriaER",
    "aria_time_experiment": "Aria",
    "ariaer_cache_fix_v2": "AriaER",
    "ariaer_sleep": "AriaER",
    "aria_sleep": "Aria",
    "ariaer": "AriaER",
    "aria": "Aria",
}

SVG_TO_PDF_MAP = {
    FIGURE / "medium_to_high_contention/ycsb_vary_zipf_op_100/20260319_081820/plots/rw80_ops100_bs1000_t12_p12_k40000.svg":
        FIGURE_PDF / "medium_high.pdf",
    FIGURE / "vary_batch/ycsb_op_100_vary_zipf_vary_batch/20260319_084212/plots/rw95_ops100_zipf0.9_t12_p12_k40000.svg":
        FIGURE_PDF / "vary_batch.pdf",
    FIGURE / "vary_batch/ycsb_op_100_vary_zipf_vary_batch_ratio/rw95_ops100_zipf0.9_t12_p12_k40000/ratio.svg":
        FIGURE_PDF / "vary_batch_ratio.pdf",
    FIGURE / "abort_ratio/ycsb_vary_zipf_op_100_abort_commit/20260319_081820/abort_commit_ratio.svg":
        FIGURE_PDF / "abort_commit_ratio.pdf",
    FIGURE / "abort_ratio/ycsb_vary_zipf_op_100_abort_commit/20260319_081820/abort_commit_aria_over_ariaer.svg":
        FIGURE_PDF / "abort_commit_aria_over_ariaer.pdf",
    FIGURE / "batch_execution_time/ycsb_vary_zipf_op_100_batch_time/20260319_212347/plots/rw80_ops100_bs1000_t12_p12_k40000.svg":
        FIGURE_PDF / "batch_time.pdf",
    FIGURE / "batch_execution_time/ycsb_vary_zipf_op_100_batch_time/20260319_212347/diff_plots/rw80_ops100_bs1000_t12_p12_k40000_aria_time_experiment_minus_ariaer_cache_fix_v2_time_experiment.svg":
        FIGURE_PDF / "batch_time_diff.pdf",
    FIGURE / "batch_execution_time/ycsb_vary_zipf_op_100_batch_time/20260319_212347/plots/rw80_ops100_bs1000_t12_p12_k40000_with_diff_dual_axis.svg":
        FIGURE_PDF / "batch_time_dual_axis.pdf",
    FIGURE / "same_condition/ycsb_vary_zipf/20260318_162848/plots/rw80_ops10_bs1000_t12_p12_k40000.svg":
        FIGURE_PDF / "same_condition.pdf",
}

SLEEP_CANDIDATES = sorted(
    (RESULT / "ycsb_sleep_experiment").glob("*/plots/sleep_throughput.svg"),
    key=lambda p: p.parent.parent.name,
)
if SLEEP_CANDIDATES:
    SVG_TO_PDF_MAP[SLEEP_CANDIDATES[-1]] = FIGURE_PDF / "sleep_throughput.pdf"


def remove_title(svg: str) -> str:
    """Remove the <text> element used as chart title (y="32")."""
    return re.sub(
        r'<text [^>]*y="32"[^>]*>[^<]*</text>\n?',
        "",
        svg,
    )


def rename_labels(svg: str) -> str:
    """Rename engine labels in legend text and axis labels, longest match first."""
    for old, new in sorted(LABEL_MAP.items(), key=lambda kv: -len(kv[0])):
        svg = svg.replace(f">{old}<", f">{new}<")
        svg = svg.replace(f">{old} -", f">{new} -")
        svg = svg.replace(f">{old} ", f">{new} ")
        svg = svg.replace(f"- {old} ", f"- {new} ")
        svg = svg.replace(f">{old}-", f">{new}-")
        svg = svg.replace(f"-{old}<", f"-{new}<")
        svg = svg.replace(f">{old}/", f">{new}/")
        svg = svg.replace(f"/{old})", f"/{new})")
        svg = svg.replace(f"/{old}<", f"/{new}<")
        svg = svg.replace(f"({old}/", f"({new}/")
        svg = svg.replace(f"({old})", f"({new})")
    svg = svg.replace("(ariaer/aria)", "(AriaER/Aria)")
    return svg


def reduce_top_margin(svg: str) -> str:
    """Shift plot area up to reclaim space left by the removed title."""
    return svg


def process_svg(src: Path) -> str:
    text = src.read_text(encoding="utf-8")
    text = remove_title(text)
    text = rename_labels(text)
    return text


def main():
    FIGURE_PDF.mkdir(parents=True, exist_ok=True)

    for svg_path, pdf_path in SVG_TO_PDF_MAP.items():
        if not svg_path.exists():
            print(f"SKIP (not found): {svg_path}")
            continue

        modified = process_svg(svg_path)

        tmp_svg = svg_path.with_suffix(".tmp.svg")
        tmp_svg.write_text(modified, encoding="utf-8")

        cairosvg.svg2pdf(url=str(tmp_svg), write_to=str(pdf_path))
        tmp_svg.unlink()

        print(f"OK: {svg_path.name} -> {pdf_path.name}")

    print(f"\nAll PDFs written to {FIGURE_PDF}")


if __name__ == "__main__":
    main()

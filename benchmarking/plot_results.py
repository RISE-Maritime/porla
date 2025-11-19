#!/usr/bin/env python3
"""
Generate ASCII charts from benchmark results.

Reads JSON result files and generates ASCII charts.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import List, Dict, Any

try:
    import plotille
except ImportError:
    print("Error: plotille library not found. Install with: pip install plotille", file=sys.stderr)
    sys.exit(1)


def format_number(num: float, unit: str = "") -> str:
    """Format a number with appropriate precision and unit."""
    if num >= 1_000_000:
        return f"{num / 1_000_000:.1f}M{unit}"
    elif num >= 1_000:
        return f"{num / 1_000:.1f}k{unit}"
    else:
        return f"{num:.1f}{unit}"


def create_horizontal_bar_chart(
    data: Dict[str, float],
    title: str,
    value_label: str = "",
    width: int = 60,
    height: int = None
) -> str:
    """
    Create a horizontal bar chart.

    Args:
        data: Dictionary mapping labels to values
        title: Chart title
        value_label: Unit label for values
        width: Chart width in characters
        height: Chart height (None = auto)

    Returns:
        ASCII chart as string
    """
    if not data:
        return f"{title}\n(No data)"

    # Sort by value descending
    sorted_items = sorted(data.items(), key=lambda x: x[1], reverse=True)
    labels = [item[0] for item in sorted_items]
    values = [item[1] for item in sorted_items]

    # Find max value for scaling
    max_value = max(values)

    # Calculate bar width (reserve space for label and value)
    max_label_len = max(len(label) for label in labels)
    max_value_str_len = max(len(format_number(val, value_label)) for val in values)
    bar_width = width - max_label_len - max_value_str_len - 4  # 4 for spacing

    # Build chart
    lines = [title, "─" * width]

    for label, value in sorted_items:
        # Calculate bar length
        bar_len = int((value / max_value) * bar_width) if max_value > 0 else 0
        bar = "█" * bar_len + "░" * (bar_width - bar_len)
        value_str = format_number(value, value_label)
        line = f"{label:<{max_label_len}} {bar} {value_str:>{max_value_str_len}}"
        lines.append(line)

    return "\n".join(lines)


def create_line_chart(
    data: Dict[str, List[float]],
    title: str,
    x_label: str = "",
    y_label: str = "",
    width: int = 80,
    height: int = 20
) -> str:
    """
    Create a line chart.

    Args:
        data: Dictionary mapping series names to lists of values
        title: Chart title
        x_label: X-axis label
        y_label: Y-axis label
        width: Chart width in characters
        height: Chart height in characters

    Returns:
        ASCII chart as string
    """
    if not data:
        return f"{title}\n(No data)"

    fig = plotille.Figure()
    fig.width = width
    fig.height = height
    fig.x_label = x_label
    fig.y_label = y_label

    for series_name, values in data.items():
        x_values = list(range(len(values)))
        fig.plot(x_values, values, label=series_name)

    chart = fig.show(legend=True)
    return f"{title}\n{chart}"


def plot_throughput_comparison(results_dir: Path, output_file: Path = None) -> str:
    """
    Create throughput comparison chart from benchmark results.

    Args:
        results_dir: Directory containing JSON result files
        output_file: Optional file to write chart to

    Returns:
        Chart as string
    """
    # Load all result files
    results = {}
    for json_file in sorted(results_dir.glob("*.json")):
        scenario_name = json_file.stem
        with open(json_file) as f:
            data = json.load(f)
            if "lines_per_second" in data:
                results[scenario_name] = data["lines_per_second"]

    # Create chart
    chart = create_horizontal_bar_chart(
        results,
        title="Throughput Comparison",
        value_label=" lines/s",
        width=70
    )

    # Save or print
    if output_file:
        output_file.write_text(chart)
        print(f"Chart saved to: {output_file}", file=sys.stderr)

    return chart


def plot_throughput_by_line_length(results_dir: Path, output_file: Path = None) -> str:
    """
    Create chart showing throughput vs line length.

    Expects files named like: baseline_50b.json, baseline_200b.json, etc.

    Args:
        results_dir: Directory containing JSON result files
        output_file: Optional file to write chart to

    Returns:
        Chart as string
    """
    # Load results for different line lengths
    line_lengths = {}

    for json_file in sorted(results_dir.glob("*_*b.json")):
        # Extract line length from filename (e.g., "baseline_50b.json" -> 50)
        parts = json_file.stem.split('_')
        if len(parts) >= 2 and parts[-1].endswith('b'):
            try:
                length = int(parts[-1][:-1])  # Remove 'b' suffix
                with open(json_file) as f:
                    data = json.load(f)
                    if "lines_per_second" in data and "megabytes_per_second" in data:
                        label = f"{length}B"
                        lines_per_sec = data["lines_per_second"]
                        mb_per_sec = data["megabytes_per_second"]
                        line_lengths[label] = (lines_per_sec, mb_per_sec)
            except (ValueError, IndexError):
                continue

    if not line_lengths:
        return "No line length data found"

    # Create two charts: one for lines/s, one with MB/s annotation
    lines_data = {}
    for label, (lines_per_sec, mb_per_sec) in sorted(
        line_lengths.items(),
        key=lambda x: int(x[0][:-1])  # Sort by numeric value
    ):
        lines_data[label] = lines_per_sec

    # Build chart with both metrics
    lines = ["Throughput vs Line Length", "─" * 70]

    max_lines_per_sec = max(lines_data.values())
    bar_width = 40

    for label in sorted(lines_data.keys(), key=lambda x: int(x[:-1])):
        lines_per_sec, mb_per_sec = line_lengths[label]
        bar_len = int((lines_per_sec / max_lines_per_sec) * bar_width)
        bar = "█" * bar_len + "░" * (bar_width - bar_len)

        lines_str = format_number(lines_per_sec, " lines/s")
        mb_str = f"({mb_per_sec:.1f} MB/s)"
        line = f"{label:>6} {bar} {lines_str:>15} {mb_str}"
        lines.append(line)

    chart = "\n".join(lines)

    # Save or print
    if output_file:
        output_file.write_text(chart)
        print(f"Chart saved to: {output_file}", file=sys.stderr)

    return chart


def plot_latency_comparison(results_dir: Path, output_file: Path = None) -> str:
    """
    Create latency comparison chart from benchmark results.

    Args:
        results_dir: Directory containing JSON result files
        output_file: Optional file to write chart to

    Returns:
        Chart as string
    """
    # Load latency results
    results = {}
    for json_file in sorted(results_dir.glob("*latency*.json")):
        scenario_name = json_file.stem.replace("_latency", "")
        with open(json_file) as f:
            data = json.load(f)
            if "latency_milliseconds" in data:
                # Use P95 latency as the main metric
                results[scenario_name] = data["latency_milliseconds"]["p95"]

    if not results:
        return "No latency data found"

    # Create chart
    chart = create_horizontal_bar_chart(
        results,
        title="Latency Comparison (P95)",
        value_label=" ms",
        width=70
    )

    # Save or print
    if output_file:
        output_file.write_text(chart)
        print(f"Chart saved to: {output_file}", file=sys.stderr)

    return chart


def main():
    parser = argparse.ArgumentParser(
        description="Generate ASCII charts from benchmark results"
    )
    parser.add_argument(
        "results_dir",
        type=Path,
        help="Directory containing JSON result files"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Directory to save chart files (default: print to stdout)"
    )
    parser.add_argument(
        "--chart-type",
        choices=["throughput", "line-length", "latency", "all"],
        default="all",
        help="Type of chart to generate (default: all)"
    )

    args = parser.parse_args()

    if not args.results_dir.exists():
        print(f"Error: Results directory not found: {args.results_dir}", file=sys.stderr)
        sys.exit(1)

    # Create output directory if specified
    if args.output_dir:
        args.output_dir.mkdir(parents=True, exist_ok=True)

    # Generate requested charts
    charts = []

    if args.chart_type in ["throughput", "all"]:
        output_file = args.output_dir / "throughput_comparison.txt" if args.output_dir else None
        chart = plot_throughput_comparison(args.results_dir, output_file)
        charts.append(("Throughput Comparison", chart))

    if args.chart_type in ["line-length", "all"]:
        output_file = args.output_dir / "throughput_by_line_length.txt" if args.output_dir else None
        chart = plot_throughput_by_line_length(args.results_dir, output_file)
        charts.append(("Throughput by Line Length", chart))

    if args.chart_type in ["latency", "all"]:
        output_file = args.output_dir / "latency_comparison.txt" if args.output_dir else None
        chart = plot_latency_comparison(args.results_dir, output_file)
        charts.append(("Latency Comparison", chart))

    # Print all charts if not saving to files
    if not args.output_dir:
        for i, (name, chart) in enumerate(charts):
            if i > 0:
                print("\n" + "=" * 70 + "\n")
            print(chart)


if __name__ == "__main__":
    main()

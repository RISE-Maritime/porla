#!/usr/bin/env python3
"""
Measure throughput for porla benchmarking.

Reads lines from stdin and reports throughput statistics.
"""

import argparse
import json
import sys
import time
from typing import Dict, Any


def measure_throughput(
    duration: float = None,
    max_lines: int = None,
    report_interval: float = 1.0
) -> Dict[str, Any]:
    """
    Measure throughput by reading lines from stdin.

    Args:
        duration: Maximum duration in seconds (None = unlimited)
        max_lines: Maximum number of lines to read (None = unlimited)
        report_interval: Interval for progress reporting in seconds

    Returns:
        Dictionary with measurement results
    """
    start_time = time.time()
    last_report = start_time
    line_count = 0
    byte_count = 0

    try:
        for line in sys.stdin:
            line_count += 1
            byte_count += len(line.encode('utf-8'))

            # Check stopping conditions
            if max_lines and line_count >= max_lines:
                break

            current_time = time.time()
            elapsed = current_time - start_time

            if duration and elapsed >= duration:
                break

            # Progress reporting
            if current_time - last_report >= report_interval:
                interim_duration = current_time - start_time
                lines_per_sec = line_count / interim_duration if interim_duration > 0 else 0
                bytes_per_sec = byte_count / interim_duration if interim_duration > 0 else 0
                print(
                    f"Progress: {line_count:,} lines, "
                    f"{lines_per_sec:,.0f} lines/s, "
                    f"{bytes_per_sec / 1024 / 1024:.2f} MB/s",
                    file=sys.stderr
                )
                last_report = current_time

    except KeyboardInterrupt:
        print("\nInterrupted by user", file=sys.stderr)
    except BrokenPipeError:
        # Handle broken pipe gracefully (e.g., when piped to head)
        pass

    end_time = time.time()
    total_duration = end_time - start_time

    # Calculate statistics
    lines_per_sec = line_count / total_duration if total_duration > 0 else 0
    bytes_per_sec = byte_count / total_duration if total_duration > 0 else 0
    mb_per_sec = bytes_per_sec / 1024 / 1024

    results = {
        "line_count": line_count,
        "byte_count": byte_count,
        "duration_seconds": total_duration,
        "lines_per_second": lines_per_sec,
        "bytes_per_second": bytes_per_sec,
        "megabytes_per_second": mb_per_sec,
        "avg_line_length": byte_count / line_count if line_count > 0 else 0
    }

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Measure throughput from stdin"
    )
    parser.add_argument(
        "--duration",
        type=float,
        help="Maximum duration in seconds"
    )
    parser.add_argument(
        "--max-lines",
        type=int,
        help="Maximum number of lines to read"
    )
    parser.add_argument(
        "--report-interval",
        type=float,
        default=1.0,
        help="Progress report interval in seconds (default: 1.0)"
    )
    parser.add_argument(
        "--output",
        help="Output JSON file for results (default: print to stderr)"
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress progress output"
    )

    args = parser.parse_args()

    # Suppress progress if quiet mode
    report_interval = args.report_interval if not args.quiet else float('inf')

    results = measure_throughput(
        duration=args.duration,
        max_lines=args.max_lines,
        report_interval=report_interval
    )

    # Print summary
    if not args.quiet:
        print("\n=== Throughput Results ===", file=sys.stderr)
        print(f"Lines processed: {results['line_count']:,}", file=sys.stderr)
        print(f"Bytes processed: {results['byte_count']:,}", file=sys.stderr)
        print(f"Duration: {results['duration_seconds']:.2f} seconds", file=sys.stderr)
        print(f"Throughput: {results['lines_per_second']:,.0f} lines/s", file=sys.stderr)
        print(f"Throughput: {results['megabytes_per_second']:.2f} MB/s", file=sys.stderr)
        print(f"Avg line length: {results['avg_line_length']:.0f} bytes", file=sys.stderr)

    # Save or print JSON results
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2)
        if not args.quiet:
            print(f"\nResults saved to: {args.output}", file=sys.stderr)
    else:
        print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()

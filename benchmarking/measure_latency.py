#!/usr/bin/env python3
"""
Measure latency for porla benchmarking.

Expects lines with timestamp prefix: "TIMESTAMP|data"
Calculates latency statistics.
"""

import argparse
import json
import sys
import time
from typing import List, Dict, Any
import statistics


def parse_timestamp_line(line: str) -> tuple[float, str]:
    """
    Parse a line with timestamp prefix.

    Args:
        line: Line in format "TIMESTAMP|data"

    Returns:
        Tuple of (timestamp, data)

    Raises:
        ValueError: If line format is invalid
    """
    if '|' not in line:
        raise ValueError(f"Invalid line format (missing '|'): {line[:50]}")

    timestamp_str, data = line.split('|', 1)
    timestamp = float(timestamp_str)
    return timestamp, data


def measure_latency(max_lines: int = None) -> Dict[str, Any]:
    """
    Measure latency by reading timestamped lines from stdin.

    Args:
        max_lines: Maximum number of lines to process

    Returns:
        Dictionary with latency statistics
    """
    latencies: List[float] = []
    line_count = 0
    error_count = 0

    try:
        for line in sys.stdin:
            line = line.rstrip('\n')
            line_count += 1

            try:
                send_time, _ = parse_timestamp_line(line)
                receive_time = time.time()
                latency = receive_time - send_time
                latencies.append(latency)
            except (ValueError, IndexError) as e:
                error_count += 1
                print(f"Warning: Failed to parse line {line_count}: {e}", file=sys.stderr)
                continue

            if max_lines and line_count >= max_lines:
                break

    except KeyboardInterrupt:
        print("\nInterrupted by user", file=sys.stderr)

    # Calculate statistics
    if not latencies:
        return {
            "error": "No valid latency measurements",
            "line_count": line_count,
            "error_count": error_count
        }

    latencies.sort()
    valid_count = len(latencies)

    results = {
        "line_count": line_count,
        "valid_measurements": valid_count,
        "error_count": error_count,
        "latency_seconds": {
            "min": min(latencies),
            "max": max(latencies),
            "mean": statistics.mean(latencies),
            "median": statistics.median(latencies),
            "p95": latencies[int(0.95 * valid_count)] if valid_count > 0 else 0,
            "p99": latencies[int(0.99 * valid_count)] if valid_count > 0 else 0,
            "stddev": statistics.stdev(latencies) if valid_count > 1 else 0
        },
        "latency_milliseconds": {
            "min": min(latencies) * 1000,
            "max": max(latencies) * 1000,
            "mean": statistics.mean(latencies) * 1000,
            "median": statistics.median(latencies) * 1000,
            "p95": latencies[int(0.95 * valid_count)] * 1000 if valid_count > 0 else 0,
            "p99": latencies[int(0.99 * valid_count)] * 1000 if valid_count > 0 else 0,
            "stddev": statistics.stdev(latencies) * 1000 if valid_count > 1 else 0
        }
    }

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Measure latency from timestamped stdin"
    )
    parser.add_argument(
        "--max-lines",
        type=int,
        help="Maximum number of lines to process"
    )
    parser.add_argument(
        "--output",
        help="Output JSON file for results"
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress output"
    )

    args = parser.parse_args()

    results = measure_latency(max_lines=args.max_lines)

    # Check for errors
    if "error" in results:
        print(f"Error: {results['error']}", file=sys.stderr)
        sys.exit(1)

    # Print summary
    if not args.quiet:
        print("\n=== Latency Results ===", file=sys.stderr)
        print(f"Lines processed: {results['line_count']:,}", file=sys.stderr)
        print(f"Valid measurements: {results['valid_measurements']:,}", file=sys.stderr)
        if results['error_count'] > 0:
            print(f"Errors: {results['error_count']:,}", file=sys.stderr)
        print("\nLatency (milliseconds):", file=sys.stderr)
        print(f"  Min:    {results['latency_milliseconds']['min']:.2f} ms", file=sys.stderr)
        print(f"  Median: {results['latency_milliseconds']['median']:.2f} ms", file=sys.stderr)
        print(f"  Mean:   {results['latency_milliseconds']['mean']:.2f} ms", file=sys.stderr)
        print(f"  P95:    {results['latency_milliseconds']['p95']:.2f} ms", file=sys.stderr)
        print(f"  P99:    {results['latency_milliseconds']['p99']:.2f} ms", file=sys.stderr)
        print(f"  Max:    {results['latency_milliseconds']['max']:.2f} ms", file=sys.stderr)
        print(f"  StdDev: {results['latency_milliseconds']['stddev']:.2f} ms", file=sys.stderr)

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

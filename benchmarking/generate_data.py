#!/usr/bin/env python3
"""
Generate test data for porla benchmarking.

Creates files with lines of specified lengths for throughput and latency testing.
"""

import argparse
import random
import string
import sys


def generate_random_line(length: int, include_timestamp: bool = False) -> str:
    """
    Generate a random line of specified length.

    Args:
        length: Target length of the line (excluding newline)
        include_timestamp: If True, prepend a timestamp placeholder

    Returns:
        A string of the specified length
    """
    if include_timestamp:
        # Format: TIMESTAMP|data
        # Reserve space for timestamp: "1234567890.123456|" = 18 chars
        prefix = "XXXXXXXXXX.XXXXXX|"
        data_length = max(1, length - len(prefix))
    else:
        prefix = ""
        data_length = length

    # Generate random alphanumeric data
    chars = string.ascii_letters + string.digits + " "
    data = ''.join(random.choices(chars, k=data_length))

    return prefix + data


def generate_test_file(
    output_file: str,
    line_length: int,
    line_count: int,
    include_timestamp: bool = False,
    seed: int = 42
) -> None:
    """
    Generate a test data file.

    Args:
        output_file: Path to output file
        line_length: Length of each line in bytes
        line_count: Number of lines to generate
        include_timestamp: Include timestamp placeholder for latency tests
        seed: Random seed for reproducibility
    """
    random.seed(seed)

    with open(output_file, 'w') as f:
        for _ in range(line_count):
            line = generate_random_line(line_length, include_timestamp)
            f.write(line + '\n')

    # Report statistics
    total_bytes = line_count * (line_length + 1)  # +1 for newline
    print(f"Generated {output_file}:", file=sys.stderr)
    print(f"  Lines: {line_count:,}", file=sys.stderr)
    print(f"  Line length: {line_length} bytes", file=sys.stderr)
    print(f"  Total size: {total_bytes:,} bytes ({total_bytes / 1024 / 1024:.2f} MB)", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description="Generate test data for porla benchmarking"
    )
    parser.add_argument(
        "output_file",
        help="Output file path"
    )
    parser.add_argument(
        "--line-length",
        type=int,
        default=200,
        help="Length of each line in bytes (default: 200)"
    )
    parser.add_argument(
        "--line-count",
        type=int,
        default=100000,
        help="Number of lines to generate (default: 100000)"
    )
    parser.add_argument(
        "--include-timestamp",
        action="store_true",
        help="Include timestamp placeholder for latency tests"
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility (default: 42)"
    )

    args = parser.parse_args()

    generate_test_file(
        args.output_file,
        args.line_length,
        args.line_count,
        args.include_timestamp,
        args.seed
    )


if __name__ == "__main__":
    main()

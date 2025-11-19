#!/usr/bin/env python3
"""
Inject timestamps into data stream for latency measurement.

Reads lines from stdin, prepends current timestamp, outputs to stdout.
Format: TIMESTAMP|original_line
"""

import sys
import time


def main():
    try:
        for line in sys.stdin:
            line = line.rstrip('\n')
            timestamp = time.time()
            print(f"{timestamp:.6f}|{line}")
            sys.stdout.flush()
    except KeyboardInterrupt:
        pass
    except BrokenPipeError:
        pass


if __name__ == "__main__":
    main()

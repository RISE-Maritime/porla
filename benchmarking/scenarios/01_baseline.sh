#!/bin/bash
#
# Baseline throughput test: to_bus -> from_bus -> measure
#
# Tests raw bus capacity without processing overhead.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
BUS_ID=${BUS_ID:-100}
LINE_LENGTH=${LINE_LENGTH:-200}
LINE_COUNT=${LINE_COUNT:-100000}
DURATION=${DURATION:-30}
TEST_DATA="${BENCH_DIR}/data/test_${LINE_LENGTH}b.txt"
RESULT_FILE="${BENCH_DIR}/results/raw/baseline_${LINE_LENGTH}b.json"

echo "=== Baseline Throughput Test ==="
echo "Bus ID: $BUS_ID"
echo "Line length: $LINE_LENGTH bytes"
echo "Test duration: ${DURATION}s"
echo "Test data: $TEST_DATA"
echo

# Generate test data if needed
if [ ! -f "$TEST_DATA" ]; then
    echo "Generating test data..."
    mkdir -p "$(dirname "$TEST_DATA")"
    python3 "${BENCH_DIR}/generate_data.py" \
        --line-length "$LINE_LENGTH" \
        --line-count "$LINE_COUNT" \
        "$TEST_DATA"
    echo
fi

# Ensure results directory exists
mkdir -p "$(dirname "$RESULT_FILE")"

# Start receiver in background
echo "Starting receiver..."
RECEIVER_PID=""
cleanup() {
    if [ -n "$RECEIVER_PID" ]; then
        kill $RECEIVER_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

from_bus $BUS_ID | \
    python3 "${BENCH_DIR}/measure_throughput.py" \
        --duration "$DURATION" \
        --output "$RESULT_FILE" &
RECEIVER_PID=$!

# Give receiver time to start
sleep 2

# Send data
echo "Sending data..."
cat "$TEST_DATA" | to_bus $BUS_ID

# Wait for measurement to complete
wait $RECEIVER_PID
RECEIVER_PID=""

echo
echo "Results saved to: $RESULT_FILE"
cat "$RESULT_FILE"

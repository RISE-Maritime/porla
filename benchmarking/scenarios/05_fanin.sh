#!/bin/bash
#
# Fan-in test: N writers -> 1 reader
#
# Tests bus contention with multiple concurrent writers.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
BUS_ID=${BUS_ID:-100}
WRITERS=${WRITERS:-4}  # Number of concurrent writers
LINE_LENGTH=${LINE_LENGTH:-200}
LINE_COUNT=${LINE_COUNT:-100000}
DURATION=${DURATION:-30}
TEST_DATA="${BENCH_DIR}/data/test_${LINE_LENGTH}b.txt"
RESULT_FILE="${BENCH_DIR}/results/raw/fanin_${WRITERS}writers_${LINE_LENGTH}b.json"

echo "=== Fan-in Test ==="
echo "Bus ID: $BUS_ID"
echo "Writers: $WRITERS"
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

# Start reader
echo "Starting reader..."
READER_PID=""
cleanup() {
    if [ -n "$READER_PID" ]; then
        kill $READER_PID 2>/dev/null || true
    fi
    # Kill any remaining writer processes
    pkill -P $$ 2>/dev/null || true
}
trap cleanup EXIT

from_bus $BUS_ID | \
    python3 "${BENCH_DIR}/measure_throughput.py" \
        --duration "$DURATION" \
        --output "$RESULT_FILE" &
READER_PID=$!

# Give reader time to start
sleep 2

# Start multiple writers in background
echo "Starting $WRITERS writers..."
WRITER_PIDS=()
for ((i=1; i<=$WRITERS; i++)); do
    echo "  Starting writer $i..."
    (
        # Each writer continuously sends data until reader stops
        while kill -0 $READER_PID 2>/dev/null; do
            cat "$TEST_DATA" | to_bus $BUS_ID
        done
    ) &
    WRITER_PIDS+=($!)
done

# Wait for measurement to complete
wait $READER_PID
READER_PID=""

# Stop all writers
for pid in "${WRITER_PIDS[@]}"; do
    kill $pid 2>/dev/null || true
done

echo
echo "Results saved to: $RESULT_FILE"
cat "$RESULT_FILE"

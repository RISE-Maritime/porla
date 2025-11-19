#!/bin/bash
#
# Multi-stage bus transfer test
#
# Tests throughput through multiple bus hops:
# to_bus 100 -> from_bus 100 -> to_bus 101 -> from_bus 101 -> measure
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
BUS_ID_START=${BUS_ID_START:-100}
STAGES=${STAGES:-2}  # Number of bus hops
LINE_LENGTH=${LINE_LENGTH:-200}
LINE_COUNT=${LINE_COUNT:-100000}
DURATION=${DURATION:-30}
TEST_DATA="${BENCH_DIR}/data/test_${LINE_LENGTH}b.txt"
RESULT_FILE="${BENCH_DIR}/results/raw/multistage_${STAGES}stage_${LINE_LENGTH}b.json"

echo "=== Multi-stage Bus Transfer Test ==="
echo "Starting Bus ID: $BUS_ID_START"
echo "Stages: $STAGES"
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

# Start intermediate stages
STAGE_PIDS=()
cleanup() {
    for pid in "${STAGE_PIDS[@]}"; do
        kill $pid 2>/dev/null || true
    done
}
trap cleanup EXIT

echo "Starting intermediate stages..."
for ((i=0; i<$STAGES-1; i++)); do
    BUS_IN=$((BUS_ID_START + i))
    BUS_OUT=$((BUS_ID_START + i + 1))
    echo "  Stage $((i+1)): bus $BUS_IN -> bus $BUS_OUT"
    from_bus $BUS_IN | to_bus $BUS_OUT &
    STAGE_PIDS+=($!)
done

# Start final receiver
BUS_FINAL=$((BUS_ID_START + STAGES - 1))
echo "Starting final receiver on bus $BUS_FINAL..."
from_bus $BUS_FINAL | \
    python3 "${BENCH_DIR}/measure_throughput.py" \
        --duration "$DURATION" \
        --output "$RESULT_FILE" &
RECEIVER_PID=$!
STAGE_PIDS+=($RECEIVER_PID)

# Give pipeline time to start
sleep 2

# Send data to first bus
echo "Sending data to bus $BUS_ID_START..."
cat "$TEST_DATA" | to_bus $BUS_ID_START

# Wait for measurement to complete
wait $RECEIVER_PID

echo
echo "Results saved to: $RESULT_FILE"
cat "$RESULT_FILE"

#!/bin/bash
#
# Processing pipeline test: to_bus -> from_bus -> processing tools -> measure
#
# Tests throughput with various processing tools in the pipeline.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
BUS_ID=${BUS_ID:-100}
LINE_LENGTH=${LINE_LENGTH:-200}
LINE_COUNT=${LINE_COUNT:-100000}
DURATION=${DURATION:-30}
PIPELINE=${PIPELINE:-"timestamp"}  # Can be: timestamp, jsonify, shuffle, b64, or combinations
TEST_DATA="${BENCH_DIR}/data/test_${LINE_LENGTH}b.txt"
RESULT_FILE="${BENCH_DIR}/results/raw/processing_${PIPELINE}_${LINE_LENGTH}b.json"

echo "=== Processing Pipeline Test ==="
echo "Bus ID: $BUS_ID"
echo "Pipeline: $PIPELINE"
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

# Build pipeline based on configuration
build_pipeline() {
    local pipeline_cmd="cat"

    case "$PIPELINE" in
        timestamp)
            pipeline_cmd="timestamp"
            ;;
        timestamp_jsonify)
            pipeline_cmd="timestamp | jsonify --input-format '{line}' --output-fields line"
            ;;
        timestamp_jsonify_b64)
            pipeline_cmd="timestamp | jsonify --input-format '{line}' --output-fields line | b64 --input-format '{line}' --output-format '{line_b64}'"
            ;;
        full)
            pipeline_cmd="timestamp | jsonify --input-format '{line}' --output-fields line | shuffle --input-format '{\"line\":\"{line}\"}' --output-format '{line}' | b64 --input-format '{line}' --output-format '{line_b64}'"
            ;;
        *)
            pipeline_cmd="$PIPELINE"
            ;;
    esac

    echo "$pipeline_cmd"
}

PIPELINE_CMD=$(build_pipeline)

# Start receiver in background
echo "Starting receiver with pipeline: $PIPELINE_CMD"
RECEIVER_PID=""
cleanup() {
    if [ -n "$RECEIVER_PID" ]; then
        kill $RECEIVER_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

from_bus $BUS_ID | \
    eval "$PIPELINE_CMD" | \
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

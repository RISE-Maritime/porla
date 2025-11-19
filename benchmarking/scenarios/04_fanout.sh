#!/bin/bash
#
# Fan-out test: 1 writer -> N readers
#
# Tests multicast scalability with multiple concurrent readers.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
BUS_ID=${BUS_ID:-100}
READERS=${READERS:-4}  # Number of concurrent readers
LINE_LENGTH=${LINE_LENGTH:-200}
LINE_COUNT=${LINE_COUNT:-100000}
DURATION=${DURATION:-30}
TEST_DATA="${BENCH_DIR}/data/test_${LINE_LENGTH}b.txt"
RESULT_FILE="${BENCH_DIR}/results/raw/fanout_${READERS}readers_${LINE_LENGTH}b.json"

echo "=== Fan-out Test ==="
echo "Bus ID: $BUS_ID"
echo "Readers: $READERS"
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

# Start multiple readers
READER_PIDS=()
cleanup() {
    for pid in "${READER_PIDS[@]}"; do
        kill $pid 2>/dev/null || true
    done
}
trap cleanup EXIT

echo "Starting $READERS readers..."
for ((i=1; i<=$READERS; i++)); do
    READER_RESULT="${BENCH_DIR}/results/raw/fanout_reader${i}_${LINE_LENGTH}b.json"
    echo "  Reader $i -> $READER_RESULT"
    from_bus $BUS_ID | \
        python3 "${BENCH_DIR}/measure_throughput.py" \
            --duration "$DURATION" \
            --output "$READER_RESULT" \
            --quiet &
    READER_PIDS+=($!)
done

# Give readers time to start
sleep 2

# Send data
echo "Sending data..."
START_TIME=$(date +%s)
cat "$TEST_DATA" | to_bus $BUS_ID
END_TIME=$(date +%s)
SEND_DURATION=$((END_TIME - START_TIME))

echo "Data sent in ${SEND_DURATION}s, waiting for readers to finish..."

# Wait for all readers
for pid in "${READER_PIDS[@]}"; do
    wait $pid 2>/dev/null || true
done

# Aggregate results
echo
echo "=== Per-Reader Results ==="
TOTAL_LINES=0
TOTAL_BYTES=0
MIN_LINES_PER_SEC=999999999
MAX_LINES_PER_SEC=0

for ((i=1; i<=$READERS; i++)); do
    READER_RESULT="${BENCH_DIR}/results/raw/fanout_reader${i}_${LINE_LENGTH}b.json"
    if [ -f "$READER_RESULT" ]; then
        LINES=$(jq -r '.line_count' "$READER_RESULT")
        LINES_PER_SEC=$(jq -r '.lines_per_second' "$READER_RESULT")
        echo "Reader $i: $LINES lines, $LINES_PER_SEC lines/s"

        TOTAL_LINES=$((TOTAL_LINES + LINES))
        TOTAL_BYTES=$((TOTAL_BYTES + $(jq -r '.byte_count' "$READER_RESULT")))

        # Track min/max
        if (( $(echo "$LINES_PER_SEC < $MIN_LINES_PER_SEC" | bc -l) )); then
            MIN_LINES_PER_SEC=$LINES_PER_SEC
        fi
        if (( $(echo "$LINES_PER_SEC > $MAX_LINES_PER_SEC" | bc -l) )); then
            MAX_LINES_PER_SEC=$LINES_PER_SEC
        fi
    fi
done

# Create summary result
AVG_LINES_PER_SEC=$(echo "scale=2; $TOTAL_LINES / $DURATION / $READERS" | bc)
TOTAL_LINES_PER_SEC=$(echo "scale=2; $TOTAL_LINES / $DURATION" | bc)

cat > "$RESULT_FILE" <<EOF
{
  "readers": $READERS,
  "total_line_count": $TOTAL_LINES,
  "total_byte_count": $TOTAL_BYTES,
  "duration_seconds": $DURATION,
  "avg_lines_per_second_per_reader": $AVG_LINES_PER_SEC,
  "total_lines_per_second": $TOTAL_LINES_PER_SEC,
  "min_lines_per_second": $MIN_LINES_PER_SEC,
  "max_lines_per_second": $MAX_LINES_PER_SEC
}
EOF

echo
echo "=== Summary ==="
echo "Total lines received (all readers): $TOTAL_LINES"
echo "Average per reader: $AVG_LINES_PER_SEC lines/s"
echo "Total throughput: $TOTAL_LINES_PER_SEC lines/s"
echo
echo "Results saved to: $RESULT_FILE"
cat "$RESULT_FILE"

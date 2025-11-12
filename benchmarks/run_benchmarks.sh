#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Performance Comparison: Python vs Rust ===${NC}\n"

# Use a more reasonable number of lines for actual comparison
NUM_LINES=50000
echo "Creating test data with ${NUM_LINES} lines..."
TEST_DATA=$(mktemp)
for i in $(seq 1 $NUM_LINES); do
    echo "2023-01-01T12:00:00 INFO Message number $i" >> "$TEST_DATA"
done

echo "Test data size: $(du -h "$TEST_DATA" | cut -f1)"
echo ""

# Benchmark timestamp
echo -e "${YELLOW}=== Benchmark 1: timestamp (--epoch) ===${NC}"

echo -e "${GREEN}Python:${NC}"
{ time cat "$TEST_DATA" | ./bin/timestamp --epoch > /dev/null ; } 2>&1 | grep real

echo -e "${GREEN}Rust:${NC}"
{ time cat "$TEST_DATA" | ./target/release/timestamp --epoch > /dev/null ; } 2>&1 | grep real

echo ""

# Benchmark shuffle
echo -e "${YELLOW}=== Benchmark 2: shuffle (pattern transformation) ===${NC}"

echo -e "${GREEN}Python:${NC}"
{ time cat "$TEST_DATA" | ./bin/shuffle '{timestamp} {level} {message}' '{level}: {message}' > /dev/null ; } 2>&1 | grep real

echo -e "${GREEN}Rust:${NC}"
{ time cat "$TEST_DATA" | ./target/release/shuffle '{timestamp} {level} {message}' '{level}: {message}' > /dev/null ; } 2>&1 | grep real

echo ""

# Benchmark jsonify
echo -e "${YELLOW}=== Benchmark 3: jsonify (JSON conversion) ===${NC}"

echo -e "${GREEN}Python:${NC}"
{ time cat "$TEST_DATA" | ./bin/jsonify '{timestamp} {level} {message}' > /dev/null ; } 2>&1 | grep real

echo -e "${GREEN}Rust:${NC}"
{ time cat "$TEST_DATA" | ./target/release/jsonify '{timestamp} {level} {message}' > /dev/null ; } 2>&1 | grep real

echo ""

# Benchmark b64 encode
echo -e "${YELLOW}=== Benchmark 4: b64 (base64 encode) ===${NC}"

# Create simpler test data for b64
B64_DATA=$(mktemp)
for i in $(seq 1 $NUM_LINES); do
    echo "Message number $i with some data to encode" >> "$B64_DATA"
done

echo -e "${GREEN}Python:${NC}"
{ time cat "$B64_DATA" | ./bin/b64 --encode > /dev/null ; } 2>&1 | grep real

echo -e "${GREEN}Rust:${NC}"
{ time cat "$B64_DATA" | ./target/release/b64 --encode > /dev/null ; } 2>&1 | grep real

echo ""

# Benchmark limit
echo -e "${YELLOW}=== Benchmark 5: limit (rate limiting) ===${NC}"
echo "(Testing with 10000 lines and 0.0001s interval)"

LIMIT_DATA=$(mktemp)
for i in $(seq 1 10000); do
    echo "key$((i % 100)) data$i" >> "$LIMIT_DATA"
done

echo -e "${GREEN}Python:${NC}"
{ time cat "$LIMIT_DATA" | ./bin/limit 0.0001 --key '{key} {data}' > /dev/null ; } 2>&1 | grep real

echo -e "${GREEN}Rust:${NC}"
{ time cat "$LIMIT_DATA" | ./target/release/limit 0.0001 --key '{key} {data}' > /dev/null ; } 2>&1 | grep real

echo ""

# Cleanup
rm -f "$TEST_DATA" "$B64_DATA" "$LIMIT_DATA"

echo -e "${BLUE}=== Benchmarks Complete ===${NC}"

#!/bin/bash

set -e

echo "=== Proper Performance Benchmark ==="
echo ""

# Pre-generate test data files to eliminate generation overhead
echo "Generating test data files..."

# 10K lines
seq 1 10000 | awk '{print "2023-01-01T12:00:00 INFO Message number " $1}' > /tmp/test_10k.txt
echo "  10K lines: $(du -h /tmp/test_10k.txt | cut -f1)"

# 50K lines
seq 1 50000 | awk '{print "2023-01-01T12:00:00 INFO Message number " $1}' > /tmp/test_50k.txt
echo "  50K lines: $(du -h /tmp/test_50k.txt | cut -f1)"

# 100K lines
seq 1 100000 | awk '{print "2023-01-01T12:00:00 INFO Message number " $1}' > /tmp/test_100k.txt
echo "  100K lines: $(du -h /tmp/test_100k.txt | cut -f1)"

echo ""

# Function to run benchmark
run_bench() {
    local name=$1
    local cmd=$2
    local input=$3
    local rounds=3

    echo "Testing: $name"

    total_time=0
    for i in $(seq 1 $rounds); do
        start=$(date +%s.%N)
        cat "$input" | eval "$cmd" > /dev/null
        end=$(date +%s.%N)
        elapsed=$(echo "$end - $start" | bc)
        total_time=$(echo "$total_time + $elapsed" | bc)
        echo "  Round $i: ${elapsed}s"
    done

    avg=$(echo "scale=3; $total_time / $rounds" | bc)
    echo "  Average: ${avg}s"
    echo ""
}

# Benchmark 1: timestamp (simple, no pattern matching)
echo "=== Benchmark 1: timestamp (10K lines) ==="
run_bench "Python timestamp" "./bin/timestamp --epoch" "/tmp/test_10k.txt"
run_bench "Rust timestamp" "./target/release/timestamp --epoch" "/tmp/test_10k.txt"

# Benchmark 2: shuffle (pattern matching intensive)
echo "=== Benchmark 2: shuffle (50K lines) ==="
run_bench "Python shuffle" "./bin/shuffle '{timestamp} {level} {message}' '{level}: {message}'" "/tmp/test_50k.txt"
run_bench "Rust shuffle" "./target/release/shuffle '{timestamp} {level} {message}' '{level}: {message}'" "/tmp/test_50k.txt"

# Benchmark 3: jsonify
echo "=== Benchmark 3: jsonify (50K lines) ==="
run_bench "Python jsonify" "./bin/jsonify '{timestamp} {level} {message}'" "/tmp/test_50k.txt"
run_bench "Rust jsonify" "./target/release/jsonify '{timestamp} {level} {message}'" "/tmp/test_50k.txt"

# Benchmark 4: Large dataset test
echo "=== Benchmark 4: shuffle (100K lines - stress test) ==="
run_bench "Python shuffle 100K" "./bin/shuffle '{timestamp} {level} {message}' '{level}: {message}'" "/tmp/test_100k.txt"
run_bench "Rust shuffle 100K" "./target/release/shuffle '{timestamp} {level} {message}' '{level}: {message}'" "/tmp/test_100k.txt"

# Cleanup
rm -f /tmp/test_*.txt

echo "=== Benchmarks Complete ==="

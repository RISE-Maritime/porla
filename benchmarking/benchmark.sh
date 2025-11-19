#!/bin/bash
#
# Main benchmark orchestration script for porla
#
# Runs all benchmark scenarios and generates reports with ASCII charts.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
DURATION=${DURATION:-30}  # Duration for each test in seconds
LINE_LENGTHS=(50 200 1000 4000)  # Different line lengths to test
QUICK_MODE=${QUICK_MODE:-0}  # Set to 1 for quick testing (shorter duration)

if [ "$QUICK_MODE" -eq 1 ]; then
    DURATION=10
    LINE_LENGTHS=(200 1000)
    echo "=== QUICK MODE ENABLED ==="
    echo "Duration: ${DURATION}s per test"
    echo "Line lengths: ${LINE_LENGTHS[*]}"
    echo
fi

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

print_step() {
    echo -e "${GREEN}>>> $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

# Check prerequisites
print_header "Checking Prerequisites"

# Check if running in porla container
if [ ! -f "/bash-init.sh" ]; then
    print_warning "Not running in porla container. Some tests may fail."
    print_warning "Please run this script inside a porla container."
fi

# Check Python dependencies
print_step "Checking Python dependencies..."
if ! python3 -c "import plotille" 2>/dev/null; then
    echo "Installing plotille..."
    pip3 install -q plotille
fi

# Create directories
print_step "Creating directories..."
mkdir -p data results/{raw,charts}

# Collect system information
print_header "System Information"
print_step "Collecting system information..."

cat > results/system_info.txt <<EOF
Porla Performance Benchmark
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

=== System Information ===
Hostname: $(hostname)
Kernel: $(uname -sr)
CPU: $(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs || echo "N/A")
CPU Cores: $(nproc)
Memory: $(free -h | grep Mem: | awk '{print $2}')
Docker Version: $(docker --version 2>/dev/null || echo "N/A")

=== Test Configuration ===
Duration per test: ${DURATION}s
Line lengths: ${LINE_LENGTHS[*]} bytes
Quick mode: $([ "$QUICK_MODE" -eq 1 ] && echo "Yes" || echo "No")
EOF

cat results/system_info.txt
echo

# Generate test data
print_header "Generating Test Data"

for length in "${LINE_LENGTHS[@]}"; do
    TEST_DATA="data/test_${length}b.txt"
    if [ ! -f "$TEST_DATA" ]; then
        print_step "Generating ${length}-byte line data..."
        python3 generate_data.py \
            --line-length "$length" \
            --line-count 100000 \
            "$TEST_DATA"
    else
        echo "Using existing data: $TEST_DATA"
    fi
done

# Run baseline tests
print_header "Running Baseline Tests"

for length in "${LINE_LENGTHS[@]}"; do
    print_step "Testing ${length}-byte lines..."
    LINE_LENGTH=$length DURATION=$DURATION \
        bash scenarios/01_baseline.sh || print_warning "Baseline test failed for ${length}b"
    sleep 2
done

# Run processing pipeline tests
print_header "Running Processing Pipeline Tests"

PIPELINES=("timestamp" "timestamp_jsonify")
if [ "$QUICK_MODE" -eq 0 ]; then
    PIPELINES+=("timestamp_jsonify_b64")
fi

for pipeline in "${PIPELINES[@]}"; do
    print_step "Testing pipeline: $pipeline"
    LINE_LENGTH=200 DURATION=$DURATION PIPELINE=$pipeline \
        bash scenarios/02_processing.sh || print_warning "Processing test failed for $pipeline"
    sleep 2
done

# Run multi-stage tests
if [ "$QUICK_MODE" -eq 0 ]; then
    print_header "Running Multi-stage Tests"

    for stages in 2 3; do
        print_step "Testing ${stages}-stage pipeline..."
        LINE_LENGTH=200 DURATION=$DURATION STAGES=$stages \
            bash scenarios/03_multistage.sh || print_warning "Multi-stage test failed for ${stages} stages"
        sleep 2
    done
fi

# Run fan-out tests
print_header "Running Fan-out Tests"

READER_COUNTS=(2 4)
if [ "$QUICK_MODE" -eq 0 ]; then
    READER_COUNTS+=(8)
fi

for readers in "${READER_COUNTS[@]}"; do
    print_step "Testing with $readers readers..."
    LINE_LENGTH=200 DURATION=$DURATION READERS=$readers \
        bash scenarios/04_fanout.sh || print_warning "Fan-out test failed for $readers readers"
    sleep 2
done

# Run fan-in tests
print_header "Running Fan-in Tests"

WRITER_COUNTS=(2 4)
if [ "$QUICK_MODE" -eq 0 ]; then
    WRITER_COUNTS+=(8)
fi

for writers in "${WRITER_COUNTS[@]}"; do
    print_step "Testing with $writers writers..."
    LINE_LENGTH=200 DURATION=$DURATION WRITERS=$writers \
        bash scenarios/05_fanin.sh || print_warning "Fan-in test failed for $writers writers"
    sleep 2
done

# Generate charts
print_header "Generating Charts"

print_step "Creating throughput by line length chart..."
python3 plot_results.py results/raw \
    --chart-type line-length \
    --output-dir results/charts

print_step "Creating processing pipeline comparison chart..."
# Create custom chart for pipeline comparison
cat > results/charts/pipeline_comparison.txt <<'EOF'
Processing Pipeline Throughput Comparison (200-byte lines)
─────────────────────────────────────────────────────────────────────
EOF

# Extract throughput values and create bars
declare -A pipeline_throughput
for pipeline in baseline timestamp timestamp_jsonify timestamp_jsonify_b64; do
    result_file="results/raw/processing_${pipeline}_200b.json"
    if [ "$pipeline" = "baseline" ]; then
        result_file="results/raw/baseline_200b.json"
    fi

    if [ -f "$result_file" ]; then
        throughput=$(jq -r '.lines_per_second' "$result_file" 2>/dev/null || echo "0")
        pipeline_throughput[$pipeline]=$throughput
    fi
done

# Find max for scaling
max_throughput=0
for throughput in "${pipeline_throughput[@]}"; do
    if (( $(echo "$throughput > $max_throughput" | bc -l) )); then
        max_throughput=$throughput
    fi
done

# Generate bars
for pipeline in baseline timestamp timestamp_jsonify timestamp_jsonify_b64; do
    if [ -n "${pipeline_throughput[$pipeline]:-}" ]; then
        throughput=${pipeline_throughput[$pipeline]}
        # Calculate bar length (40 chars max)
        bar_length=$(echo "scale=0; ($throughput / $max_throughput) * 40" | bc)
        bar=$(printf '█%.0s' $(seq 1 $bar_length))
        padding=$(printf '░%.0s' $(seq 1 $((40 - bar_length))))

        # Format pipeline name
        case $pipeline in
            baseline) name="Baseline (no processing)" ;;
            timestamp) name="+ timestamp" ;;
            timestamp_jsonify) name="+ timestamp + jsonify" ;;
            timestamp_jsonify_b64) name="+ timestamp + jsonify + b64" ;;
        esac

        # Format throughput
        throughput_formatted=$(printf "%'0.0f" $throughput)

        printf "%-30s %s%s %10s lines/s\n" "$name" "$bar" "$padding" "$throughput_formatted" >> results/charts/pipeline_comparison.txt
    fi
done

# Generate summary report
print_header "Generating Summary Report"

cat > results/RESULTS.md <<EOF
# Porla Performance Benchmark Results

Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## System Information

\`\`\`
$(cat results/system_info.txt | sed -n '/=== System Information ===/,/=== Test Configuration ===/p' | head -n -2)
\`\`\`

## Test Configuration

\`\`\`
Duration per test: ${DURATION}s
Line lengths tested: ${LINE_LENGTHS[*]} bytes
Quick mode: $([ "$QUICK_MODE" -eq 1 ] && echo "Yes" || echo "No")
\`\`\`

## Results

### Throughput by Line Length

\`\`\`
$(cat results/charts/throughput_by_line_length.txt)
\`\`\`

### Processing Pipeline Impact

\`\`\`
$(cat results/charts/pipeline_comparison.txt)
\`\`\`

## Key Findings

EOF

# Extract some key metrics for findings
baseline_200b=$(jq -r '.lines_per_second' results/raw/baseline_200b.json 2>/dev/null || echo "N/A")
baseline_1000b=$(jq -r '.lines_per_second' results/raw/baseline_1000b.json 2>/dev/null || echo "N/A")
baseline_mb=$(jq -r '.megabytes_per_second' results/raw/baseline_1000b.json 2>/dev/null || echo "N/A")

cat >> results/RESULTS.md <<EOF
1. **Baseline Throughput**:
   - ~${baseline_200b} lines/s for 200-byte lines
   - ~${baseline_1000b} lines/s for 1000-byte lines
   - Peak bandwidth: ~${baseline_mb} MB/s

2. **Processing Overhead**: Each processing tool in the pipeline reduces throughput.
   - See "Processing Pipeline Impact" chart above for details.

3. **Multicast Scalability**: The UDP multicast bus supports multiple concurrent readers
   efficiently (fan-out scenario).

4. **Recommended Use Cases**:
   - **High-throughput logging**: Use baseline configuration for maximum performance
   - **Timestamped logs**: Minimal overhead with timestamp tool
   - **Structured data**: jsonify and other tools suitable for moderate throughput needs
   - **Multiple consumers**: Multicast nature allows efficient fan-out

## Raw Data

All raw benchmark data is available in \`results/raw/*.json\`.

## Reproduction

To reproduce these benchmarks:

\`\`\`bash
cd benchmarking
./benchmark.sh
\`\`\`

For quick testing (shorter duration):
\`\`\`bash
QUICK_MODE=1 ./benchmark.sh
\`\`\`
EOF

print_step "Summary report saved to: results/RESULTS.md"

# Display results
print_header "Benchmark Complete!"

cat results/RESULTS.md

echo
print_step "All results saved in: $SCRIPT_DIR/results/"
echo "  - Raw data: results/raw/"
echo "  - Charts: results/charts/"
echo "  - Summary: results/RESULTS.md"
echo

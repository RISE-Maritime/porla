# Porla Performance Benchmarking

This directory contains a comprehensive benchmarking suite for measuring porla's performance across various scenarios.

## Overview

The benchmark suite measures:
- **Throughput**: Lines per second and bytes per second
- **Latency**: End-to-end message delay (P50, P95, P99)
- **Scalability**: Fan-out and fan-in performance
- **Processing overhead**: Impact of different processing tools

## Quick Start

### Running All Benchmarks

Run the complete benchmark suite inside a porla container:

```bash
cd benchmarking
./benchmark.sh
```

This will:
1. Generate test data files
2. Run all benchmark scenarios
3. Generate ASCII charts
4. Create a summary report in `results/RESULTS.md`

### Quick Mode

For faster testing (shorter duration, fewer scenarios):

```bash
QUICK_MODE=1 ./benchmark.sh
```

### Running Individual Scenarios

Each scenario can be run independently:

```bash
# Baseline throughput
LINE_LENGTH=200 DURATION=30 bash scenarios/01_baseline.sh

# Processing pipeline
LINE_LENGTH=200 PIPELINE=timestamp bash scenarios/02_processing.sh

# Multi-stage bus transfers
STAGES=2 bash scenarios/03_multistage.sh

# Fan-out (multiple readers)
READERS=4 bash scenarios/04_fanout.sh

# Fan-in (multiple writers)
WRITERS=4 bash scenarios/05_fanin.sh
```

## Benchmark Scenarios

### 1. Baseline Throughput (`01_baseline.sh`)

Measures raw bus capacity without processing overhead.

**Pipeline**: `cat data → to_bus → from_bus → measure`

**Variables**:
- `LINE_LENGTH`: Line size in bytes (default: 200)
- `DURATION`: Test duration in seconds (default: 30)
- `BUS_ID`: Bus ID to use (default: 100)

### 2. Processing Pipeline (`02_processing.sh`)

Measures throughput with various processing tools.

**Pipelines**:
- `timestamp`: Add timestamps only
- `timestamp_jsonify`: Timestamp + JSON conversion
- `timestamp_jsonify_b64`: Full processing chain with base64 encoding

**Variables**:
- `PIPELINE`: Pipeline configuration (default: "timestamp")
- `LINE_LENGTH`: Line size in bytes
- `DURATION`: Test duration in seconds

### 3. Multi-stage Transfers (`03_multistage.sh`)

Tests throughput through multiple bus hops.

**Pipeline**: `to_bus 100 → from_bus 100 → to_bus 101 → from_bus 101 → measure`

**Variables**:
- `STAGES`: Number of bus hops (default: 2)
- `LINE_LENGTH`: Line size in bytes
- `DURATION`: Test duration in seconds

### 4. Fan-out (`04_fanout.sh`)

Tests multicast scalability with multiple concurrent readers.

**Configuration**: 1 writer → N readers

**Variables**:
- `READERS`: Number of concurrent readers (default: 4)
- `LINE_LENGTH`: Line size in bytes
- `DURATION`: Test duration in seconds

### 5. Fan-in (`05_fanin.sh`)

Tests bus contention with multiple concurrent writers.

**Configuration**: N writers → 1 reader

**Variables**:
- `WRITERS`: Number of concurrent writers (default: 4)
- `LINE_LENGTH`: Line size in bytes
- `DURATION`: Test duration in seconds

## Tools

### Data Generation (`generate_data.py`)

Generates test data files with lines of specified length.

```bash
python3 generate_data.py output.txt \
    --line-length 200 \
    --line-count 100000
```

### Throughput Measurement (`measure_throughput.py`)

Measures throughput by reading from stdin.

```bash
cat data.txt | python3 measure_throughput.py \
    --duration 30 \
    --output results.json
```

### Latency Measurement (`measure_latency.py`)

Measures latency from timestamped input.

```bash
cat data.txt | python3 inject_timestamps.py | \
    <pipeline> | \
    python3 measure_latency.py --output latency.json
```

### Chart Generation (`plot_results.py`)

Generates ASCII charts from JSON results.

```bash
python3 plot_results.py results/raw \
    --chart-type all \
    --output-dir results/charts
```

## Results

Benchmark results are saved in the `results/` directory:

```
results/
├── raw/                          # Raw JSON data
│   ├── baseline_200b.json
│   ├── processing_timestamp_200b.json
│   └── ...
├── charts/                       # ASCII charts
│   ├── throughput_comparison.txt
│   └── throughput_by_line_length.txt
├── RESULTS.md                    # Summary report
└── system_info.txt               # System information
```

### Sample Results

```
Throughput vs Line Length (baseline scenario)
──────────────────────────────────────────────────
50B   ███████████████████████████ 100.0k lines/s (5.0 MB/s)
200B  ████████████████████░░░░░░░  65.0k lines/s (13.0 MB/s)
1000B ████████████████░░░░░░░░░░░  50.0k lines/s (50.0 MB/s)
4000B ████████░░░░░░░░░░░░░░░░░░░  25.0k lines/s (100.0 MB/s)
```

## Dependencies

Python packages (installed automatically if needed):
- `plotille>=5.0.0` - ASCII chart generation

## Customization

### Adding New Scenarios

1. Create a new script in `scenarios/`
2. Follow the naming convention: `NN_scenario_name.sh`
3. Save results to `results/raw/scenario_name_*.json`
4. Update `benchmark.sh` to run the new scenario

### Custom Test Data

Generate custom test data with specific characteristics:

```bash
python3 generate_data.py custom_data.txt \
    --line-length 500 \
    --line-count 50000 \
    --seed 123
```

## Interpreting Results

### Throughput Metrics

- **lines_per_second**: Number of complete lines processed per second
- **bytes_per_second**: Raw byte throughput
- **megabytes_per_second**: Throughput in MB/s for easier comparison

### When to Use Different Configurations

- **Baseline**: Maximum throughput for simple logging
- **Timestamp**: Minimal overhead for timestamped logs
- **Processing**: Suitable for moderate throughput with data transformation
- **Multi-stage**: Understand overhead of complex pipeline architectures
- **Fan-out**: Distribute same data to multiple consumers
- **Fan-in**: Aggregate data from multiple sources

## Troubleshooting

### "Not running in porla container"

Make sure to run benchmarks inside a porla container:

```bash
docker run --rm -it \
    --network host \
    -v $(pwd):/workspace \
    -w /workspace \
    porla \
    bash benchmarking/benchmark.sh
```

### Low Performance

- Ensure no other intensive processes are running
- Check system resources (CPU, memory, disk I/O)
- Increase test duration for more stable results
- Run in quick mode first to verify setup

### Missing Dependencies

Install Python dependencies:

```bash
pip3 install -r benchmarking/requirements.txt
```

## Contributing

To improve the benchmark suite:

1. Add new scenarios that test different porla use cases
2. Improve measurement accuracy and reporting
3. Add more visualization options
4. Optimize scenario scripts for better reliability

## License

Same as the main porla project.

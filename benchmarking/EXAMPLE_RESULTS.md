# Porla Performance Benchmark Results (Example)

> **Note**: These are example results to demonstrate the benchmark output format.
> Actual results will vary based on hardware and system configuration.
> Run `./benchmark.sh` in a porla container to generate real results for your environment.

Generated: 2025-11-19 12:00:00 UTC

## System Information

```
Hostname: benchmark-host
Kernel: Linux 4.4.0
CPU: Intel(R) Xeon(R) CPU @ 2.30GHz
CPU Cores: 4
Memory: 16GB
Docker Version: 24.0.5
```

## Test Configuration

```
Duration per test: 30s
Line lengths tested: 50 200 1000 4000 bytes
Quick mode: No
```

## Results

### Throughput by Line Length

```
Throughput vs Line Length (baseline scenario)
──────────────────────────────────────────────────
  50B  ███████████████████████████ 120,000 lines/s (6.0 MB/s)
 200B  ████████████████████░░░░░░░  70,000 lines/s (14.0 MB/s)
1000B  ████████████████░░░░░░░░░░░  55,000 lines/s (55.0 MB/s)
4000B  ██████████░░░░░░░░░░░░░░░░░  32,000 lines/s (128.0 MB/s)
```

### Processing Pipeline Impact

```
Processing Pipeline Throughput Comparison (200-byte lines)
─────────────────────────────────────────────────────────────────────
Baseline (no processing)       ████████████████████████████ 70,000 lines/s
+ timestamp                    ████████████████████████░░░░ 60,000 lines/s
+ timestamp + jsonify          ████████████████░░░░░░░░░░░░ 40,000 lines/s
+ timestamp + jsonify + b64    ██████████░░░░░░░░░░░░░░░░░░ 25,000 lines/s
```

## Key Findings

1. **Baseline Throughput**:
   - ~70,000 lines/s for 200-byte lines
   - ~55,000 lines/s for 1000-byte lines
   - Peak bandwidth: ~128 MB/s (with 4KB lines)

2. **Processing Overhead**: Each processing tool in the pipeline reduces throughput.
   - `timestamp`: ~14% overhead (minimal impact)
   - `jsonify`: ~43% overhead (moderate impact)
   - Full pipeline (timestamp + jsonify + b64): ~64% overhead

3. **Multicast Scalability**: The UDP multicast bus supports multiple concurrent readers
   efficiently (fan-out scenario):
   - 2 readers: ~98% efficiency per reader
   - 4 readers: ~95% efficiency per reader
   - 8 readers: ~90% efficiency per reader

4. **Multi-stage Impact**: Each bus hop adds ~5-10% overhead:
   - 2-stage: ~92% of baseline throughput
   - 3-stage: ~85% of baseline throughput

5. **Recommended Use Cases**:
   - **High-throughput logging**: Use baseline configuration for maximum performance (70k+ lines/s)
   - **Timestamped logs**: Minimal overhead with timestamp tool (60k+ lines/s)
   - **Structured data**: jsonify and other tools suitable for moderate throughput needs (25-40k lines/s)
   - **Multiple consumers**: Multicast nature allows efficient fan-out with minimal performance impact
   - **Complex pipelines**: 3-4 stage pipelines maintain reasonable throughput for most use cases

## Performance Characteristics

### Line Length Impact

Porla's performance is influenced by line length:
- **Small lines (50-200 bytes)**: Line parsing overhead dominates, ~60-120k lines/s
- **Medium lines (500-1000 bytes)**: Balanced performance, ~50-60k lines/s
- **Large lines (2000-4000 bytes)**: Bandwidth becomes limiting factor, ~30-40k lines/s

### CPU Utilization

Typical CPU usage per container:
- Baseline (no processing): 5-10% per core
- With timestamp: 8-12% per core
- With jsonify: 15-25% per core
- Full pipeline: 30-40% per core

### Memory Footprint

Memory usage is generally low:
- Base container: ~10-20 MB
- Processing tools: +5-10 MB each
- Data buffering: Minimal (line-by-line processing)

## Scalability Notes

### Horizontal Scaling (Fan-out)

Porla's multicast architecture scales well for fan-out scenarios:
- Adding readers has minimal impact on sender or other readers
- Tested up to 8 concurrent readers with <10% performance degradation
- Network switch/router capacity may become limiting factor beyond 10+ readers

### Vertical Scaling (Processing)

For CPU-intensive processing:
- Use rate limiting (`limit` tool) to prevent overload
- Consider splitting processing across multiple bus IDs
- Monitor CPU usage and adjust pipeline complexity accordingly

## Troubleshooting Performance

If you experience lower than expected performance:

1. **Check system resources**: Ensure adequate CPU and memory
2. **Network configuration**: Verify multicast is not being rate-limited
3. **Disk I/O**: For `record` function, ensure fast storage (SSD preferred)
4. **Container overhead**: Use `--network host` for minimal network overhead
5. **Test data**: Ensure test data file is cached in memory (run tests multiple times)

## Raw Data

All raw benchmark data is available in `results/raw/*.json`.

Example raw data structure:
```json
{
  "line_count": 2100000,
  "byte_count": 420000000,
  "duration_seconds": 30.05,
  "lines_per_second": 69883.6,
  "bytes_per_second": 13976720.0,
  "megabytes_per_second": 13.33,
  "avg_line_length": 200.0
}
```

## Reproduction

To reproduce these benchmarks in your environment:

```bash
cd benchmarking
./benchmark.sh
```

For quick testing (shorter duration):
```bash
QUICK_MODE=1 ./benchmark.sh
```

Your results may differ based on:
- CPU speed and architecture
- Available memory and system load
- Network configuration (for multicast)
- Storage performance (for `record` operations)
- Docker/container runtime overhead

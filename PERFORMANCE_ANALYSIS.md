# Performance Analysis: Python vs Rust Bin Scripts

## Executive Summary

The Rust implementations are **2-4x faster** than Python when properly optimized. Initial benchmarks showed Python as faster due to a **critical bug in the gullwing crate** that recompiles regex patterns on every parse.

## Benchmark Results (50,000 lines)

### With Optimized Rust (Direct Regex)

| Tool | Python | Rust (Optimized) | Speedup |
|------|--------|------------------|---------|
| **timestamp** | 0.205s | 0.107s | **1.9x faster** ✅ |
| **shuffle** | 0.517s | 0.158s | **3.3x faster** ✅ |

### With Gullwing Library (Buggy)

| Tool | Python | Rust (Gullwing) | Performance |
|------|--------|-----------------|-------------|
| shuffle | 0.517s | 3.086s | **6x slower** ❌ |
| jsonify | 0.643s | 3.234s | **5x slower** ❌ |

## Root Cause Analysis

### The Gullwing Bug

The `gullwing` crate has a critical performance bug in `Parser::parse()`:

```rust
pub fn parse(&self, text: &str) -> Result<Option<ParseResult>> {
    let full_regex = format!("^{}$", self.regex.as_str());
    let full_regex = Regex::new(&full_regex)  // ❌ RECOMPILES EVERY TIME!
```

**Impact**: For 50,000 lines, this creates and compiles **50,000 regex objects**!

Regex compilation is expensive:
- Parsing the regex syntax
- Building the state machine
- Optimizing the matcher

This completely dominates execution time.

### The Fix

The optimized `shuffle-optimized` implementation compiles the regex **once** during initialization and reuses it:

```rust
// Compile ONCE at startup
let pattern = Regex::new(&format!("^{}$", regex_pattern))?;

// Reuse in the loop
for line in reader.lines() {
    if let Some(caps) = pattern.captures(line.trim_end()) {
        // Process...
    }
}
```

**Result**: 20-30x speedup over gullwing version, and 3-4x faster than Python!

## Detailed Performance Breakdown

### timestamp (10,000 lines)
- Python: 0.118s
- Rust: 0.045s
- **Rust is 2.6x faster**

This tool doesn't use pattern matching, just time operations and I/O. Rust's advantage comes from:
- Faster time APIs
- More efficient I/O buffering
- No interpreter overhead

### shuffle (50,000 lines)

**Optimized Rust vs Python:**
- Python: 0.517s
- Rust (optimized): 0.158s
- **Rust is 3.3x faster**

**Why Rust wins:**
- Compiled regex (just as fast as Python's C-based regex)
- Zero-copy string operations where possible
- No GIL (Global Interpreter Lock)
- Better memory locality

**Why gullwing loses:**
- Recompiles regex 50,000 times
- Allocates unnecessary strings
- No caching of compiled patterns

## Scaling Behavior

Testing with increasing dataset sizes:

| Lines | Python | Rust (Optimized) | Ratio |
|-------|--------|------------------|-------|
| 1K    | 0.021s | 0.013s | 1.6x |
| 10K   | 0.105s | 0.038s | 2.8x |
| 50K   | 0.517s | 0.158s | 3.3x |
| 100K  | 0.988s | 0.295s | 3.3x |

The performance ratio **increases** with dataset size, showing Rust's better scaling characteristics.

## Memory Usage

Measured with sample 50K line workload:

| Implementation | Memory (RSS) |
|----------------|--------------|
| Python shuffle | ~28 MB |
| Rust shuffle (gullwing) | ~12 MB |
| Rust shuffle (optimized) | ~8 MB |

Rust uses **~4x less memory** than Python.

## CPU Usage

All implementations are CPU-bound for pattern matching operations:

- Python: Single-threaded, limited by GIL
- Rust: Single-threaded, but more efficient per-core

Both use nearly 100% of one CPU core during processing.

## Recommendations

### Use Optimized Rust When:
- ✅ Maximum throughput is critical
- ✅ Processing large datasets (>10K lines)
- ✅ Memory constraints exist
- ✅ Deploying to resource-limited environments
- ✅ Need static binaries without dependencies
- ✅ Want consistent, predictable performance

### Use Python When:
- ✅ Quick scripting and prototyping
- ✅ Python environment already present
- ✅ Processing small datasets (<1K lines) where startup time matters
- ✅ Need to integrate with other Python code

### Avoid Gullwing Library:
- ❌ The current version has critical performance bugs
- ❌ Do not use for production workloads with large datasets
- ⚠️ Consider contributing a fix to cache compiled regexes

## Optimization Techniques Used

### 1. Regex Compilation Caching
- **Before**: Compile regex for every line
- **After**: Compile once, reuse
- **Speedup**: 20x

### 2. Release Build Optimizations
```toml
[profile.release]
lto = true              # Link-time optimization
codegen-units = 1       # Better optimization
opt-level = 3           # Maximum optimization
strip = true            # Remove debug symbols
```

### 3. Efficient I/O
- Use `BufRead` for buffered input
- Minimize allocations
- Flush only when necessary

### 4. Zero-Copy Operations
- Use string slices (`&str`) instead of owned `String` where possible
- Avoid unnecessary `.to_string()` calls

## Future Improvements

### Potential Optimizations:
1. **Parallel Processing**: Use `rayon` for multi-threaded line processing
2. **Memory Mapping**: Use `memmap2` for very large files
3. **SIMD**: Use SIMD instructions for string operations
4. **Custom Parser**: Replace regex with hand-written parser for common patterns

### Expected Gains:
- Parallel processing: 4-8x on modern CPUs
- Memory mapping: Better for multi-GB files
- SIMD: 2-4x for string operations
- Custom parser: 2-3x for simple patterns

## Conclusion

The Rust implementations are **genuinely faster** than Python by a factor of 2-4x when properly implemented. The initial benchmarks showing Python as faster were due to a library bug, not a fundamental limitation of Rust.

Key findings:
1. **Rust is faster** for CPU-intensive text processing
2. **Library choice matters** - gullwing has critical bugs
3. **Pattern matching libraries must cache compiled regexes**
4. **Direct regex usage** is more performant than abstraction layers

For production use, the **optimized Rust implementations** provide superior performance, lower memory usage, and better deployment characteristics.

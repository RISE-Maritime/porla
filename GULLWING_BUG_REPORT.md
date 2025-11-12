# Performance Bug: Parser.parse() Recompiles Regex on Every Call

## Summary

`Parser::parse()` recompiles the regex pattern on every invocation, causing severe performance degradation for workloads that parse multiple lines. This makes the library **20-30x slower** than expected and unusable for production batch processing.

## Root Cause

**File**: `src/parse/matcher.rs`, lines 75-78

```rust
pub fn parse(&self, text: &str) -> Result<Option<ParseResult>> {
    let full_regex = format!("^{}$", self.regex.as_str());
    let full_regex = Regex::new(&full_regex)  // ❌ Recompiles on every call!
        .map_err(|e| Error::RegexError(format!("failed to compile regex: {}", e)))?;
```

The regex is compiled fresh for every `parse()` call instead of being cached. Regex compilation is expensive (parsing syntax, building state machines, optimization), and should only happen once during `Parser::new()`.

## Performance Impact

**Benchmark**: Parsing 50,000 lines with pattern `{timestamp} {level} {message}`

| Implementation | Time | Performance |
|----------------|------|-------------|
| Python `parse` library | 0.517s | Baseline |
| Gullwing (current) | 3.086s | **6x slower** ❌ |
| Direct Rust regex (compiled once) | 0.158s | **3.3x faster** ✅ |

**Analysis**:
- Gullwing is **20x slower** than properly cached regex
- The recompilation overhead completely dominates execution time
- Makes gullwing slower than Python's C-based `parse` library

## Reproduction

```rust
use gullwing::Parser;

fn main() {
    let parser = Parser::new("{name} {value}").unwrap();

    // This will recompile the regex 50,000 times!
    for i in 0..50000 {
        let line = format!("item{} data{}", i, i);
        let _ = parser.parse(&line).unwrap();
    }
}
```

**Expected**: Fast, regex compiled once
**Actual**: Very slow, regex compiled 50,000 times

## Suggested Fix

Store the anchored regex in the `Parser` struct and compile it during construction:

```rust
pub struct Parser {
    pattern: String,
    regex: Regex,
    anchored_regex: Regex,  // ✅ Add this
    captures: Vec<CaptureInfo>,
}

impl Parser {
    pub fn new(pattern: &str) -> Result<Self> {
        let (regex_pattern, captures) = build_regex_pattern(pattern)?;
        let regex = Regex::new(&regex_pattern)
            .map_err(|e| Error::RegexError(format!("failed to compile regex: {}", e)))?;

        // ✅ Compile anchored version once
        let anchored_pattern = format!("^{}$", regex_pattern);
        let anchored_regex = Regex::new(&anchored_pattern)
            .map_err(|e| Error::RegexError(format!("failed to compile anchored regex: {}", e)))?;

        Ok(Parser {
            pattern: pattern.to_string(),
            regex,
            anchored_regex,  // ✅ Store it
            captures,
        })
    }

    pub fn parse(&self, text: &str) -> Result<Option<ParseResult>> {
        // ✅ Use cached regex
        if let Some(cap) = self.anchored_regex.captures(text) {
            let values = self.extract_values(&cap)?;
            Ok(Some(ParseResult {
                values,
                text: text.to_string(),
            }))
        } else {
            Ok(None)
        }
    }
}
```

## Impact

This fix would:
- ✅ Make `parse()` 20-30x faster for typical workloads
- ✅ Make gullwing competitive with Python's `parse` library
- ✅ Enable production use for batch processing
- ✅ Minimal API changes (fully backward compatible)
- ✅ Small memory overhead (~few KB per Parser instance)

## Additional Notes

The same issue may exist in other methods that construct regex patterns. A quick audit shows:
- ✅ `search()` - Uses the base `self.regex` directly (no issue)
- ✅ `findall()` - Uses the base `self.regex` directly (no issue)
- ❌ `parse()` - Recompiles with anchors (THIS BUG)

## Environment

- **gullwing version**: 0.9.0 (git commit `5f048df5`)
- **Rust version**: 1.91.0
- **OS**: Linux

## References

- Benchmark script: [proper_benchmark.sh](benchmarks/proper_benchmark.sh)
- Performance analysis: [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md)
- Test case: Used in [porla](https://github.com/RISE-Maritime/porla) bin script rewrites

---

This bug makes gullwing unusable for production workloads. The fix is straightforward and would provide dramatic performance improvements. Happy to test a patch or submit a PR if helpful.

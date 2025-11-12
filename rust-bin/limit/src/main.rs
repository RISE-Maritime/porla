use anyhow::Result;
use clap::Parser as ClapParser;
use gullwing::Parser;
use log::{debug, error};
use std::collections::HashMap;
use std::io::{self, BufRead, Write};
use std::time::Instant;

#[derive(ClapParser, Debug)]
#[command(
    name = "limit",
    about = "Rate limit the flow through a pipeline on a line-by-line basis"
)]
struct Args {
    #[arg(help = "Minimum allowed interval (in seconds) between lines")]
    interval: f64,

    #[arg(
        long,
        help = "Key specification for per-key rate limiting (e.g., '{key} {} {}')"
    )]
    key: Option<String>,

    #[arg(long, default_value = "warn", help = "Log level (error, warn, info, debug)")]
    log_level: String,
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Initialize logger
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or(&args.log_level)
    ).init();

    // Compile the key pattern if provided
    let parser = args.key.as_ref().map(|k| Parser::new(k)).transpose()?;

    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let reader = stdin.lock();

    // Track last seen time for each key
    let mut buffer: HashMap<String, Instant> = HashMap::new();
    let interval = std::time::Duration::from_secs_f64(args.interval);

    for line in reader.lines() {
        let line = line?;
        let now = Instant::now();

        debug!("{}", line);

        // Extract key from line
        let key = match get_key(&line, &parser) {
            Some(k) => k,
            None => continue, // Skip line if key extraction failed
        };

        // Check if enough time has passed since last seen
        let should_pass = match buffer.get(&key) {
            Some(last_seen) => now.duration_since(*last_seen) > interval,
            None => true, // First time seeing this key
        };

        if should_pass {
            buffer.insert(key, now);
            write!(stdout, "{}", line)?;
            if !line.ends_with('\n') {
                writeln!(stdout)?;
            }
            stdout.flush()?;
        }
        // else: drop line
    }

    Ok(())
}

fn get_key(line: &str, parser: &Option<Parser>) -> Option<String> {
    match parser {
        None => Some("fixed".to_string()),
        Some(p) => {
            match p.parse(line.trim_end()) {
                Ok(Some(result)) => {
                    // Look for the 'key' field in captures
                    result.get("key").and_then(|v| v.as_str()).map(|s| s.to_string())
                }
                _ => {
                    error!("Could not parse line: {} according to the key specification", line);
                    None
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;
    use std::time::Duration;

    #[test]
    fn test_get_key_no_parser() {
        let key = get_key("any line", &None);
        assert_eq!(key, Some("fixed".to_string()));
    }

    #[test]
    fn test_get_key_with_parser() {
        let parser = Some(Parser::new("{key} {data}").unwrap());
        let key = get_key("mykey somedata", &parser);
        assert_eq!(key, Some("mykey".to_string()));
    }

    #[test]
    fn test_get_key_parse_failure() {
        let parser = Some(Parser::new("{key} {data}").unwrap());
        let key = get_key("invalid", &parser);
        assert_eq!(key, None);
    }

    #[test]
    fn test_rate_limiting_logic() {
        let mut buffer: HashMap<String, Instant> = HashMap::new();
        let interval = Duration::from_millis(50);
        let key = "test".to_string();

        // First message should pass
        let now1 = Instant::now();
        let should_pass1 = match buffer.get(&key) {
            Some(last_seen) => now1.duration_since(*last_seen) > interval,
            None => true,
        };
        assert!(should_pass1);
        buffer.insert(key.clone(), now1);

        // Immediate second message should be blocked
        let now2 = Instant::now();
        let should_pass2 = match buffer.get(&key) {
            Some(last_seen) => now2.duration_since(*last_seen) > interval,
            None => true,
        };
        assert!(!should_pass2);

        // After waiting, message should pass
        thread::sleep(Duration::from_millis(60));
        let now3 = Instant::now();
        let should_pass3 = match buffer.get(&key) {
            Some(last_seen) => now3.duration_since(*last_seen) > interval,
            None => true,
        };
        assert!(should_pass3);
    }
}

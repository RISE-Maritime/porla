use anyhow::Result;
use chrono::{DateTime, Utc};
use clap::Parser;
use std::io::{self, BufRead, Write};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Parser, Debug)]
#[command(
    name = "timestamp",
    about = "Prepend each line from stdin with a timestamp"
)]
struct Args {
    #[arg(long, group = "format", help = "Use Unix epoch timestamp")]
    epoch: bool,

    #[arg(long, group = "format", help = "Use RFC3339 timestamp")]
    rfc3339: bool,
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Validate that exactly one format is specified
    if !args.epoch && !args.rfc3339 {
        anyhow::bail!("error: one of '--epoch' or '--rfc3339' must be specified");
    }

    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let reader = stdin.lock();

    for line in reader.lines() {
        let line = line?;
        let timestamp = if args.epoch {
            format_epoch()
        } else {
            format_rfc3339()
        };

        writeln!(stdout, "{} {}", timestamp, line)?;
        stdout.flush()?;
    }

    Ok(())
}

fn format_epoch() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("Time went backwards");
    format!("{:.6}", now.as_secs_f64())
}

fn format_rfc3339() -> String {
    let now: DateTime<Utc> = SystemTime::now().into();
    now.to_rfc3339()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn test_format_epoch() {
        let ts = format_epoch();
        let parsed: f64 = ts.parse().expect("Should be valid float");
        assert!(parsed > 0.0);
        // Check it has 6 decimal places
        assert!(ts.contains('.'));
        let decimals = ts.split('.').nth(1).unwrap();
        assert_eq!(decimals.len(), 6);
    }

    #[test]
    fn test_format_rfc3339() {
        let ts = format_rfc3339();
        // Should be parseable as DateTime
        DateTime::parse_from_rfc3339(&ts).expect("Should be valid RFC3339");
        // Should contain 'T' and timezone
        assert!(ts.contains('T'));
        assert!(ts.contains('+') || ts.contains('Z'));
    }

    #[test]
    fn test_epoch_timestamps_increase() {
        let ts1 = format_epoch();
        std::thread::sleep(Duration::from_millis(10));
        let ts2 = format_epoch();

        let val1: f64 = ts1.parse().unwrap();
        let val2: f64 = ts2.parse().unwrap();
        assert!(val2 > val1);
    }
}

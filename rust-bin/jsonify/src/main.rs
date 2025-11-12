use anyhow::Result;
use clap::Parser as ClapParser;
use gullwing::Parser;
use log::{debug, error};
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

#[derive(ClapParser, Debug)]
#[command(
    name = "jsonify",
    about = "Parse input lines and assemble into JSON objects"
)]
struct Args {
    #[arg(
        help = "Specification for parsing (e.g., '{timestamp} {data}')",
        value_name = "SPECIFICATION"
    )]
    specification: String,

    #[arg(long, default_value = "warn", help = "Log level (error, warn, info, debug)")]
    log_level: String,
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Initialize logger
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or(&args.log_level)
    ).init();

    // Compile the pattern
    let parser = Parser::new(&args.specification)?;

    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let reader = stdin.lock();

    for line in reader.lines() {
        let line = line?;
        debug!("{}", line);

        match parser.parse(&line.trim_end())? {
            Some(result) => {
                // Convert captures to JSON object
                let mut obj = serde_json::Map::new();
                for (name, value) in result.values() {
                    let json_value = match value {
                        gullwing::Value::Int(i) => Value::Number((*i).into()),
                        gullwing::Value::UInt(u) => Value::Number((*u).into()),
                        gullwing::Value::Float(f) => {
                            Value::Number(serde_json::Number::from_f64(*f).unwrap_or_else(|| 0.into()))
                        }
                        gullwing::Value::Bool(b) => Value::Bool(*b),
                        _ => Value::String(value.to_string()),
                    };
                    obj.insert(name.to_string(), json_value);
                }

                let json_output = json!(obj);
                writeln!(stdout, "{}", json_output)?;
                stdout.flush()?;
            }
            None => {
                error!(
                    "Could not parse line: {} according to the specification: {}",
                    line, args.specification
                );
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn test_jsonify_simple() {
        let parser = Parser::new("{name} {value}").unwrap();
        let result = parser.parse("hello world").unwrap().unwrap();

        let mut obj = serde_json::Map::new();
        for (name, value) in result.values() {
            obj.insert(name.to_string(), Value::String(value.to_string()));
        }

        let json_output = json!(obj);
        let parsed: Value = serde_json::from_str(&json_output.to_string()).unwrap();

        assert_eq!(parsed["name"], "hello");
        assert_eq!(parsed["value"], "world");
    }

    #[test]
    fn test_jsonify_multiple_fields() {
        let parser = Parser::new("{timestamp} {level} {message}").unwrap();
        let result = parser.parse("2023-01-01 INFO test").unwrap().unwrap();

        let mut obj = serde_json::Map::new();
        for (name, value) in result.values() {
            obj.insert(name.to_string(), Value::String(value.to_string()));
        }

        let json_output = json!(obj);
        let parsed: Value = serde_json::from_str(&json_output.to_string()).unwrap();

        assert_eq!(parsed["timestamp"], "2023-01-01");
        assert_eq!(parsed["level"], "INFO");
        assert_eq!(parsed["message"], "test");
    }

    #[test]
    fn test_jsonify_with_integer() {
        let parser = Parser::new("{name} {value:d}").unwrap();
        let result = parser.parse("count 42").unwrap().unwrap();

        let mut obj = serde_json::Map::new();
        for (name, value) in result.values() {
            let json_value = match value {
                gullwing::Value::Int(i) => Value::Number((*i).into()),
                _ => Value::String(value.to_string()),
            };
            obj.insert(name.to_string(), json_value);
        }

        let json_output = json!(obj);
        let parsed: Value = serde_json::from_str(&json_output.to_string()).unwrap();

        assert_eq!(parsed["name"], "count");
        assert_eq!(parsed["value"], 42);
    }
}

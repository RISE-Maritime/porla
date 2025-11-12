use anyhow::Result;
use clap::Parser as ClapParser;
use log::{debug, error};
use regex::Regex;
use std::io::{self, BufRead, Write};

#[derive(ClapParser, Debug)]
#[command(
    name = "shuffle-optimized",
    about = "Parse input lines and reformat - optimized without gullwing"
)]
struct Args {
    #[arg(help = "Input specification (e.g., '{timestamp} {level} {message}')")]
    input_specification: String,

    #[arg(help = "Output specification (e.g., '{level}: {message}')")]
    output_specification: String,

    #[arg(long, default_value = "warn")]
    log_level: String,
}

fn main() -> Result<()> {
    let args = Args::parse();

    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or(&args.log_level)
    ).init();

    // Convert Python-style pattern to regex - extract field names
    let (regex_pattern, field_names) = build_regex(&args.input_specification)?;

    // Compile regex ONCE (with anchors for full match)
    let pattern = Regex::new(&format!("^{}$", regex_pattern))?;

    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let reader = stdin.lock();

    for line in reader.lines() {
        let line = line?;
        debug!("{}", line);

        if let Some(caps) = pattern.captures(line.trim_end()) {
            let mut output = args.output_specification.clone();

            // Replace each field in the output template
            for (i, field_name) in field_names.iter().enumerate() {
                if let Some(value) = caps.get(i + 1) {
                    let placeholder = format!("{{{}}}", field_name);
                    output = output.replace(&placeholder, value.as_str());
                }
            }

            writeln!(stdout, "{}", output)?;
            stdout.flush()?;
        } else {
            error!("Could not parse line: {}", line);
        }
    }

    Ok(())
}

/// Convert Python-style format pattern to regex
/// "{timestamp} {level} {message}" -> ("(\\S+) (\\S+) (.+)", ["timestamp", "level", "message"])
fn build_regex(pattern: &str) -> Result<(String, Vec<String>)> {
    let mut regex = String::new();
    let mut fields = Vec::new();
    let mut chars = pattern.chars().peekable();

    while let Some(ch) = chars.next() {
        if ch == '{' {
            // Extract field name
            let mut field_name = String::new();
            while let Some(&next_ch) = chars.peek() {
                if next_ch == '}' {
                    chars.next(); // consume '}'
                    break;
                }
                field_name.push(chars.next().unwrap());
            }

            fields.push(field_name);

            // Use greedy match for all but last field
            if chars.peek().is_some() {
                regex.push_str(r"(\S+)");
            } else {
                // Last field can contain spaces
                regex.push_str(r"(.+)");
            }
        } else {
            // Escape regex special characters
            match ch {
                '.' | '*' | '+' | '?' | '^' | '$' | '(' | ')' | '[' | ']' | '|' | '\\' => {
                    regex.push('\\');
                    regex.push(ch);
                }
                ' ' => regex.push_str(r" "),
                _ => regex.push(ch),
            }
        }
    }

    Ok((regex, fields))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_regex() {
        let (regex, fields) = build_regex("{name} {value}").unwrap();
        assert_eq!(fields, vec!["name", "value"]);

        let re = Regex::new(&format!("^{}$", regex)).unwrap();
        assert!(re.is_match("hello world"));

        let caps = re.captures("hello world").unwrap();
        assert_eq!(caps.get(1).unwrap().as_str(), "hello");
        assert_eq!(caps.get(2).unwrap().as_str(), "world");
    }

    #[test]
    fn test_complex_pattern() {
        let (regex, fields) = build_regex("{timestamp} {level} {message}").unwrap();
        assert_eq!(fields, vec!["timestamp", "level", "message"]);

        let re = Regex::new(&format!("^{}$", regex)).unwrap();
        let text = "2023-01-01 INFO This is a message";
        assert!(re.is_match(text));

        let caps = re.captures(text).unwrap();
        assert_eq!(caps.get(1).unwrap().as_str(), "2023-01-01");
        assert_eq!(caps.get(2).unwrap().as_str(), "INFO");
        assert_eq!(caps.get(3).unwrap().as_str(), "This is a message");
    }
}

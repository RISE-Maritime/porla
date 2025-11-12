use anyhow::Result;
use clap::Parser as ClapParser;
use gullwing::Parser;
use log::{debug, error};
use std::io::{self, BufRead, Write};

#[derive(ClapParser, Debug)]
#[command(
    name = "shuffle",
    about = "Parse input lines and reformat according to specifications"
)]
struct Args {
    #[arg(
        help = "Input specification (e.g., '{timestamp} {data}')",
        value_name = "INPUT_SPEC"
    )]
    input_specification: String,

    #[arg(
        help = "Output specification (e.g., '{data}')",
        value_name = "OUTPUT_SPEC"
    )]
    output_specification: String,

    #[arg(long, default_value = "warn", help = "Log level (error, warn, info, debug)")]
    log_level: String,
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Initialize logger
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or(&args.log_level)
    ).init();

    // Compile the input pattern
    let input_parser = Parser::new(&args.input_specification)?;

    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let reader = stdin.lock();

    for line in reader.lines() {
        let line = line?;
        debug!("{}", line);

        match input_parser.parse(&line.trim_end())? {
            Some(result) => {
                // Format output using the captured values
                let output = format_output(&args.output_specification, &result);
                writeln!(stdout, "{}", output)?;
                stdout.flush()?;
            }
            None => {
                error!(
                    "Could not parse line: {} according to the input_specification: {}",
                    line, args.input_specification
                );
            }
        }
    }

    Ok(())
}

fn format_output(template: &str, result: &gullwing::ParseResult) -> String {
    let mut output = template.to_string();

    for (name, value) in result.values() {
        let placeholder = format!("{{{}}}", name);
        let value_str = match value.as_str() {
            Some(s) => s.to_string(),
            None => value.to_string(),
        };
        output = output.replace(&placeholder, &value_str);
    }

    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_output_simple() {
        let parser = Parser::new("{name} {value}").unwrap();
        let result = parser.parse("hello world").unwrap().unwrap();

        let output = format_output("{value} {name}", &result);
        assert_eq!(output, "world hello");
    }

    #[test]
    fn test_format_output_with_literals() {
        let parser = Parser::new("{x} {y}").unwrap();
        let result = parser.parse("1 2").unwrap().unwrap();

        let output = format_output("x={x}, y={y}", &result);
        assert_eq!(output, "x=1, y=2");
    }

    #[test]
    fn test_format_output_repeated_placeholder() {
        let parser = Parser::new("{val}").unwrap();
        let result = parser.parse("test").unwrap().unwrap();

        let output = format_output("{val} {val} {val}", &result);
        assert_eq!(output, "test test test");
    }
}

use anyhow::Result;
use base64::{engine::general_purpose::STANDARD, Engine};
use clap::Parser as ClapParser;
use gullwing::Parser;
use log::{debug, error};
use std::io::{self, BufRead, Write};

#[derive(ClapParser, Debug)]
#[command(
    name = "b64",
    about = "Base64 encode or decode lines from stdin"
)]
struct Args {
    #[arg(long, group = "operation", help = "Encode input to base64")]
    encode: bool,

    #[arg(long, group = "operation", help = "Decode input from base64")]
    decode: bool,

    #[arg(
        default_value = "{input}",
        help = "Input specification (e.g., '{timestamp} {input}')"
    )]
    input_specification: String,

    #[arg(
        default_value = "{output}",
        help = "Output specification (e.g., '{output}')"
    )]
    output_specification: String,

    #[arg(long, default_value = "warn", help = "Log level (error, warn, info, debug)")]
    log_level: String,
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Validate that exactly one operation is specified
    if !args.encode && !args.decode {
        anyhow::bail!("error: one of '--encode' or '--decode' must be specified");
    }

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
                // Get the 'input' field
                match result.get("input") {
                    Some(input_value) => {
                        let input_str = match input_value.as_str() {
                            Some(s) => s,
                            None => {
                                error!("Input field is not a string");
                                continue;
                            }
                        };

                        // Perform encoding or decoding
                        let output = if args.encode {
                            STANDARD.encode(input_str.as_bytes())
                        } else {
                            match STANDARD.decode(input_str.as_bytes()) {
                                Ok(decoded) => match String::from_utf8(decoded) {
                                    Ok(s) => s,
                                    Err(e) => {
                                        error!("Invalid UTF-8 in decoded data: {}", e);
                                        continue;
                                    }
                                },
                                Err(e) => {
                                    error!("Base64 decode error: {}", e);
                                    continue;
                                }
                            }
                        };

                        // Format output with the result
                        let formatted = format_output(&args.output_specification, &result, &output);
                        writeln!(stdout, "{}", formatted)?;
                        stdout.flush()?;
                    }
                    None => {
                        error!(
                            "Could not find the expected named argument 'input' in the input specification: {}",
                            args.input_specification
                        );
                    }
                }
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

fn format_output(template: &str, result: &gullwing::ParseResult, output: &str) -> String {
    let mut formatted = template.to_string();

    // First replace {output} with the encoded/decoded value
    formatted = formatted.replace("{output}", output);

    // Then replace other captured values
    for (name, value) in result.values() {
        if name != "input" {
            let placeholder = format!("{{{}}}", name);
            let value_str = match value.as_str() {
                Some(s) => s.to_string(),
                None => value.to_string(),
            };
            formatted = formatted.replace(&placeholder, &value_str);
        }
    }

    formatted
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode() {
        let encoded = STANDARD.encode(b"hello");
        assert_eq!(encoded, "aGVsbG8=");
    }

    #[test]
    fn test_decode() {
        let decoded = STANDARD.decode("aGVsbG8=").unwrap();
        let text = String::from_utf8(decoded).unwrap();
        assert_eq!(text, "hello");
    }

    #[test]
    fn test_encode_decode_roundtrip() {
        let original = "Hello, World! 123";
        let encoded = STANDARD.encode(original.as_bytes());
        let decoded = STANDARD.decode(&encoded).unwrap();
        let result = String::from_utf8(decoded).unwrap();
        assert_eq!(result, original);
    }

    #[test]
    fn test_format_output_simple() {
        let parser = Parser::new("{input}").unwrap();
        let result = parser.parse("test").unwrap().unwrap();

        let output = format_output("{output}", &result, "encoded_value");
        assert_eq!(output, "encoded_value");
    }

    #[test]
    fn test_format_output_with_other_fields() {
        let parser = Parser::new("{timestamp} {input}").unwrap();
        let result = parser.parse("2023-01-01 test").unwrap().unwrap();

        let output = format_output("{timestamp} {output}", &result, "encoded");
        assert_eq!(output, "2023-01-01 encoded");
    }
}

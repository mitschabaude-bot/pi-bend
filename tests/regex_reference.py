"""Build the test-only Rust byte-regex oracle used by ripgrep-style checks."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'build/regex-reference'
MANIFEST = '''[package]
name = "regex-reference"
version = "0.1.0"
edition = "2021"
[dependencies]
regex = "=1.13.1"
regex-automata = "=0.4.18"
regex-syntax = "=0.8.11"
serde_json = "=1.0.151"
'''
SOURCE = r'''use std::io::{self, BufRead};
fn main() {
    for row in io::stdin().lock().lines() {
        let row: Vec<String> = serde_json::from_str(&row.unwrap()).unwrap();
        match regex::bytes::RegexBuilder::new(&row[1])
            .case_insensitive(row[0] == "i").build() {
            Ok(regex) => println!("{}", regex.is_match(row[2].as_bytes())),
            Err(_) => println!("error"),
        }
    }
}
'''

def setup():
    (TARGET / 'src').mkdir(parents=True, exist_ok=True)
    (TARGET / 'Cargo.toml').write_text(MANIFEST)
    (TARGET / 'src/main.rs').write_text(SOURCE)
    subprocess.run(['cargo', 'build', '--release', '--manifest-path', str(TARGET / 'Cargo.toml')], check=True)
    print(TARGET / 'target/release/regex-reference')

if __name__ == '__main__':
    setup()

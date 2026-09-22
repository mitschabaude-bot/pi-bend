"""Build a test-only pinned globset/fd oracle; production uses only Bend."""
from pathlib import Path
from urllib.request import urlopen
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'build/path-glob-oracle'
SOURCE = ROOT / 'build/reference/regex-helper.rs'
SOURCE.parent.mkdir(parents=True, exist_ok=True)
if not SOURCE.exists():
    SOURCE.write_bytes(urlopen('https://raw.githubusercontent.com/sharkdp/fd/v10.3.0/src/regex_helper.rs', timeout=30).read())
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == '520987991c1659ba8c1be0c9c29b81ea7145e25c76a5e4cb340a9e82c6c29d13'
(TARGET/'src').mkdir(parents=True, exist_ok=True)
(TARGET/'Cargo.toml').write_text(r'''
[package]
name = "path-glob-oracle"
version = "0.0.0"
edition = "2021"
[dependencies]
globset = "=0.4.16"
regex = "=1.11.1"
regex-syntax = "=0.8.5"
serde_json = "1"
'''.lstrip())
(TARGET/'src/main.rs').write_text(r'''
use std::io::{self, Read};
#[allow(dead_code)]
mod fd_helper { include!("../../reference/regex-helper.rs"); }
fn main() {
 let mut input=String::new(); io::stdin().read_to_string(&mut input).unwrap();
 let cases: Vec<(String,String)> = serde_json::from_str(&input).unwrap();
 for (pattern,text) in cases {
  match globset::GlobBuilder::new(&pattern).literal_separator(true).build() {
   Err(_) => println!("error"),
   Ok(glob) => {
    match regex::bytes::RegexBuilder::new(glob.regex()).case_insensitive(!fd_helper::pattern_has_uppercase_char(glob.regex())).dot_matches_new_line(true).build() {
     Err(_) => println!("error"),
     Ok(regex) => println!("{}",regex.is_match(text.as_bytes()))
    }
   }
  }
 }
}
'''.lstrip())
subprocess.run(['cargo','build','--release','--manifest-path',str(TARGET/'Cargo.toml')],check=True)

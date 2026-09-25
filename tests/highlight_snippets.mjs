// Hand-written snippets for the highlight.js differential (tests/highlight_check.py):
// pi's 20 eager languages, common deferred ones, and the grammar features the
// Bend port implements natively (callbacks, sub-languages, continuations).
export const snippets = [
  { language: "python", code: `#!/usr/bin/env python3
"""Module docstring."""
import os
from typing import List

@decorator(arg=1)
class Foo(Base, metaclass=Meta):
    '''Class doc'''
    x: int = 0x1F

    def method(self, a, *args, **kw) -> List[int]:
        # TODO: fix this
        s = f"value {self.x + 1:>4} and {a!r}"
        b = rb'raw\\bytes'
        return [i ** 2 for i in range(10) if i % 2 == 0 and not None]

async def main():
    await asyncio.sleep(1.5e-3)
    lambda x: x
print("done", end='')
` },
  { language: "java", code: `package com.example;

import java.util.*;

/**
 * Javadoc with {@link Map} and @param tags.
 */
@SuppressWarnings("unchecked")
public final class Main<T extends Comparable<T>> implements Runnable {
    private static final long MAX = 100_000L;
    private final Map<String, List<Integer>> index = new HashMap<>();

    public static void main(String[] args) throws Exception {
        int x = 0b1010 + 0x1F + 07;
        char c = '\\n';
        String s = "hello \\"world\\"";
        for (var i = 0; i < args.length; i++) { System.out.println(args[i]); }
        new Main<String>().run();
    }

    @Override
    public void run() { synchronized (this) { this.notifyAll(); } }
}
` },
  { language: "go", code: `package main

import (
	"fmt"
	"strings"
)

// Point is a point.
type Point struct {
	X, Y float64 \`json:"x"\`
}

func (p *Point) Add(q Point) Point { return Point{p.X + q.X, p.Y + q.Y} }

func main() {
	ch := make(chan int, 3)
	go func() { ch <- 42 }()
	m := map[string]int{"a": 1}
	s := \`raw
string\`
	fmt.Printf("%d %v %s\\n", <-ch, m, strings.ToUpper(s))
	var x complex128 = 1 + 2i
	_ = x
}
` },
  { language: "javascript", code: `#!/usr/bin/env node
'use strict';
import { readFile } from "node:fs/promises";
const re = /foo+[a-z]\\/(bar)?/gi;
const tpl = \`value: \${a + \`nested \${b}\`} end\`;
class Animal extends Base {
  static #count = 0;
  constructor(name) { super(); this.name = name; }
  get label() { return \`<\${this.name}>\`; }
  async *items() { yield* [1, 2n, 0x1f, 1_000.5e3]; }
}
function App({ items }) {
  return (
    <div className="app" onClick={() => setCount(count + 1)}>
      {items.map((item) => <Item key={item.id} {...item} />)}
      <>fragment</>
    </div>
  );
}
const html = html\`<p class="x">\${text}</p>\`;
const styles = css\`color: red; .a { margin: 0 }\`;
export default async function main(a = 1, { b, c } = {}) {
  const x = a?.b ?? c; // comment
  /* block
     comment */
  return x > 1 ? "yes" : 'no';
}
obj.function = 1; obj.return();
` },
  { language: "typescript", code: `import type { Foo } from "./foo";
enum Color { Red = 1, Green, Blue }
interface Props<T> extends Base {
  readonly id: number;
  items?: Array<Array<number>>;
  cb: (x: T) => void;
}
declare module "m" { export const x: string; }
type Mapped<T> = { [K in keyof T]?: T[K] };
abstract class Shape implements Props<string> {
  private constructor(public readonly name: string, protected size = 0) { super(); }
  abstract area(): number;
  @decorator() method<T extends object>(arg: T): Promise<T> { return Promise.resolve(arg as T); }
}
const f = <T,>(x: T): T => x;
let a: unknown = <any>b;
function isString(x: unknown): x is string { return typeof x === "string"; }
namespace NS { export let y = 1n; }
` },
  { language: "cpp", code: `#include <iostream>
#include "local.h"
#define MAX(a, b) ((a) > (b) ? (a) : (b))

namespace ns {
template <typename T, std::size_t N = 4>
class Buffer final : public Base {
public:
  explicit Buffer(T init) noexcept : data_{init} {}
  ~Buffer() override = default;
  constexpr auto size() const -> std::size_t { return N; }
private:
  T data_[N];
};
}  // namespace ns

int main(int argc, char** argv) {
  auto raw = R"delim(raw "string" )" )delim";
  auto s = u8"utf8" L"wide";
  std::vector<int> v{1, 2, 3};
  for (const auto& x : v) std::cout << x << '\\n';
  int* p = nullptr; unsigned long long n = 0xFFULL + 1'000'000;
  return static_cast<int>(3.14f);
}
` },
  { language: "php", code: `<!DOCTYPE html>
<html>
<body>
<?php
namespace App\\Http;

use Foo\\Bar as Baz;

/** Doc comment */
final class User extends Model implements \\JsonSerializable {
    public const TABLE = 'users';
    private ?int $id = null;

    public function __construct(private string $name) {}

    public static function find(int $id): ?self {
        $sql = "SELECT * FROM users WHERE id = {$id} AND name = '$this->name'";
        $text = <<<EOT
Heredoc with $var and {$arr['key']}
EOT;
        $now = <<<'NOW'
nowdoc text $notvar
NOW;
        return array_map(fn($x) => $x * 2, [1, 2, 3]) ?? null;
    }
}
echo "done";
?>
<p><?= htmlspecialchars($title) ?></p>
</body>
</html>
` },
  { language: "ruby", code: `#!/usr/bin/env ruby
# frozen_string_literal: true
require 'json'

module Shop
  class Cart < Base
    attr_reader :items
    CONSTANT = %w[a b c].freeze

    def initialize(items = [])
      @items = items
      @@count ||= 0
    end

    def total(tax: 0.2, &block)
      sum = items.sum { |i| i[:price] * (1 + tax) }
      yield sum if block_given?
      "Total: #{format('%.2f', sum)}"
    end

    def self.parse(text) = JSON.parse(text, symbolize_names: true)
  end
end

query = <<~SQL
  SELECT * FROM carts WHERE id = #{id}
SQL
puts /ab+c/i.match?("abbc") ? :yes : :no
=begin
block comment
=end
` },
  { language: "c", code: `/* Multi-line
 * comment */
#include <stdio.h>
#include <stdlib.h>
#ifndef FOO_H
#define FOO_H 1
#endif

typedef struct node {
    int value;
    struct node *next;
} node_t;

static inline int add(int a, int b) { return a + b; }

int main(void) {
    char buf[256] = "hello\\tworld";
    const char c = 'x';
    unsigned long n = 42UL;
    double d = 1.5e-10;
    node_t *head = malloc(sizeof(node_t));
    if (!head) { perror("malloc"); return EXIT_FAILURE; }
    switch (n) { case 1: break; default: goto done; }
done:
    printf("%s %c %lu %f\\n", buf, c, n, d);
    return 0;
}
` },
  { language: "csharp", code: `using System;
using System.Collections.Generic;

namespace Demo
{
    /// <summary>XML doc</summary>
    [Serializable]
    public sealed class Person<T> : IComparable<Person<T>> where T : class
    {
        public string Name { get; init; } = "";
        private readonly List<int> _scores = new();

        public async Task<int> ComputeAsync(int x, out int y, ref int z)
        {
            y = x switch { 0 => 1, _ => 2 };
            var s = $"Hello {Name}, {x:N2}!";
            var v = @"verbatim ""string""";
            #region Helpers
            await Task.Delay(10);
            #endregion
            return x is > 5 and < 10 ? 1 : default;
        }

        public int CompareTo(Person<T>? other) => string.Compare(Name, other?.Name);
    }
}
` },
  { language: "nix", code: `{ pkgs ? import <nixpkgs> {}, lib, ... }:

let
  version = "1.2.3";
  # comment
  src = pkgs.fetchFromGitHub {
    owner = "example";
    repo = "project";
    rev = "v\${version}";
    sha256 = "0000000000000000000000000000000000000000000000000000";
  };
in
pkgs.stdenv.mkDerivation rec {
  pname = "project";
  inherit version src;
  buildInputs = with pkgs; [ openssl zlib ];
  installPhase = ''
    mkdir -p $out/bin
    cp project $out/bin/
  '';
  meta = { license = lib.licenses.mit; broken = false; };
}
` },
  { language: "bash", code: `#!/bin/bash
# Deploy script
set -euo pipefail

readonly DIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/bin:$PATH"

function log() {
  local level=$1; shift
  echo "[$(date +%T)] \${level}: $*" >&2
}

for f in "$DIR"/*.sh; do
  if [[ -x "$f" && ! -d "$f" ]]; then
    log info "running $f"
    "$f" || exit $?
  fi
done

cat <<EOF > config.txt
name=$USER
home=$HOME
EOF

case "$1" in
  start|run) echo 'starting' ;;
  *) echo "unknown: $1"; exit 1 ;;
esac
arr=(one two three); echo \${#arr[@]} $((1 + 2 * 3))
` },
  { language: "rust", code: `//! Crate docs
use std::collections::HashMap;
use std::fmt::{self, Display};

/// A point.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point<T: Copy> { x: T, y: T }

impl<T: Copy + Display> Display for Point<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "({}, {})", self.x, self.y)
    }
}

pub enum Shape { Circle { r: f64 }, Square(f64) }

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut map: HashMap<&str, i32> = HashMap::new();
    map.insert("a", 1_000i32);
    let raw = r#"raw "string""#;
    let bytes = b"bytes\\n";
    let c = 'c';
    let lifetime: &'static str = "s";
    match map.get("a") {
        Some(&v) if v > 0 => println!("{v} {raw} {c}"),
        _ => unreachable!(),
    }
    let closure = |x: u8| -> u8 { x.wrapping_add(0xff) };
    unsafe { std::ptr::null::<u8>(); }
    Ok(())
}
` },
  { language: "scala", code: `package example

import scala.collection.mutable
import scala.concurrent.{Future, ExecutionContext}

/** Scaladoc */
case class Person(name: String, age: Int) extends Ordered[Person] {
  def compare(that: Person): Int = this.age - that.age
}

sealed trait Shape
object Shape {
  final case class Circle(r: Double) extends Shape
  case object Unit extends Shape
}

object Main extends App {
  implicit val ec: ExecutionContext = ExecutionContext.global
  val xs = List(1, 2, 3).map(_ * 2).filter { x => x > 2 }
  val s = s"Hello \${xs.head} and $name"
  val raw = """triple
    quoted"""
  def area(s: Shape): Double = s match {
    case Shape.Circle(r) => math.Pi * r * r
    case _               => 0.0
  }
  lazy val f: Future[Int] = Future { 42 }
  println(xs)
}
` },
  { language: "kotlin", code: `package com.example

import kotlinx.coroutines.*

/**
 * KDoc comment
 */
@JvmInline
value class Id(val raw: Long)

data class User(val id: Id, var name: String = "anon") : Comparable<User> {
    override fun compareTo(other: User): Int = name.compareTo(other.name)
    companion object { const val MAX = 0xFF }
}

sealed interface Result<out T>
object Loading : Result<Nothing>

suspend fun fetch(url: String): String? = withContext(Dispatchers.IO) {
    val text = """
        raw $url
    """.trimIndent()
    if (text.isEmpty()) null else "Got \${text.length} chars: $url"
}

fun main() = runBlocking {
    val users = listOf(User(Id(1L)), User(Id(2L), "bob"))
    users.filter { it.name != "anon" }.forEach(::println)
    when (val x = users.size) { in 0..1 -> println("few") else -> println(x) }
}
` },
  { language: "swift", code: `import Foundation
import SwiftUI

/// Documentation comment
@MainActor
final class ViewModel: ObservableObject {
    @Published private(set) var items: [String] = []
    let id = UUID()

    init() {}

    func load(from url: URL) async throws -> Int {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8) else { return 0 }
        items = text.split(separator: "\\n").map(String.init)
        return items.count
    }
}

struct ContentView: View {
    @StateObject var model = ViewModel()
    var body: some View {
        List(model.items, id: \\.self) { item in
            Text("Item: \\(item)")
        }
    }
}

enum Direction: Int, CaseIterable { case north = 1, south, east, west }
let multiline = """
    Hello, \\(name)!
    """
let n = 0b1010 + 0o17 + 0xFF + 1_000.5
` },
  { language: "dart", code: `import 'dart:async';
import 'package:flutter/material.dart';

/// Doc comment
@immutable
class Counter extends StatefulWidget {
  const Counter({super.key, this.initial = 0});
  final int initial;

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  late int _count = widget.initial;
  static const double pi = 3.14159;

  Future<void> _increment() async {
    await Future.delayed(const Duration(milliseconds: 100));
    setState(() => _count++);
  }

  @override
  Widget build(BuildContext context) {
    final text = 'Count: $_count and \${_count * 2}';
    final raw = r'raw \\n string';
    return Text(text, style: TextStyle(fontSize: 12.0));
  }
}

void main() => runApp(const Counter());
` },
  { language: "groovy", code: `#!/usr/bin/env groovy
package example

import groovy.transform.CompileStatic

@CompileStatic
class Greeter {
    String name
    static final int MAX = 10

    def greet(String who = 'world') {
        def msg = "Hello, \${who}! from $name"
        println msg
        return msg
    }
}

def list = [1, 2, 3].collect { it * 2 }
def map = [a: 1, b: 2]
def slashy = /reg[ex]+/
def multi = '''
  multi-line
'''
pipeline {
    agent any
    stages {
        stage('Build') {
            steps { sh 'make build' }
        }
    }
}
` },
  { language: "perl", code: `#!/usr/bin/perl
use strict;
use warnings;

# Comment
my %hash = (one => 1, two => 2);
my @list = qw(a b c);
my $ref = \\@list;

sub greet {
    my ($name, %opts) = @_;
    return "Hello, $name!" unless $opts{quiet};
}

foreach my $key (sort keys %hash) {
    printf "%s => %d\\n", $key, $hash{$key};
}

my $text = "abc123";
if ($text =~ m/(\\d+)/) { print "digits: $1\\n"; }
$text =~ s/abc/xyz/g;
$text =~ tr/a-z/A-Z/;
print <<"END";
Heredoc with $text
END

__END__
=pod

Documentation

=cut
` },
  { language: "lua", code: `-- Single line comment
--[[ Multi-line
     comment ]]
local M = {}

local function helper(a, b, ...)
  local args = {...}
  return a + b * #args
end

function M.new(name)
  local self = setmetatable({}, { __index = M })
  self.name = name or "default"
  return self
end

function M:greet()
  print(("Hello, %s!"):format(self.name))
  local s = [[long
string]]
  for i = 1, 10, 2 do
    if i % 3 == 0 then goto continue end
    ::continue::
  end
  while true do break end
  return nil, false, 0x1F, 1e10
end

return M
` },
  { language: "json", code: `{
  "name": "example",
  "version": "1.0.0",
  "private": true,
  "nested": { "array": [1, 2.5, -3e10, null, false], "empty": {} },
  "escaped": "quote \\" and \\u00e9"
}
` },
  { language: "yaml", code: `%YAML 1.2
---
# Comment
name: example
version: 1.0
enabled: true
anchors:
  base: &base
    key: value
  derived:
    <<: *base
    other: !!str 123
list:
  - one
  - "two"
  - 'three'
multiline: |
  line one
  line two
folded: >-
  folded
  text
date: 2021-01-01
empty: ~
...
` },
  { language: "xml", code: `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE note SYSTEM "Note.dtd">
<!-- comment -->
<root xmlns:x="urn:example">
  <x:item id="1" enabled='true'>Text &amp; entity</x:item>
  <empty/>
  <![CDATA[ raw <data> ]]>
</root>
` },
  { language: "html", code: `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Page</title>
  <style>
    body { color: #333; margin: 0 auto; }
    .a > b:hover::after { content: "x"; }
  </style>
  <script type="text/javascript">
    const x = 1 < 2 && "</div>";
    function f() { return x; }
  </script>
</head>
<body class="main" data-x=1>
  <!-- comment -->
  <p>Hello <b>world</b> &copy; 2021</p>
  <input type="text" disabled>
</body>
</html>
` },
  { language: "css", code: `@import url("reset.css");
@media (max-width: 600px) and (orientation: landscape) {
  .container > .item:nth-child(2n+1)::before {
    content: "\\201C";
    color: #ff0000;
    background: rgba(0, 0, 0, 0.5) url(img.png) no-repeat;
    margin: 0 auto !important;
    transition: all 0.3s ease-in-out;
  }
}
#id, a[href^="http"] { font: 12px/1.5 "Helvetica Neue", sans-serif; }
@keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
:root { --main-color: hsl(120, 100%, 50%); }
/* comment */
` },
  { language: "scss", code: `@use "sass:math";
$primary: #333 !default;
@mixin flex($dir: row) { display: flex; flex-direction: $dir; }
.card {
  @include flex(column);
  &:hover { color: darken($primary, 10%); }
  .title { font-size: math.div(16px, 2); }
  // line comment
}
` },
  { language: "sql", code: `-- Comment
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL DEFAULT 'anon',
  created_at TIMESTAMP WITH TIME ZONE
);
/* block */
SELECT u.id, COUNT(*) AS n, MAX(o.total)
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE u.name LIKE 'a%' AND o.total > 100.5
GROUP BY u.id
HAVING COUNT(*) > 1
ORDER BY n DESC
LIMIT 10;
INSERT INTO t (a, "quoted col") VALUES (1, 'it''s'), (NULL, TRUE);
` },
  { language: "diff", code: `diff --git a/file.txt b/file.txt
index 83db48f..bf269f4 100644
--- a/file.txt
+++ b/file.txt
@@ -1,4 +1,4 @@
 unchanged line
-removed line
+added line
 another line
*** 1,3 ****
! changed
` },
  { language: "markdown", code: `# Heading 1

Some *emphasis*, **strong**, and \`inline code\`.

## List

- item one
- item [link](http://example.com "title")
1. numbered
> blockquote

\`\`\`javascript
const x = 1;
\`\`\`

    indented code

| a | b |
|---|---|
| 1 | 2 |

![image](img.png)
<div>html block</div>
***
` },
  { language: "shell", code: `$ echo "hello"
hello
$ ls -la /tmp
total 0
# comment line
> continuation
` },
  // Callback coverage and edge cases.
  { language: "typescript", code: `const a = <Array<number>>[];
function g<T>(x: Array<T>): T { return x[0]; }
const el = <Component prop={1}>child</Component>;
const bad = <T>(x: T) => x;
` },
  { language: "javascript", code: `if (a < b && c > d) { x = <br />; }
const t = <Foo>text without close
` },
  { language: "mathematica", code: `(* comment *)
f[x_] := Sin[x]^2 + Cos[x]^2
Plot[f[x], {x, 0, 2 Pi}, PlotRange -> All]
myVar = NotASystemSymbol[1.5*^3]
` },
  { language: "latex", code: `\\documentclass{article}
\\begin{document}
\\section{Intro} Math $x^2 + y_1$ and \\[ \\int_0^1 f \\]
\\begin{verbatim}
raw \\text here
\\end{verbatim}
% comment
\\end{document}
` },
  { language: "r", code: `x <- c(1, 2, 3)
s <- r"(raw "string" here)"
t <- R"-[another]-"
f <- function(a, b = 2L, ...) { if (a > b) TRUE else NA_integer_ }
` },
  { language: "pgsql", code: `CREATE FUNCTION f() RETURNS int AS $body$
BEGIN
  RETURN 1;
END;
$body$ LANGUAGE plpgsql;
SELECT $$dollar $inner$ text$$;
` },
  { language: "erlang", code: `-module(hello).
-export([start/0]).
start() -> io:format("Hello ~p~n", [world]).
` },
  { language: "http", code: `POST /api HTTP/1.1
Host: example.com
Content-Type: application/json

{"a": 1, "b": [true, null]}
` },
  { language: "xml", code: `<div><script>var a = "<b>";</script><style>p { color: red }</style></div>
` },
  { language: "handlebars", code: `<div class="{{cls}}">{{#each items}}<b>{{this}}</b>{{/each}}</div>
` },
  { language: "cpp", code: `auto s = R"x(a)x" R"(b)";
` },
  { language: "ruby", code: `x = <<-EOS
  indented #{y}
  EOS
` },
  { language: "bash", code: `cat <<-'END'
	text $not
	END
` },
  { language: "plaintext", code: `just text <b> & stuff
` },
  { language: "vbscript-html", code: `<p><% Response.Write "hi" %></p>
` },
  { language: "js", code: `obj.return.if; x.for = 1;` },
  { language: "TS", code: `let x: number = 1;` },
  { language: "py", code: `def f(): pass` },
  { language: "unknown-language", code: `nothing` },
  { language: "python", code: "" },
  { language: "python", code: "\n\n" },
  { language: "javascript", code: "const s = \"unterminated\nnext line" },
  { language: "python", code: "print('é ✓ 😀 \\u00e9')  # ünïcödé 😀\n" },
];

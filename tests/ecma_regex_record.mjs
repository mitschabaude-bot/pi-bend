// Test-only oracle (tests/ecma_regex_check.py): record RegExp exec calls made by highlight.js 10.7.3 while highlighting
// snippets in the eager languages; write cases with JS results (indices).
import hljs from "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/highlight.js/lib/core.js";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const base = "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/highlight.js/lib/languages/";
const langs = ["python","java","go","javascript","cpp","typescript","php","ruby","c","csharp","nix","bash","rust","scala","kotlin","swift","dart","groovy","perl","lua"];
for (const l of langs) hljs.registerLanguage(l, require(base + l + ".js"));
const snippets = {
  python: 'def f(x: int) -> str:\n    """doc"""\n    return f"{x!r}" if x > 0 else None  # c\n@dec\nclass A(B): pass\n',
  java: 'public class A<T> extends B { @Override public int f(int x) { return x * 2; } // c\n String s = "a\\"b"; }',
  go: 'package main\nimport "fmt"\nfunc main() { x := []int{1, 2}; fmt.Println(x) } // c\n',
  javascript: 'const f = async (a, {b}) => { return `t ${a + 1}` }; /* c */ class X extends Y { static #p = 1 }\nlet r = /a[b]c/gi;\n',
  cpp: '#include <vector>\ntemplate<typename T> int f(T x) { return std::max(x, 0); } // c\n',
  typescript: 'interface A { x: number } function f<T>(a: T): T { return a as T } type U = A | null;\n',
  php: '<?php\nfunction f($x) { return $x ?? "d"; } // c\necho <<<EOT\nhi\nEOT;\n',
  ruby: 'def f(x)\n  puts "v #{x}" if x > 0\nend\n# c\n:sym\n@ivar = [1, 2].map { |y| y * 2 }\n',
  c: 'int main(void) { printf("%d\\n", 1); return 0; } /* c */\n#define X 1\n',
  csharp: 'public class A { public int F(int x) => x * 2; } // c\nvar s = $"v {x}";\n',
  nix: '{ pkgs ? import <nixpkgs> {} }: pkgs.mkShell { buildInputs = [ pkgs.hello ]; } # c\n',
  bash: '#!/bin/bash\nfor f in *.txt; do echo "$f ${x:-y}"; done # c\nif [ -n "$a" ]; then exit 1; fi\n',
  rust: 'fn main() { let v: Vec<i32> = vec![1, 2]; println!("{:?}", v); } // c\nimpl<T> Tr for S<T> {}\n',
  scala: 'object A { def f(x: Int): Int = x * 2 } // c\ncase class P(a: String)\n',
  kotlin: 'fun main() { val x = listOf(1, 2); println("v $x") } // c\ndata class P(val a: Int)\n',
  swift: 'func f(_ x: Int) -> Int { return x * 2 } // c\nlet s = "v \\(x)"\nstruct P { var a: Int }\n',
  dart: 'void main() { var x = [1, 2]; print("v $x"); } // c\nclass A extends B {}\n',
  groovy: 'def f(x) { return "v ${x}" } // c\nclass A { String s = \'a\' }\n',
  perl: 'my $x = 1; print "v $x\\n" if $x =~ /a+/; # c\nsub f { return @_; }\n',
  lua: 'local function f(x) return x * 2 end -- c\nprint("v" .. f(1))\n',
};
const cases = new Map();
const original = RegExp.prototype.exec;
let recording = true;
RegExp.prototype.exec = function (input) {
  const lastIndex = this.lastIndex;
  const result = original.call(this, input);
  if (recording && typeof input === "string") {
    const key = this.source + "\u0000" + this.flags + "\u0000" + input + "\u0000" + lastIndex;
    if (!cases.has(key) && cases.size < 40000) cases.set(key, { source: this.source, flags: this.flags, input, lastIndex });
  }
  return result;
};
for (const l of langs) hljs.highlight(snippets[l], { language: l, ignoreIllegals: true });
recording = false;
RegExp.prototype.exec = original;
const enc = (s) => [...s].map((c) => c.codePointAt(0)).join(" ");
const lines = [], expected = [];
for (const c of cases.values()) {
  const flags = c.flags.replace("d", "");
  const sticky = /[gy]/.test(flags);
  const re = new RegExp(c.source, flags + "d");
  re.lastIndex = sticky ? c.lastIndex : 0;
  const m = re.exec(c.input);
  const last = sticky ? c.lastIndex : 0;
  lines.push([enc(flags), enc(c.source), enc(c.input), String(last)].join("|"));
  expected.push(m ? m.indices.map((x) => (x ? x[0] + "-" + x[1] : "u")).join(" ") : "null");
}
const fs = await import("fs");
fs.writeFileSync(process.argv[2] + "/cases.txt", lines.join("\n") + "\n");
fs.writeFileSync(process.argv[2] + "/expected.txt", expected.join("\n") + "\n");
console.log(cases.size, "cases");

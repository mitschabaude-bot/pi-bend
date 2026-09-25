import Base
import ../packages/runtime/src/ecma-regex.bend as Re

# ECMAScript RegExp semantics against results recorded from JavaScript
# (node, with the d flag for capture indices); highlight.js workloads are
# compared in tests/ecma_regex_check.py.

def spanText(span: Maybe<&2, Re.Span>) -> String:
  match span:
    case None{}: "u"
    case Some{Re.Span{start, end}}: Nat.show(start) ++ "-" ++ Nat.show(end)
def spans(values: List<&2, Maybe<&2, Re.Span>>) -> String:
  match values:
    case Nil{}: ""
    case value <> rest: " " ++ spanText(value) ++ spans(rest)
def shown(result: Maybe<&2, Re.Match>) -> String:
  match result:
    case None{}: "null"
    case Some{Re.Match{index, end, captures}}: Nat.show(index) ++ "-" ++ Nat.show(end) ++ spans(captures)
def ran(compiled: Result<&2, &2, Re.Error, Re.RegExp>, input: String, last: Nat) -> String:
  match compiled:
    case Fail{Re.SyntaxError{message}}: "error: " ++ message
    case Done{regex}: shown(Re.exec(regex, input, last))
def run(pattern: String, flags: String, input: String, last: Nat) -> String: ran(Re.compile(pattern, flags), input, last)
def check(+actual: String, +expected: String, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), String.eq(actual, expected), _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ actual ++ " expected " ++ expected))(Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    check(run("a(b+)c", "", "xxabbbcx", 0n), "2-7 3-6", "a(b+)c /")
    check(run("(?<=\\$)\\d+", "", "cost $42 now", 0n), "6-8", "(?<=\\$)\\d+ /")
    check(run("(\\w)\\1", "", "abccd", 0n), "2-4 2-3", "(\\w)\\1 /")
    check(run("^(?:foo|bar)+?$", "", "foobarfoo", 0n), "0-9", "^(?:foo|bar)+?$ /")
    check(run("a|ab|abc", "", "abc", 0n), "0-1", "a|ab|abc /")
    check(run("(a*)*b", "", "aaab", 0n), "0-4 0-3", "(a*)*b /")
    check(run("\\bis\\b", "i", "This IS it", 0n), "5-7", "\\bis\\b /i")
    check(run("[^a-c]+", "", "abcxyzab", 0n), "3-6", "[^a-c]+ /")
    check(run("x(?!y)", "", "xyxz", 0n), "2-3", "x(?!y) /")
    check(run("(a)|b", "", "b", 0n), "0-1 u", "(a)|b /")
    check(run("\\d{2,3}", "y", "12345", 1n), "1-4", "\\d{2,3} /y")
    check(run("(?<year>\\d{4})-\\k<year>", "", "1999-1999", 0n), "0-9 0-4", "(?<year>\\d{4})-\\k<year> /")
    check(run("(?<!a)b", "", "abcb", 0n), "3-4", "(?<!a)b /")
    check(run("^b$", "m", "a\nb\nc", 0n), "2-3", "^b$ /m")
    check(run("a.c", "s", "a\nc", 0n), "0-3", "a.c /s")
    check(run("a.c", "", "a\nc", 0n), "null", "a.c /")
    check(run("(z)((a+)?(b+)?(c))*", "", "zaacbbbcac", 0n), "0-10 0-1 8-10 8-9 u 9-10", "(z)((a+)?(b+)?(c))* /")
    check(run("\\x41\\u0042\\103", "", "xABC", 0n), "1-4", "\\x41\\u0042\\103 /")
    check(run("[\\d-z]+", "", "1-z2", 0n), "0-4", "[\\d-z]+ /")
    check(run("a{,2}", "", "a{,2}", 0n), "0-5", "a{,2} /")
    check(run("(?:a|b)*?c", "", "ababc", 0n), "0-5", "(?:a|b)*?c /")
    check(run("(?=(a+))a*b\\1", "", "baaabac", 0n), "3-6 3-4", "(?=(a+))a*b\\1 /")
    check(run("\\8", "", "8", 0n), "0-1", "\\8 /")
    check(run("[\\p{P}\\p{S}]+", "u", "ab!$€«»x", 0n), "2-7", "[\\p{P}\\p{S}]+ /u")
    check(run("\\P{L}+", "u", "ab12 !c", 0n), "2-6", "\\P{L}+ /u")
    check(run("[^\\s\\p{P}\\p{S}]+", "u", "!!ab1é, x", 0n), "2-6", "[^\\s\\p{P}\\p{S}]+ /u")
    check(run("\\p{gc=Symbol}", "u", "a+", 0n), "1-2", "\\p{gc=Symbol} /u")
    check(run("\\p{General_Category=N}", "u", "a٣", 0n), "1-2", "\\p{General_Category=N} /u")
    check(run("\\p", "", "xp", 0n), "1-2", "\\p /")
    check(run("\\p{Script=Greek}", "u", "", 0n), "error: Invalid property name", "unsupported property")
    check(run("(", "", "", 0n), "error: Unterminated group", "unterminated group")
    check(run("a**", "", "", 0n), "error: Nothing to repeat", "nothing to repeat")

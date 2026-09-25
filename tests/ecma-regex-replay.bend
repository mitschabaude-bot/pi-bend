import Base
import ../packages/runtime/src/ecma-regex.bend as Re
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8

# Replays recorded RegExp exec calls: each line is flags|pattern|input|lastIndex
# with fields as space-separated code points; prints "start-end" per capture
# ("u" when undefined) or "null".
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
# Tail-recursive split (the harness lines hold tens of thousands of scalars).
def splitOn(text: String, +separator: U32, +current: String, +parts: List<&2, String>) -> List<&2, String>:
  match text:
    case SNil{}: List.reverse(&2, String, String.reverse(current) <> parts)
    case SCon{Chr{+code}, +rest}: Bool.pick(Unit -> List<&2, String>, U32.is_eq(code, separator), _ => splitOn(rest, separator, "", String.reverse(current) <> parts), _ => splitOn(rest, separator, SCon{Chr{code}, current}, parts))(Unit{})
def number(text: String, value: Nat) -> Nat:
  match text:
    case SNil{}: value
    case SCon{Chr{code}, rest}: number(rest, value * 10n + U32.to_nat((code - 48 : U32)))
def code(text: String) -> U32: U32.from_nat(number(text, 0n))
def codesOf(parts: List<&2, String>, reversed: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: List.reverse(&2, U32, reversed)
    case part <> rest: codesOf(rest, code(part) <> reversed)
def field(text: String) -> String:
  Re.fromCodes(codesOf(splitOn(text, 32, "", Nil{}), Nil{}))
def fieldOrEmpty(text: String) -> String:
  match text:
    case SNil{}: ""
    case text: field(text)
def fields(parts: List<&2, String>) -> String:
  match parts:
    case flags <> pattern <> input <> last <> Nil{}: ran(Re.compile(fieldOrEmpty(pattern), fieldOrEmpty(flags)), fieldOrEmpty(input), number(last, 0n))
    case _: "bad line"
def lines(values: List<&2, String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case "" <> rest: lines(rest)
    case line <> rest:
      do IO<Unit>:
        IO.print(fields(splitOn(line, 124, "", Nil{})))
        lines(rest)
def casesPath() -> String: "build/ecma-regex/cases.txt"
def main() -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(casesPath())
    lines(splitOn(Utf8.decodeBytes(Result.default(&2, &2, FS.Error, List<&2, U32>, bytes, Nil{})), 10, "", Nil{}))

import Base
import ../packages/coding-agent/src/core/tools/diff.bend as Diff
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/test/utf8-runner.bend as Wire

def keys(values: List<&2,String>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: Wire.showText(value)
    case value <> rest: Wire.showText(value) ++ ";" ++ keys(rest)
def kind(value: Diff.ChangeKind) -> String:
  match value:
    case Diff.Same{}: "="
    case Diff.Added{}: "+"
    case Diff.Removed{}: "-"
def changes(values: List<&2,Diff.Change>) -> String:
  match values:
    case Nil{}: ""
    case Diff.Change{tag,words} <> Nil{}: kind(tag) ++ ":" ++ keys(words)
    case Diff.Change{tag,words} <> rest: kind(tag) ++ ":" ++ keys(words) ++ "|" ++ changes(rest)
def query(fields: List<&2,String>) -> String:
  match fields:
    case "line" <> old <> newer <> Nil{}: changes(Diff.diffLines(Wire.fromScalars(Wire.parseNumbers(old)),Wire.fromScalars(Wire.parseNumbers(newer))))
    case old <> newer <> Nil{}: changes(Diff.diffWordKeys(Wire.fromScalars(Wire.parseNumbers(old)),Wire.fromScalars(Wire.parseNumbers(newer))))
    case _: "invalid fixture input"
def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(query(Strings.split(value,'/')))
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

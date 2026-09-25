import Base
import ../packages/runtime/src/marked/rules.bend as Rules
import ../packages/runtime/src/ecma-regex.bend as Re

# Every rule source of the marked port with its flags and whether it
# compiles, one per line (tests/marked_rules_check.py compares them with
# marked's own).
def compiles(result: Result<&2,&2,Re.Error,Re.RegExp>) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{Re.SyntaxError{message}}: "error " ++ message
def line(named: Rules.Named) -> String:
  match named:
    case Rules.Named{name,Rules.Edit{+source,+flags}}: name ++ "\t" ++ flags ++ "\t" ++ compiles(Re.compile(source,flags)) ++ "\t" ++ source
def lines(named: List<&2,Rules.Named>) -> List<&2,String>:
  match named:
    case Nil{}: Nil{}
    case first <> rest: line(first) <> lines(rest)
def main() -> IO(Unit):
  IO.print(String.join(lines(Rules.sources()),"\n"))

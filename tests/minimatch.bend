import Base
import ../packages/runtime/src/minimatch.bend as M
import ../packages/runtime/src/string.bend as S

# Differential fixture: each argument is `m<US>path<US>pattern` (prints true,
# false or throw) or `b<US>pattern` (prints the brace expansions joined by
# U+001E, with backslash, CR and LF escaped so each answer is one line).
def render(result: Result<&2, &2, M.Error, Bool>) -> String:
  match result:
    case Done{True{}}: "true"
    case Done{False{}}: "false"
    case Fail{_}: "throw"

def joinedGo(values: List<&2, String>, acc: String) -> String:
  match values:
    case Nil{}: String.reverse(acc)
    case value <> Nil{}: String.reverse(String.append(String.reverse(value), acc))
    case value <> rest: joinedGo(rest, SCon{Chr{30}, String.append(String.reverse(value), acc)})

def escapeLines(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{92}, rest}: escapeLines(rest, SCon{Chr{92}, SCon{Chr{92}, reversed}})
    case SCon{Chr{10}, rest}: escapeLines(rest, SCon{'n', SCon{Chr{92}, reversed}})
    case SCon{Chr{13}, rest}: escapeLines(rest, SCon{'r', SCon{Chr{92}, reversed}})
    case SCon{char, rest}: escapeLines(rest, SCon{char, reversed})

def fields(parts: List<&2, String>) -> String:
  match parts:
    case "m" <> path <> pattern <> Nil{}: render(M.tryMinimatch(path, pattern))
    case "b" <> pattern <> Nil{}: escapeLines(joinedGo(M.braceExpand(pattern), ""), "")
    case _: "invalid-request"

def queries(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        _ : Unit <- IO.print(fields(S.split(text, Chr{31})))
        queries(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    queries(args)

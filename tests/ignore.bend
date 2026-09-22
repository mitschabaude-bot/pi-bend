import Base
import ../packages/runtime/src/ignore.bend as I
import ../packages/runtime/src/string.bend as S

def render(result: Result<&2,&2,I.Error,I.Decision>) -> String:
  match result:
    case Fail{I.InvalidPath{_}}: "invalid-path"
    case Fail{_}: "invalid-pattern"
    case Done{I.Decision{True{},_}}: "ignored"
    case Done{I.Decision{False{},True{}}}: "unignored"
    case _: "included"
def query(path: String,result: Result<&2,&2,I.Error,I.Matcher>) -> String:
  match result:
    case Fail{_}: "invalid-pattern"
    case Done{matcher}: render(I.test(matcher,path))
def fields(parts: List<&2,String>) -> String:
  match parts:
    case mode <> path <> patterns: query(path,I.add(I.new(S.equal(mode,"1")),patterns))
    case _: "invalid-request"
def queries(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        _ : Unit <- IO.print(fields(S.split(text,Chr{31})))
        queries(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    queries(args)

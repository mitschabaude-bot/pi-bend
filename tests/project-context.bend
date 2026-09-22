import Base
import ../packages/coding-agent/src/core/resource-loader.bend as L
import ../packages/coding-agent/src/core/footer-data-provider.bend as G
import ../packages/coding-agent/src/core/system-prompt.bend as P
import ../packages/coding-agent/src/core/diagnostics.bend as D
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties

def environment(cwd: String, home: String) -> Paths.Environment:
  Paths.Environment{cwd,home,URL.Context{IDNA.Context{Mapping.table(),Normalization.tables(),Properties.table()},IDNA.Options{IDNA.LabelOptions{False{},False{},True{},IDNA.Nontransitional{}},True{},False{}}}}
def get(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def file(value: P.ContextFile) -> String:
  match value:
    case P.ContextFile{path,content}: "{\"path\":" ++ Json.quote(path) ++ ",\"content\":" ++ Json.quote(content) ++ "}"
def files(values: List<&2,P.ContextFile>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: file(value) <> files(rest)
def issues(values: List<&2,D.ResourceDiagnostic>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case D.ResourceDiagnostic{_,message,path,_} <> rest: ("{\"message\":" ++ Json.quote(message) ++ ",\"path\":" ++ Json.quote(Maybe.default(&2,String,path,"")) ++ "}") <> issues(rest)
def report(value: L.ContextFiles) -> IO(Unit):
  match value:
    case L.ContextFiles{values,warnings}: IO.print("{\"files\":[" ++ String.join(files(values),",") ++ "],\"diagnostics\":[" ++ String.join(issues(warnings),",") ++ "]}")
def git(value: Maybe<&2,G.GitPaths>) -> String:
  match value:
    case None{}: "null"
    case Some{G.GitPaths{repo,common,head}}: "{\"repoDir\":" ++ Json.quote(repo) ++ ",\"commonGitDir\":" ++ Json.quote(common) ++ ",\"headPath\":" ++ Json.quote(head) ++ "}"
def request(mode: String,+value: V.Value) -> IO(Unit):
  match mode:
    case "git":
      do IO<Unit>:
        result : Maybe<&2,G.GitPaths> <- G.findGitPaths(text(get(value,"cwd")))
        IO.print(git(result))
    case _:
      do IO<Unit>:
        result : L.ContextFiles <- L.loadProjectContextFiles(environment(text(get(value,"environmentCwd")),text(get(value,"home"))),L.Options{text(get(value,"cwd")),text(get(value,"agentDir"))})
        report(result)
def parsed(value: Result<&2,&2,Json.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit,1,"Invalid fixture JSON")
    case Done{+value}: request(text(get(value,"mode")),value)
def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        parsed(Json.parse(value))
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(values)

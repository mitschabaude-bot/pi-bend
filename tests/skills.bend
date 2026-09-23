import Base
import ../packages/coding-agent/src/core/skills.bend as S
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
def boolean(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}
def strings(values: List<&2,V.Value>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case V.Text{value} <> rest: value <> strings(rest)
    case _ <> rest: strings(rest)
def list(value: V.Value) -> List<&2,String>:
  match value:
    case V.ArrayValue{values}: strings(values)
    case _: Nil{}
def optional(key: String,value: Maybe<&2,String>) -> String:
  match value:
    case None{}: ""
    case Some{value}: "," ++ Json.quote(key) ++ ":" ++ Json.quote(value)
def scope(value: S.SourceScope) -> String:
  match value:
    case S.User{}: "user"
    case S.Project{}: "project"
    case S.Temporary{}: "temporary"
def origin(value: S.SourceOrigin) -> String:
  match value:
    case S.Package{}: "package"
    case S.TopLevel{}: "top-level"
def sourceInfo(value: S.SourceInfo) -> String:
  match value:
    case S.SourceInfo{path,source,which,from,baseDir}: "{\"path\":" ++ Json.quote(path) ++ ",\"source\":" ++ Json.quote(source) ++ ",\"scope\":" ++ Json.quote(scope(which)) ++ ",\"origin\":" ++ Json.quote(origin(from)) ++ optional("baseDir",baseDir) ++ "}"
def skill(value: S.Skill) -> String:
  match value:
    case S.Skill{name,description,path,base,source,disabled}:
      "{\"name\":" ++ Json.quote(name) ++ ",\"description\":" ++ Json.quote(description) ++ ",\"filePath\":" ++ Json.quote(path) ++ ",\"baseDir\":" ++ Json.quote(base) ++ ",\"sourceInfo\":" ++ sourceInfo(source) ++ ",\"disableModelInvocation\":" ++ Bool.pick(String,disabled,"true","false") ++ "}"
def skills(values: List<&2,S.Skill>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: skill(value) <> skills(rest)
def resource(value: D.ResourceType) -> String:
  match value:
    case D.Skill{}: "skill"
    case D.Prompt{}: "prompt"
    case D.Extension{}: "extension"
    case D.Theme{}: "theme"
def collision(value: Maybe<&2,D.ResourceCollision>) -> String:
  match value:
    case None{}: ""
    case Some{D.ResourceCollision{resourceType,name,winner,loser,ws,ls}}:
      ",\"collision\":{\"resourceType\":" ++ Json.quote(resource(resourceType)) ++ ",\"name\":" ++ Json.quote(name) ++ ",\"winnerPath\":" ++ Json.quote(winner) ++ ",\"loserPath\":" ++ Json.quote(loser) ++ optional("winnerSource",ws) ++ optional("loserSource",ls) ++ "}"
def kind(value: D.DiagnosticType) -> String:
  match value:
    case D.Warning{}: "warning"
    case D.Error{}: "error"
    case D.Collision{}: "collision"
def diagnostic(value: D.ResourceDiagnostic) -> String:
  match value:
    case D.ResourceDiagnostic{tag,message,path,details}: "{\"type\":" ++ Json.quote(kind(tag)) ++ ",\"message\":" ++ Json.quote(message) ++ optional("path",path) ++ collision(details) ++ "}"
def diagnostics(values: List<&2,D.ResourceDiagnostic>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: diagnostic(value) <> diagnostics(rest)
def report(value: S.LoadSkillsResult) -> IO(Unit):
  match value:
    case S.LoadSkillsResult{values,issues}: IO.print("{\"skills\":[" ++ String.join(skills(values),",") ++ "],\"diagnostics\":[" ++ String.join(diagnostics(issues),",") ++ "]}")
def request(mode: String,+value: V.Value) -> IO(Unit):
  match mode:
    case "dir":
      do IO<Unit>:
        result : S.LoadSkillsResult <- S.loadSkillsFromDir(S.LoadSkillsFromDirOptions{text(get(value,"dir")),text(get(value,"source"))})
        report(result)
    case "load":
      do IO<Unit>:
        result : S.LoadSkillsResult <- S.loadSkills(environment(text(get(value,"environmentCwd")),text(get(value,"home"))),S.LoadSkillsOptions{text(get(value,"cwd")),text(get(value,"agentDir")),list(get(value,"skillPaths")),boolean(get(value,"includeDefaults"))})
        report(result)
    case _: IO.die(Unit,1,"Invalid fixture command")
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

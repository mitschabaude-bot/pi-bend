import Base
import ../packages/coding-agent/src/core/settings-manager.bend as S
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson

def get(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def trusted(value: V.Value) -> Bool:
  match value:
    case V.Boolean{False{}}: False{}
    case _: True{}
def project(value: V.Value) -> Bool:
  match value:
    case V.Boolean{True{}}: True{}
    case _: False{}
def errorName(value: S.Error) -> String:
  match value:
    case S.InvalidJson{_}: "json"
    case S.InvalidSetting{_}: "setting"
    case S.DuplicateSetting{_}: "duplicate"
    case S.UntrustedProject{}: "untrusted"
    case S.StorageFailure{_}: "storage"
    case S.FileFailure{_}: "filesystem"
    case S.InvalidEncoding{_}: "utf8"
    case S.LockFailure{_}: "lock"
    case S.CleanupFailure{_,_}: "cleanup"
def errorValue(value: S.SettingsError) -> V.Value:
  match value:
    case S.SettingsError{S.Global{},_,cause}: V.Text{"global." ++ errorName(cause)}
    case S.SettingsError{S.Project{},_,cause}: V.Text{"project." ++ errorName(cause)}
def errorPath(value: S.SettingsError) -> V.Value:
  match value:
    case S.SettingsError{_,None{},_}: V.Null{}
    case S.SettingsError{_,Some{path},_}: V.Text{path}
def output(value: S.SettingsManager & List<&2,S.SettingsError>) -> IO(Unit):
  match value:
    case (+state,+issues):
      IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(V.ObjectValue{R.Record{R.Property{"global",S.toValue(S.getGlobalSettings(state))} <> R.Property{"project",S.toValue(S.getProjectSettings(state))} <> R.Property{"errors",V.ArrayValue{S.encodeValues(~S.SettingsError,~errorValue,issues,Nil{})}} <> R.Property{"errorPaths",V.ArrayValue{S.encodeValues(~S.SettingsError,~errorPath,issues,Nil{})}} <> Nil{}}})),"null"))

def finished(value: S.FileSettingsStorage & S.SettingsManager) -> IO(Unit):
  match value:
    case (_,state): output(S.drainErrors(state))
def updated(result: S.Outcome(S.SettingsManager),storage: S.FileSettingsStorage,state: S.SettingsManager) -> IO(Unit):
  match result:
    case Fail{cause}: output((state,S.SettingsError{S.Global{},None{},cause} <> Nil{}))
    case Done{next}:
      do IO<Unit>:
        result : S.FileSettingsStorage & S.SettingsManager <- S.flush(~S.FileSettingsStorage,~S.fileWithLock,storage,next)
        finished(result)
def selected(result: Result<&2,&2,J.Error,Maybe<&2,S.Setting>>,project: Bool,storage: S.FileSettingsStorage,+state: S.SettingsManager) -> IO(Unit):
  match result:
    case Fail{cause}: updated(Fail{S.InvalidSetting{cause}},storage,state)
    case Done{None{}}: output(S.drainErrors(state))
    case Done{Some{+value}}: updated(Bool.pick(S.Outcome(S.SettingsManager),project,S.setProject(value,state),S.set(value,state)),storage,state)
def loaded(value: S.FileSettingsStorage & S.SettingsManager,+input: V.Value) -> IO(Unit):
  match value:
    case (storage,state): selected(S.knownField(text(get(input,"key")),get(input,"value")),project(get(input,"project")),storage,state)
def run(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit,1,"Invalid fixture JSON")
    case Done{+input}:
      do IO<Unit>:
        value : S.FileSettingsStorage & S.SettingsManager <- S.create(text(get(input,"cwd")),text(get(input,"agentDir")),S.SettingsManagerCreateOptions{trusted(get(input,"trusted"))})
        loaded(value,input)
def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        run(J.parse(value))
        args(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)

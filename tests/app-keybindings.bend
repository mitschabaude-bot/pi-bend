import Base
import ../packages/tui/src/keys.bend as K
import ../packages/coding-agent/src/core/keybindings.bend as A
import ../packages/tui/src/keybindings.bend as Tui
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/filesystem.bend as FS
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
def optionalText(value: V.Value) -> Maybe<&2,String>:
  match value:
    case V.Text{value}: Some{value}
    case _: None{}
def renderedKeys(keys: List<&2,K.KeyId>) -> List<&2,V.Value>:
  match keys:
    case Nil{}: Nil{}
    case key <> rest: V.Text{K.formatKeyId(key)} <> renderedKeys(rest)
def descriptionOutput(value: Maybe<&2,String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: V.Text{value}
def keyList(items: List<&2,V.Value>) -> List<&2,K.KeyId>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: Maybe.default(&2,List<&2,K.KeyId>,Maybe.map(&2,K.KeyId,List<&2,K.KeyId>,key => key <> keyList(rest),K.parseKeyId(text(item))),Nil{})
def keyOutput(keys: List<&2,K.KeyId>) -> V.Value: V.ArrayValue{renderedKeys(keys)}
def inputKeys(value: V.Value) -> List<&2,K.KeyId>:
  match value:
    case V.ArrayValue{items}: keyList(items)
    case V.Text{value}: keyList(V.Text{value} <> Nil{})
    case _: Nil{}
def propertyOutput(value: R.Property<List<&2,K.KeyId>>) -> R.Property<V.Value>:
  match value:
    case R.Property{name,keys}: R.Property{name,keyOutput(keys)}
def definitionOutput(value: Maybe<&2,Tui.KeybindingDefinition>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Tui.KeybindingDefinition{keys,description}}: V.ObjectValue{R.Record{R.Property{"defaultKeys",keyOutput(keys)} <> R.Property{"description",descriptionOutput(description)} <> Nil{}}}
def configFields(fields: List<&2,R.Property<V.Value>>) -> List<&2,R.Property<List<&2,K.KeyId>>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{name,value} <> rest: R.Property{name,inputKeys(value)} <> configFields(rest)
def renderedConfig(items: List<&2,R.Property<List<&2,K.KeyId>>>) -> List<&2,R.Property<V.Value>>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: propertyOutput(item) <> renderedConfig(rest)
def config(value: V.Value) -> Tui.KeybindingsConfig():
  match value:
    case V.ObjectValue{fields}: R.Record{configFields(R.entries(V.Value,fields))}
    case _: R.new(List<&2,K.KeyId>)
def configOutput(value: Tui.KeybindingsConfig()) -> V.Value:
  V.ObjectValue{R.Record{renderedConfig(R.entries(List<&2,K.KeyId>,value))}}
def environment(+value: V.Value) -> A.Environment:
  A.Environment{Maybe.default(&2,String,optionalText(get(value,"platform")),"linux"),optionalText(get(value,"wslDistroName")),optionalText(get(value,"wslInterop"))}
def object(value: V.Value) -> R.Record<V.Value>:
  match value:
    case V.ObjectValue{fields}: fields
    case _: R.new(V.Value)
def definitionFields(items: List<&2,R.Property<Tui.KeybindingDefinition>>) -> List<&2,R.Property<V.Value>>:
  match items:
    case Nil{}: Nil{}
    case R.Property{name,value} <> rest: R.Property{name,definitionOutput(Some{value})} <> definitionFields(rest)
def definitions(value: Tui.KeybindingDefinitions()) -> V.Value: V.ObjectValue{R.Record{definitionFields(R.entries(Tui.KeybindingDefinition,value))}}
def migration(value: A.Migration) -> V.Value:
  match value:
    case A.Migration{config,migrated}: V.ObjectValue{R.Record{R.Property{"config",V.ObjectValue{config}} <> R.Property{"migrated",V.Boolean{migrated}} <> Nil{}}}
def userBindings(manager: A.KeybindingsManager) -> Tui.KeybindingsConfig():
  match manager:
    case A.KeybindingsManager{bindings,_,_}: Tui.getUserBindings(bindings)
def snapshot(+manager: A.KeybindingsManager) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"user",configOutput(userBindings(manager))} <> R.Property{"effective",configOutput(A.getEffectiveConfig(manager))} <> Nil{}}}
def errorName(value: A.Error) -> String:
  match value:
    case A.Filesystem{_}: "filesystem"
    case A.Encoding{_}: "utf8"
    case A.InvalidJson{_}: "json"
    case A.InvalidRoot{}: "invalid-config"
    case A.InvalidBinding{_}: "invalid-binding"
    case A.InvalidKey{_,_}: "invalid-key"
def error(value: A.Error) -> V.Value: V.ObjectValue{R.Record{R.Property{"error",V.Text{errorName(value)}} <> Nil{}}}
def outcome(value: Result<&2,&2,A.Error,A.KeybindingsManager>) -> V.Value:
  match value:
    case Done{manager}: snapshot(manager)
    case Fail{cause}: error(cause)
def reloadOutput(+before: A.KeybindingsManager,after: Result<&2,&2,A.Error,A.KeybindingsManager>) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"before",snapshot(before)} <> R.Property{"retained",snapshot(before)} <> R.Property{"after",outcome(after)} <> Nil{}}}
def rewritten(result: Result<&2,&2,FS.Error,Unit>,+manager: A.KeybindingsManager) -> IO(V.Value):
  match result:
    case Fail{_}: IO.die(V.Value,1,"Fixture reload write failed")
    case Done{_}:
      do IO<V.Value>:
        after : Result<&2,&2,A.Error,A.KeybindingsManager> <- A.reload(manager)
        IO.pure(V.Value,reloadOutput(manager,after))
def loadedForReload(result: Result<&2,&2,A.Error,A.KeybindingsManager>,path: String,replacement: String) -> IO(V.Value):
  match result:
    case Fail{cause}: IO.pure(V.Value,error(cause))
    case Done{manager}:
      do IO<V.Value>:
        written : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(path,replacement)
        rewritten(written,manager)
def query(method: String,+value: V.Value) -> IO(V.Value):
  match method:
    case "windows": IO.pure(V.Value,V.Boolean{A.useWindowsKeybindings(environment(get(value,"environment")))})
    case "definitions": IO.pure(V.Value,definitions(A.KEYBINDINGS(environment(get(value,"environment")))))
    case "migration": IO.pure(V.Value,migration(A.migrateKeybindingsConfig(environment(get(value,"environment")),object(get(value,"config")))))
    case "memory": IO.pure(V.Value,snapshot(A.inMemory(environment(get(value,"environment")),config(get(value,"config")))))
    case "file":
      do IO<V.Value>:
        result : Result<&2,&2,A.Error,A.KeybindingsManager> <- A.create(environment(get(value,"environment")),text(get(value,"agentDir")))
        IO.pure(V.Value,outcome(result))
    case "reload":
      do IO<V.Value>:
        result : Result<&2,&2,A.Error,A.KeybindingsManager> <- A.create(environment(get(value,"environment")),text(get(value,"agentDir")))
        loadedForReload(result,text(get(value,"agentDir")) ++ "/keybindings.json",text(get(value,"replacement")))
    case _: IO.pure(V.Value,V.Null{})
def queries(items: List<&2,V.Value>,reversed: List<&2,V.Value>) -> IO(V.Value):
  match items:
    case Nil{}: IO.pure(V.Value,V.ArrayValue{List.reverse(&2,V.Value,reversed)})
    case +item <> rest:
      do IO<V.Value>:
        result : V.Value <- query(text(get(item,"method")),item)
        queries(rest,result <> reversed)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{items}}:
      do IO<Unit>:
        result : V.Value <- queries(items,Nil{})
        IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(result)),"null"))
    case _: IO.die(Unit,1,"Invalid app keybindings fixture input")
def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case input <> rest:
      do IO<Unit>:
        program(J.parse(input))
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

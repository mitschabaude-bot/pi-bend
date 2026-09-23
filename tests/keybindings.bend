import Base
import ../packages/tui/src/keys.bend as K
import ../packages/tui/src/keybindings.bend as B
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
def flag(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}
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
def renderedStrings(items: List<&2,String>) -> List<&2,V.Value>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: V.Text{item} <> renderedStrings(rest)
def keyList(items: List<&2,V.Value>) -> List<&2,K.KeyId>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: Maybe.default(&2,List<&2,K.KeyId>,Maybe.map(&2,K.KeyId,List<&2,K.KeyId>,key => key <> keyList(rest),K.parseKeyId(text(item))),Nil{})
def keyOutput(keys: List<&2,K.KeyId>) -> V.Value: V.ArrayValue{renderedKeys(keys)}
def conflictOutput(value: B.KeybindingConflict) -> V.Value:
  match value:
    case B.KeybindingConflict{key,actions}: V.ObjectValue{R.Record{R.Property{"key",V.Text{K.formatKeyId(key)}} <> R.Property{"keybindings",V.ArrayValue{renderedStrings(actions)}} <> Nil{}}}
def context(+value: V.Value) -> K.Context: K.Context{flag(get(value,"kitty")),flag(get(value,"windows"))}
def keys(value: V.Value) -> List<&2,K.KeyId>:
  match value:
    case V.ArrayValue{items}: keyList(items)
    case V.Text{value}: keyList(V.Text{value} <> Nil{})
    case _: Nil{}
def propertyOutput(value: R.Property<List<&2,K.KeyId>>) -> R.Property<V.Value>:
  match value:
    case R.Property{name,keys}: R.Property{name,keyOutput(keys)}
def definitionOutput(value: Maybe<&2,B.KeybindingDefinition>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{B.KeybindingDefinition{keys,description}}: V.ObjectValue{R.Record{R.Property{"defaultKeys",keyOutput(keys)} <> R.Property{"description",descriptionOutput(description)} <> Nil{}}}
def renderedConflicts(items: List<&2,B.KeybindingConflict>) -> List<&2,V.Value>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: conflictOutput(item) <> renderedConflicts(rest)
def configFields(fields: List<&2,R.Property<V.Value>>) -> List<&2,R.Property<List<&2,K.KeyId>>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{name,value} <> rest: R.Property{name,keys(value)} <> configFields(rest)
def definition(+value: V.Value) -> B.KeybindingDefinition: B.KeybindingDefinition{keys(get(value,"defaultKeys")),optionalText(get(value,"description"))}
def renderedConfig(items: List<&2,R.Property<List<&2,K.KeyId>>>) -> List<&2,R.Property<V.Value>>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: propertyOutput(item) <> renderedConfig(rest)
def config(value: V.Value) -> B.KeybindingsConfig():
  match value:
    case V.ObjectValue{fields}: R.Record{configFields(R.entries(V.Value,fields))}
    case _: R.new(List<&2,K.KeyId>)
def definitionFields(fields: List<&2,R.Property<V.Value>>) -> List<&2,R.Property<B.KeybindingDefinition>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{name,value} <> rest: R.Property{name,definition(value)} <> definitionFields(rest)
def configOutput(value: B.KeybindingsConfig()) -> V.Value:
  V.ObjectValue{R.Record{renderedConfig(R.entries(List<&2,K.KeyId>,value))}}
def definitions(value: V.Value) -> B.KeybindingDefinitions():
  match value:
    case V.ObjectValue{fields}: R.Record{definitionFields(R.entries(V.Value,fields))}
    case _: B.TUI_KEYBINDINGS()
def query(method: String,+manager: B.KeybindingsManager,+input: V.Value) -> V.Value:
  match method:
    case "getKeys": keyOutput(B.getKeys(manager,text(get(input,"action"))))
    case "getDefinition": definitionOutput(B.getDefinition(manager,text(get(input,"action"))))
    case "getConflicts": V.ArrayValue{renderedConflicts(B.getConflicts(manager))}
    case "getUserBindings": configOutput(B.getUserBindings(manager))
    case "getResolvedBindings": configOutput(B.getResolvedBindings(manager))
    case "matches": V.Boolean{B.matches(manager,context(input),text(get(input,"data")),text(get(input,"action")))}
    case _: V.Null{}
def replaced(replacement: V.Value,manager: B.KeybindingsManager) -> B.KeybindingsManager:
  match replacement:
    case V.ObjectValue{fields}: B.setUserBindings(manager,config(V.ObjectValue{fields}))
    case _: manager
def queries(items: List<&2,V.Value>,+manager: B.KeybindingsManager) -> List<&2,V.Value>:
  match items:
    case Nil{}: Nil{}
    case +input <> rest: query(text(get(input,"method")),manager,input) <> queries(rest,manager)
def queryValue(value: V.Value,manager: B.KeybindingsManager) -> V.Value:
  match value:
    case V.ArrayValue{items}: V.ArrayValue{queries(items,manager)}
    case _: V.Null{}
def steps(items: List<&2,V.Value>,manager: B.KeybindingsManager) -> List<&2,V.Value>:
  match items:
    case Nil{}: Nil{}
    case +item <> rest:
      +updated = replaced(get(item,"replace"),manager)
      queryValue(get(item,"queries"),updated) <> steps(rest,updated)
def executeSteps(value: V.Value,manager: B.KeybindingsManager) -> List<&2,V.Value>:
  match value:
    case V.ArrayValue{items}: steps(items,manager)
    case _: Nil{}
def execute(+input: V.Value) -> V.Value:
  V.ArrayValue{executeSteps(get(input,"steps"),B.create(definitions(get(input,"definitions")),config(get(input,"bindings"))))}
def executeAll(items: List<&2,V.Value>) -> List<&2,V.Value>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: execute(item) <> executeAll(rest)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{items}}: IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(V.ArrayValue{executeAll(items)})),"null"))
    case _: IO.die(Unit,1,"Invalid keybindings fixture input")
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


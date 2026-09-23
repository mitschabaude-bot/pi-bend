import Base
import ../packages/tui/src/keys.bend as K
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
    case V.Boolean{True{}}: True{}
    case _: False{}
def output(value: Maybe<&2,String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{text}: V.Text{text}
def matchParsed(value: Maybe<&2,K.KeyId>,context: K.Context,data: String) -> Bool:
  match value:
    case None{}: False{}
    case Some{key}: K.matchesKey(context,data,key)
def context(+value: V.Value) -> K.Context: K.Context{flag(get(value,"kitty")),flag(get(value,"windows"))}
def query(method: String,+value: V.Value) -> V.Value:
  match method:
    case "matchesKey": V.Boolean{matchParsed(K.parseKeyId(text(get(value,"key"))),context(value),text(get(value,"data")))}
    case "parseKey": output(Maybe.map(&2,K.KeyId,String,K.formatKeyId,K.parseKey(context(value),text(get(value,"data")))))
    case "parseKeyId": output(Maybe.map(&2,K.KeyId,String,K.formatKeyId,K.parseKeyId(text(get(value,"key")))))
    case "decodeKittyPrintable": output(K.decodeKittyPrintable(text(get(value,"data"))))
    case "decodePrintableKey": output(K.decodePrintableKey(text(get(value,"data"))))
    case "isKeyRelease": V.Boolean{K.isKeyRelease(text(get(value,"data")))}
    case "isKeyRepeat": V.Boolean{K.isKeyRepeat(text(get(value,"data")))}
    case _: V.Null{}
def values(items: List<&2,V.Value>,reversed: List<&2,V.Value>) -> V.Value:
  match items:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case +item <> rest: values(rest,query(text(get(item,"method")),item) <> reversed)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{items}}: IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(values(items,Nil{}))),"null"))
    case _: IO.die(Unit,1,"Invalid keyboard fixture input")
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

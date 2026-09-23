import Base
import ../packages/tui/src/components/editor.bend as E
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/json.bend as J
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
def n(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(value))
    case _: 0n
def obj(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def c(n: Nat) -> V.Value: V.Number{U32.to_f64(U32.from_nat(n))}
def paste(value: V.Value) -> E.Paste: E.Paste{n(value),""}
def pasteList(items: List<&2,V.Value>) -> List<&2,E.Paste>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: paste(item) <> pasteList(rest)
def pastes(value: V.Value) -> List<&2,E.Paste>:
  match value:
    case V.ArrayValue{items}: pasteList(items)
    case _: Nil{}
def chunk(value: E.TextChunk) -> V.Value:
  match value:
    case E.TextChunk{text,start,end}: obj([R.Property{"text",V.Text{text}},R.Property{"startIndex",c(start)},R.Property{"endIndex",c(end)}])
def chunkList(items: List<&2,E.TextChunk>) -> List<&2,V.Value>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: chunk(item) <> chunkList(rest)
def query(+value: V.Value) -> V.Value:
  V.ArrayValue{chunkList(E.wordWrapLineWithMarkers(text(get(value,"text")),n(get(value,"width")),pastes(get(value,"ids"))))}
def queryList(items: List<&2,V.Value>) -> List<&2,V.Value>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: query(item) <> queryList(rest)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{items}}:
      do IO<Unit>:
        result : V.Value <- IO.pure(V.Value,V.ArrayValue{queryList(items)})
        IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(result)),"null"))
    case _: IO.die(Unit,1,"invalid input")
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

import Base
import ../packages/tui/src/tui.bend as Tui
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
def number(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(value))
    case _: 0n
def strings(items: List<&2,V.Value>,reversed: List<&2,String>) -> List<&2,String>:
  match items:
    case Nil{}: List.reverse(&2,String,reversed)
    case value <> rest: strings(rest,text(value) <> reversed)
def lines(value: V.Value) -> List<&2,String>:
  match value:
    case V.ArrayValue{items}: strings(items,Nil{})
    case _: Nil{}
def shown(lines: List<&2,String>,reversed: List<&2,V.Value>) -> V.Value:
  match lines:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case value <> rest: shown(rest,V.Text{value} <> reversed)
def cursor(value: Maybe<&2,Tui.CursorPosition>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Tui.CursorPosition{row,col}}: V.ObjectValue{R.Record{R.Property{"row",V.Number{Tui.dimension(row)}} <> R.Property{"col",V.Number{Tui.dimension(col)}} <> Nil{}}}
def frame(value: Tui.CursorFrame,reset: Bool) -> V.Value:
  match value:
    case Tui.CursorFrame{+lines,position}: V.ObjectValue{R.Record{R.Property{"lines",shown(Bool.pick(Unit -> List<&2,String>,reset,_ => Tui.applyLineResets(lines),_ => lines)(Unit{}),Nil{})} <> R.Property{"cursor",cursor(position)} <> Nil{}}}
def query(method: String,+value: V.Value) -> V.Value:
  match method:
    case "reset": shown(Tui.applyLineResets(lines(get(value,"lines"))),Nil{})
    case "frame": frame(Tui.extractCursorPosition(lines(get(value,"lines")),number(get(value,"height"))),True{})
    case _: frame(Tui.extractCursorPosition(lines(get(value,"lines")),number(get(value,"height"))),False{})
def queries(items: List<&2,V.Value>,reversed: List<&2,V.Value>) -> V.Value:
  match items:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case +value <> rest: queries(rest,query(text(get(value,"op")),value) <> reversed)
def parsed(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{values}}: IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(queries(values,Nil{}))),"null"))
    case _: IO.die(Unit,1,"expected JSON array")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    parsed(J.parse(Maybe.default(&1,String,List.head(&1,String,args),"[]")))

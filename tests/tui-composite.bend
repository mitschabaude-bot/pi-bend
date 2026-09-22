import Base
import ../packages/tui/src/utils.bend as U
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
def repetitions(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(value))
    case _: 0n
def query(method: String,+value: V.Value) -> V.Value:
  V.Text{Tui.compositeTuiLine(text(get(value,"base")),text(get(value,"overlay")),repetitions(get(value,"start")),repetitions(get(value,"width")),repetitions(get(value,"total")))}
def queries(items: List<&2,V.Value>,reversed: List<&2,V.Value>) -> V.Value:
  match items:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case +item <> rest: queries(rest,query(text(get(item,"method")),item) <> reversed)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{items}}: IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(queries(items,Nil{}))),"null"))
    case _: IO.die(Unit,1,"Invalid width fixture input")
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

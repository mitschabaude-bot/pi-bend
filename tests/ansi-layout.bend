import Base
import ../packages/tui/src/utils.bend as U
import ../packages/runtime/src/unicode-17-display.bend as Display
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
def count(value: Nat) -> V.Value: V.Number{U32.to_f64(U32.from_nat(value))}
def digest(remaining: Nat,+point: U32,hash: U32) -> U32:
  match remaining:
    case Zero{}: hash
    case Succ{rest}: digest(rest,U32.add(point,1),U32.mul(U32.xor(hash,Bool.pick(U32,U32.is_eq(U32.and(Display.properties(point),256),0),0,1)),16777619))
def repetitions(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(value))
    case _: 0n
def repeated(remaining: Nat,+text: String,reversed: String) -> String:
  match remaining:
    case Zero{}: U.reverseInto(reversed,"")
    case Succ{rest}: repeated(rest,text,U.prependReversed(text,reversed))
def boolean(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}
def strings(items: List<&2,String>,reversed: List<&2,V.Value>) -> V.Value:
  match items:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case text <> rest: strings(rest,V.Text{text} <> reversed)
def widthResult(value: U.WidthResult) -> V.Value:
  match value:
    case U.WidthResult{text,width}: V.ObjectValue{R.set(V.Value,R.set(V.Value,R.new(V.Value),"text",V.Text{text}),"width",count(width))}
def segmentsResult(value: U.Segments) -> V.Value:
  match value:
    case U.Segments{before,beforeWidth,after,afterWidth}: V.ObjectValue{R.set(V.Value,R.set(V.Value,R.set(V.Value,R.set(V.Value,R.new(V.Value),"before",V.Text{before}),"beforeWidth",count(beforeWidth)),"after",V.Text{after}),"afterWidth",count(afterWidth))}
def preparedText(+value: V.Value) -> String:
  +repeat = repetitions(get(value,"repeat"))
  Bool.pick(Unit -> String,Nat.is_eq(repeat,0n),_ => text(get(value,"text")),_ => repeated(repeat,text(get(value,"text")),""))(Unit{})
def query(method: String,+value: V.Value) -> V.Value:
  match method:
    case "cjkProperties": V.Number{U32.to_f64(digest(1114112n,0,2166136261))}
    case "wrapTextWithAnsi": strings(U.wrapTextWithAnsi(preparedText(value),repetitions(get(value,"width"))),Nil{})
    case "truncateToWidth": V.Text{U.truncateToWidth(preparedText(value),repetitions(get(value,"width")),text(get(value,"ellipsis")),boolean(get(value,"pad")))}
    case "sliceWithWidth": widthResult(U.sliceWithWidth(preparedText(value),repetitions(get(value,"start")),repetitions(get(value,"length")),boolean(get(value,"strict"))))
    case "sliceByColumn": V.Text{U.sliceByColumn(preparedText(value),repetitions(get(value,"start")),repetitions(get(value,"length")),boolean(get(value,"strict")))}
    case "extractSegments": segmentsResult(U.extractSegments(preparedText(value),repetitions(get(value,"before")),repetitions(get(value,"after")),repetitions(get(value,"length")),boolean(get(value,"strict"))))
    case _: V.Null{}
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

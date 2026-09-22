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
    case Succ{rest}: digest(rest,U32.add(point,1),U32.mul(U32.xor(hash,U32.and(Display.properties(point),127)),16777619))
def repetitions(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(value))
    case _: 0n
def repeated(remaining: Nat,+text: String,reversed: String) -> String:
  match remaining:
    case Zero{}: U.reverseInto(reversed,"")
    case Succ{rest}: repeated(rest,text,U.prependReversed(text,reversed))
def query(method: String,+value: V.Value) -> V.Value:
  match method:
    case "width": count(U.visibleWidth(text(get(value,"text"))))
    case "grapheme": count(U.graphemeWidth(text(get(value,"text"))))
    case "emoji": V.Boolean{Display.isRgiEmoji(text(get(value,"text")))}
    case "repeat": count(U.visibleWidth(text(get(value,"prefix")) ++ repeated(repetitions(get(value,"repeat")),text(get(value,"text")),"")))
    case "properties": V.Number{U32.to_f64(digest(1114112n,0,2166136261))}
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

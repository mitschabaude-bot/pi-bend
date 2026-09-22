import Base
import ../packages/tui/src/utils.bend as U
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
def position(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(value))
    case _: 0n
def extracted(value: Maybe<&2,U.AnsiCode>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{U.AnsiCode{code,length}}: V.ObjectValue{R.Record{R.Property{"code",V.Text{code}} <> R.Property{"length",V.Number{U32.to_f64(U32.from_nat(length))}} <> Nil{}}}
def snapshot(+state: U.AnsiCodeTracker) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"codes",V.Text{U.getActiveCodes(state)}} <> R.Property{"background",V.Text{U.getActiveBackgroundCode(state)}} <> R.Property{"reset",V.Text{U.getLineEndReset(state)}} <> R.Property{"active",V.Boolean{U.hasActiveCodes(state)}} <> Nil{}}}
def track(items: List<&2,V.Value>,state: U.AnsiCodeTracker,reversed: List<&2,V.Value>) -> V.Value:
  match items:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case V.Null{} <> rest:
      +next = U.clear(state)
      track(rest,next,snapshot(next) <> reversed)
    case item <> rest:
      +next = U.updateTrackerFromText(text(item),state)
      track(rest,next,snapshot(next) <> reversed)
def tracked(value: V.Value) -> V.Value:
  match value:
    case V.ArrayValue{items}: track(items,U.emptyTracker(),Nil{})
    case _: V.Null{}
def query(method: String,+value: V.Value) -> V.Value:
  match method:
    case "extract": extracted(U.extractAnsiCode(text(get(value,"text")),position(get(value,"position"))))
    case "strip": V.Text{U.stripTerminalSequences(text(get(value,"text")))}
    case "normalize": V.Text{U.normalizeTerminalOutput(text(get(value,"text")))}
    case "background": V.Text{U.getActiveBackgroundAnsi(text(get(value,"text")))}
    case "close": V.Text{U.getActiveOsc8Close(text(get(value,"text")))}
    case "track": tracked(get(value,"items"))
    case _: V.Null{}
def queries(items: List<&2,V.Value>,reversed: List<&2,V.Value>) -> V.Value:
  match items:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case +item <> rest: queries(rest,query(text(get(item,"method")),item) <> reversed)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{items}}: IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(queries(items,Nil{}))),"null"))
    case _: IO.die(Unit,1,"Invalid ANSI fixture input")
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

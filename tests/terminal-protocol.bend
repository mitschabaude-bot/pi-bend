import Base
import ../packages/tui/src/terminal.bend as T
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V

def texts(values: List<&2,String>) -> String:
  match values:
    case Nil{}: ""
    case text <> Nil{}: J.quote(text)
    case text <> rest: J.quote(text) ++ "," ++ texts(rest)
def report(value: T.ProtocolTransition) -> String:
  match value:
    case T.ProtocolTransition{T.Negotiation{kitty,modify,pushed,pending,_},input,output}:
      "{\"kitty\":" ++ Bool.pick(String,kitty,"true","false") ++ ",\"modify\":" ++ Bool.pick(String,modify,"true","false") ++ ",\"pending\":" ++ J.quote(pending) ++ ",\"input\":[" ++ texts(input) ++ "],\"output\":" ++ J.quote(output) ++ "}"
def action(state: T.Negotiation,command: V.Value) -> T.ProtocolTransition:
  match command:
    case V.ArrayValue{V.Number{now} <> V.Text{text} <> Nil{}}: T.protocolInput(U32.to_nat(F64.to_u32(now)),text,state)
    case V.Number{now}: T.protocolTimeout(U32.to_nat(F64.to_u32(now)),state)
    case _: T.disableKeyboard(state)
def runSteps(commands: List<&2,V.Value>,transition: T.ProtocolTransition) -> IO(Unit):
  match commands transition:
    case Nil{} _: IO.pure(Unit,Unit{})
    case command <> rest T.ProtocolTransition{state,_,_}:
      +next = action(state,command)
      do IO<Unit>:
        IO.print(report(next))
        runSteps(rest,next)
def parsed(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{V.Text{"escape"} <> V.Text{configured} <> V.Text{connection} <> V.Text{tty} <> Nil{}}}:
      IO.print(U32.show(T.resolveEscapeTimeoutMs(configured,connection,tty)))
    case Done{V.ArrayValue{V.Text{"normalize"} <> V.Text{text} <> V.Boolean{detect} <> V.Boolean{shift} <> Nil{}}}:
      IO.print(J.quote(T.normalizeNativeShiftEnterInput(text,detect,shift)))
    case Done{V.ArrayValue{steps}}: runSteps(steps,T.ProtocolTransition{T.initialNegotiation(),Nil{},""})
    case _: IO.die(Unit,1,"commands required")
def arguments(values: List<String>) -> IO(Unit):
  match values:
    case argument <> Nil{}: parsed(J.parse(argument))
    case _: IO.die(Unit,1,"commands required")
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

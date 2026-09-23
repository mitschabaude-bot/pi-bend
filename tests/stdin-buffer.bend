import Base
import ../packages/tui/src/stdin-buffer.bend as B
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V

def event(value: B.InputEvent) -> String:
  match value:
    case B.DataEvent{text}: "[\"data\"," ++ J.quote(text) ++ "]"
    case B.PasteEvent{text}: "[\"paste\"," ++ J.quote(text) ++ "]"
def events(values: List<&2,B.InputEvent>,result: List<&2,String>) -> String:
  match values:
    case Nil{}: "[" ++ String.join(List.reverse(&2,String,result),",") ++ "]"
    case value <> rest: events(rest,event(value) <> result)
def delay(value: Maybe<&2,U32>) -> String:
  match value:
    case None{}: "null"
    case Some{ms}: U32.show(ms)
def snapshot(+state: B.StdinBuffer,emitted: List<&2,B.InputEvent>) -> String:
  "{\"events\":" ++ events(emitted,Nil{}) ++ ",\"buffer\":" ++ J.quote(B.getBuffer(state)) ++ ",\"timeout\":" ++ delay(B.pendingTimeout(state,B.defaultOptions())) ++ "}"
def operation(state: B.StdinBuffer,value: V.Value) -> B.Transition:
  match value:
    case V.ArrayValue{V.Text{"process"} <> V.Text{text} <> Nil{}}: B.process(text,state)
    case V.ArrayValue{V.Text{"flush"} <> Nil{}}: B.flush(state)
    case _: B.Transition{B.clear(state),Nil{}}
def collect(steps: List<&2,V.Value>,transition: B.Transition,result: List<&2,String>) -> String:
  match steps transition:
    case Nil{} B.Transition{+state,emitted}: "[" ++ String.join(List.reverse(&2,String,snapshot(state,emitted) <> result),",") ++ "]"
    case next <> rest B.Transition{+state,emitted}: collect(rest,operation(state,next),snapshot(state,emitted) <> result)
def scenario(value: V.Value) -> String:
  match value:
    case V.ArrayValue{first <> rest}: collect(rest,operation(B.create(),first),Nil{})
    case _: "[]"
def parsed(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{value}: IO.print(scenario(value))
    case Fail{_}: IO.die(Unit,1,"invalid JSON")
def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        parsed(J.parse(text))
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

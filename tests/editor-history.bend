import Base
import ../packages/tui/src/kill-ring.bend as Kill
import ../packages/tui/src/undo-stack.bend as Undo
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R

def field(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def boolean(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}
def optional(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "null"
    case Some{value}: Json.quote(value)

type State is Data:
  State{ring: Kill.KillRing, stack: Undo.UndoStack<String>, saved: Undo.UndoStack<String>}
def stateResult(+ring: Kill.KillRing,+stack: Undo.UndoStack<String>,saved: Undo.UndoStack<String>,popped: Maybe<&2,String>) -> State & String:
  (State{ring,stack,saved},"[" ++ Nat.show(Kill.length(ring)) ++ "," ++ optional(Kill.peek(ring)) ++ "," ++ Nat.show(Undo.length(String,stack)) ++ "," ++ optional(popped) ++ "]")
def popped(ring: Kill.KillRing,saved: Undo.UndoStack<String>,result: Undo.UndoStack<String> & Maybe<&2,String>) -> State & String:
  match result:
    case (stack,value): stateResult(ring,stack,saved,value)
def save(state: State) -> State & String:
  match state:
    case State{ring,+stack,_}: stateResult(ring,stack,stack,None{})
def step(kind: String,+operation: V.Value,state: State) -> State & String:
  match kind state:
    case "save" state: save(state)
    case "kill" State{ring,stack,saved}: stateResult(Kill.push(text(field(operation,"text")),Kill.PushOptions{boolean(field(operation,"prepend")),boolean(field(operation,"accumulate"))},ring),stack,saved,None{})
    case "rotate" State{ring,stack,saved}: stateResult(Kill.rotate(ring),stack,saved,None{})
    case "push" State{ring,stack,saved}: stateResult(ring,Undo.push(String,text(field(operation,"text")),stack),saved,None{})
    case "pop" State{ring,stack,saved}: popped(ring,saved,Undo.pop(String,stack))
    case "clear" State{ring,stack,saved}: stateResult(ring,Undo.clear(String,stack),saved,None{})
    case "restore" State{ring,_,+saved}: stateResult(ring,saved,saved,None{})
    case _ State{ring,stack,saved}: stateResult(ring,stack,saved,None{})
def operation(+value: V.Value,state: State) -> State & String:
  step(text(field(value,"op")),value,state)
def transitions(ops: List<&2,V.Value>,current: State & String,results: List<&2,String>) -> String:
  match ops current:
    case Nil{} Tuple{_,result}: "[" ++ String.join(List.reverse(&2,String,result <> results),",") ++ "]"
    case value <> rest Tuple{state,result}: transitions(rest,operation(value,state),result <> results)
def begin(ops: List<&2,V.Value>) -> String:
  match ops:
    case Nil{}: "[]"
    case value <> rest: transitions(rest,operation(value,State{Kill.create(),Undo.create(String),Undo.create(String)}),Nil{})
def parsed(value: Result<&2,&2,Json.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{ops}}: IO.print(begin(ops))
    case _: IO.die(Unit,1,"expected operation array")
def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case arg <> rest:
      do IO<Unit>:
        parsed(Json.parse(arg))
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

import Base
import ../types.bend as Ai
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/date.bend as Date

# Provider replay repair is a persistent fold. Output and held system messages
# are accumulated in reverse order; pending calls retain assistant order.
def Messages(-P: Data, -A: Data, -G: Data, -D: Data) -> Data:
  List<&2, Ai.Message<P, A, G, D>>

type State<-P: Data, -A: Data, -G: Data, -D: Data> is Data:
  State{pending: List<&2, Ai.ToolCall<A>>, seen: List<&2, String>, held: Messages(P, A, G, D), output: Messages(P, A, G, D)}

def contains(ids: List<&2, String>, +id: String) -> Bool:
  match ids:
    case Nil{}: False{}
    case head <> rest: String.eq(head, id) || contains(rest, id)

def toolCalls(-A: Data, content: List<&2, Ai.AssistantContent<A>>) -> List<&2, Ai.ToolCall<A>>:
  match content:
    case Nil{}: Nil{}
    case Ai.AssistantToolCall{call} <> rest: call <> toolCalls(A, rest)
    case _ <> rest: toolCalls(A, rest)

def appendMissing(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~now: Unit -> IO(F64), exists: Bool, call: Ai.ToolCall<A>, output: Messages(P, A, G, D)) -> IO(Messages(P, A, G, D)):
  match exists call:
    case True{} _: IO.pure(Messages(P, A, G, D), output)
    case False{} Ai.ToolCall{id, name, _, _, _}:
      do IO<Messages(P, A, G, D)>:
        timestamp : F64 <- now(Unit{})
        return Ai.ToolResult{Ai.ToolResultMessage{id, name, Ai.TextImageText{Ai.TextContent{"No result provided", None{}}} <> Nil{}, None{}, None{}, True{}, timestamp}} <> output

def callId(-A: Data, call: Ai.ToolCall<A>) -> String:
  match call:
    case Ai.ToolCall{id, _, _, _, _}: id

def missing(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~now: Unit -> IO(F64), calls: List<&2, Ai.ToolCall<A>>, +seen: List<&2, String>, output: Messages(P, A, G, D)) -> IO(Messages(P, A, G, D)):
  match calls:
    case Nil{}: IO.pure(Messages(P, A, G, D), output)
    case +call <> rest:
      do IO<Messages(P, A, G, D)>:
        output : Messages(P, A, G, D) <- appendMissing(~P, ~A, ~G, ~D, ~now, contains(seen, callId(A, call)), call, output)
        missing(~P, ~A, ~G, ~D, ~now, rest, seen, output)

def flush(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~now: Unit -> IO(F64), state: State<P, A, G, D>) -> IO(Messages(P, A, G, D)):
  match state:
    case State{pending, seen, held, output}:
      do IO<Messages(P, A, G, D)>:
        repaired : Messages(P, A, G, D) <- missing(~P, ~A, ~G, ~D, ~now, pending, seen, output)
        return List.append(&2, Ai.Message<P, A, G, D>, held, repaired)

def replayable(reason: Ai.StopReason) -> Bool:
  match reason:
    case Ai.Error{}: False{}
    case Ai.Aborted{}: False{}
    case _: True{}

def assistantSelected(-P: Data, -A: Data, -G: Data, -D: Data, keep: Bool, source: Ai.AssistantMessage<A, G>, pending: List<&2, Ai.ToolCall<A>>, output: Messages(P, A, G, D)) -> State<P, A, G, D>:
  match keep:
    case False{}: State{Nil{}, Nil{}, Nil{}, output}
    case True{}: State{pending, Nil{}, Nil{}, Ai.Assistant{source} <> output}

def assistantState(-P: Data, -A: Data, -G: Data, -D: Data, +source: Ai.AssistantMessage<A, G>, output: Messages(P, A, G, D)) -> State<P, A, G, D>:
  match source:
    case Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, reason, _, _, _, _, _}:
      assistantSelected(P, A, G, D, replayable(reason), source, toolCalls(A, content), output)

def resultState(-P: Data, -A: Data, -G: Data, -D: Data, +result: Ai.ToolResultMessage<D>, state: State<P, A, G, D>) -> State<P, A, G, D>:
  match result state:
    case Ai.ToolResultMessage{id, _, _, _, _, _, _} State{pending, seen, held, output}:
      State{pending, id <> seen, held, Ai.ToolResult{result} <> output}

def systemState(-P: Data, -A: Data, -G: Data, -D: Data, system: Ai.SystemMessage<P>, state: State<P, A, G, D>) -> State<P, A, G, D>:
  match state:
    case State{Nil{}, seen, held, output}: State{Nil{}, seen, held, Ai.System{system} <> output}
    case State{pending, seen, held, output}: State{pending, seen, Ai.System{system} <> held, output}

def advance(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~now: Unit -> IO(F64), message: Ai.Message<P, A, G, D>, state: State<P, A, G, D>) -> IO(State<P, A, G, D>):
  match message:
    case Ai.Assistant{source}:
      do IO<State<P, A, G, D>>:
        output : Messages(P, A, G, D) <- flush(~P, ~A, ~G, ~D, ~now, state)
        return assistantState(P, A, G, D, source, output)
    case Ai.User{user}:
      do IO<State<P, A, G, D>>:
        output : Messages(P, A, G, D) <- flush(~P, ~A, ~G, ~D, ~now, state)
        return State{Nil{}, Nil{}, Nil{}, Ai.User{user} <> output}
    case Ai.ToolResult{result}: IO.pure(State<P, A, G, D>, resultState(P, A, G, D, result, state))
    case Ai.System{system}: IO.pure(State<P, A, G, D>, systemState(P, A, G, D, system, state))

def run(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~now: Unit -> IO(F64), messages: Messages(P, A, G, D), state: State<P, A, G, D>) -> IO(Messages(P, A, G, D)):
  match messages:
    case Nil{}:
      do IO<Messages(P, A, G, D)>:
        output : Messages(P, A, G, D) <- flush(~P, ~A, ~G, ~D, ~now, state)
        return List.reverse(&2, Ai.Message<P, A, G, D>, output)
    case message <> rest:
      do IO<Messages(P, A, G, D)>:
        next : State<P, A, G, D> <- advance(~P, ~A, ~G, ~D, ~now, message, state)
        run(~P, ~A, ~G, ~D, ~now, rest, next)

def repairWith(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~now: Unit -> IO(F64), messages: Messages(P, A, G, D)) -> IO(Messages(P, A, G, D)):
  run(~P, ~A, ~G, ~D, ~now, messages, State{Nil{}, Nil{}, Nil{}, Nil{}})

def wallClock(unused: Unit) -> IO(F64): Date.now()

def repairToolResults(~P: Data, ~A: Data, ~G: Data, ~D: Data, messages: Messages(P, A, G, D)) -> IO(Messages(P, A, G, D)):
  repairWith(~P, ~A, ~G, ~D, ~wallClock, messages)

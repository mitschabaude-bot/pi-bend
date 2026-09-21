import Base
import ../packages/ai/src/api/openai-responses-session.bend as Session
import ../packages/ai/src/api/openai-responses-lifecycle.bend as Life
import ../packages/ai/src/api/openai-sse-reader.bend as SSE
import ../packages/ai/src/api/openai-http-errors.bend as Errors
import ../packages/ai/src/utils/event-stream.bend as Events
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/test/utf8-runner.bend as Text
import ./openai-provider-driver.bend as Source
import ./provider-request.bend as Requests
import ./openai-http-process.bend as Process

def observed(cursor: Events.Iterator<Source.AssistantEvent(), Source.Message()>, consumed: Chan(List<&2, Source.AssistantEvent()>), final: Chan(Source.Message()), pair: Session.Run<V.Value, Unit, String> & Life.RunResult<V.Value, Unit, String>) -> IO(Unit):
  match pair:
    case (owner, result):
      do IO<Unit>:
        Source.finished(result)
        events : List<&2, Source.AssistantEvent()> <- IO.join(List<&2, Source.AssistantEvent()>, consumed)
        Source.retained(events)
        output : Source.Message() <- IO.join(Source.Message(), final)
        IO.print("final:" ++ Source.snapshot(output))
        Events.disposeIterator(Source.AssistantEvent(), Source.Message(), cursor)
        ignored : Life.RunResult<V.Value, Unit, String> <- Session.dispose(V.Value, Unit, String, owner)
        return Unit{}

def observe(pair: Session.Run<V.Value, Unit, String> & Source.Stream()) -> IO(Unit):
  match pair:
    case Tuple{owner, +stream}:
      do IO<Unit>:
        +cursor : Events.Iterator<Source.AssistantEvent(), Source.Message()> <- Events.iterator(Source.AssistantEvent(), Source.Message(), stream)
        consumed : Chan(List<&2, Source.AssistantEvent()>) <- IO.fork(List<&2, Source.AssistantEvent()>, Source.drain(cursor))
        final : Chan(Source.Message()) <- IO.fork(Source.Message(), Events.resultValue(Source.AssistantEvent(), Source.Message(), stream))
        joined : Session.Run<V.Value, Unit, String> & Life.RunResult<V.Value, Unit, String> <- Session.wait(V.Value, Unit, String, owner)
        observed(cursor, consumed, final, joined)

def run(port: U32, +mode: U32) -> IO(Unit):
  do IO<Unit>:
    +controller : A.AbortController<String> <- A.new(String)
    +hooks : SSE.Hooks<Errors.TransportError(String)> <- Process.createHooks(controller)
    +signal : C.Callback<Unit, Bool> <- C.create(~A.AbortController<String>, ~Unit, ~Bool, ~Source.aborted, controller)
    owner : Session.Run<V.Value, Unit, String> <- Session.start(~V.Value, ~Unit, ~String, ~Source.identity, Requests.Owner(), Life.initial(V.Value, Unit, Unit, Process.model(), F.fromU32(123)), signal, Source.acquire(port, mode, controller), Source.process(mode, controller, hooks), Requests.release(False{}))
    observe(Session.borrow(V.Value, Unit, String, owner))
    C.dispose(Unit, Bool, signal)
    Process.retireHooks(hooks)
    A.dispose(String, controller)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case port <> mode <> Nil{}: run(Text.decimal(port, 0), Text.decimal(mode, 0))
    case _: IO.die(Unit, 1, "expected port mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

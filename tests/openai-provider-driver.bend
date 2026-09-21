import Base
import ../packages/ai/src/utils/error-body.bend as ErrorBody
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-lifecycle.bend as Life
import ../packages/ai/src/api/openai-responses-driver.bend as Driver
import ../packages/ai/src/api/openai-responses-stream.bend as Content
import ../packages/ai/src/api/openai-responses-terminal.bend as Terminal
import ../packages/ai/src/api/openai-responses-stream-pricing.bend as Pricing
import ../packages/ai/src/api/openai-http-responses-reader.bend as Reader
import ../packages/ai/src/api/openai-sse-reader.bend as SSE
import ../packages/ai/src/api/openai-http-errors.bend as Errors
import ../packages/ai/src/utils/event-stream.bend as Events
import ../packages/ai/src/utils/provider-request.bend as Request
import ../packages/ai/src/utils/provider-response-view.bend as View
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/test/provider-retry.bend as Reference
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-socket-exchange.bend as Exchange
import ../packages/runtime/test/utf8-runner.bend as Text
import ./provider-request.bend as Requests
import ./openai-http-process.bend as Process

def Message() -> Data: T.AssistantMessage<V.Value, Unit>
def AssistantEvent() -> Data: T.AssistantMessageEvent<V.Value, Unit>
def Stream() -> Data: Events.AssistantMessageEventStream(V.Value, Unit)
def identity(value: String) -> String: value

def requestMode(+mode: U32) -> U32:
  Bool.pick(U32, U32.is_eq(mode, 2), 4, Bool.pick(U32, U32.is_eq(mode, 3), 5, Bool.pick(U32, U32.is_eq(mode, 14), 2, Bool.pick(U32, U32.is_eq(mode, 15), 10, 1))))

def formatted(value: Result<&2, &2, ErrorBody.NormalizationError, String>) -> String:
  match value:
    case Done{text}: text
    case Fail{_}: "format"

def requestResult(value: Result<&2, &1, Request.Error<String>, Requests.Owner()>) -> Result<&2, &1, String, Requests.Owner()>:
  match value:
    case Done{owner}: Done{owner}
    case Fail{Request.PayloadFailure{cause}}: Fail{cause}
    case Fail{Request.ResponseFailure{cause, _}}: Fail{cause}
    case Fail{Request.RequestFailure{Retry.RequestFailed{Retry.Provider{Retry.ProviderError{original, _, status, _, _, _}}}}}: Fail{formatted(ErrorBody.formatProviderError(ErrorBody.NormalizedProviderError{status, None{}, original, True{}}, Some{"OpenAI API error"}))}
    case Fail{_}: Fail{"request"}

def acquire(port: U32, +mode: U32, +controller: A.AbortController<String>) -> IO(Result<&2, &1, String, Requests.Owner()>):
  do IO<Result<&2, &1, String, Requests.Owner()>>:
    +request : C.Callback<Requests.Payload(), Result<&2, &1, Retry.RequestFailure<String>, Requests.Owner()>> <- C.create(~Requests.Environment, ~Requests.Payload(), ~Result<&2, &1, Retry.RequestFailure<String>, Requests.Owner()>, ~(environment => value => Requests.requestBody(environment, value)), Requests.Environment{port, controller})
    +payload : T.PayloadCallback(Requests.Payload(), String, String) <- C.create(~U32, ~T.PayloadInput<Requests.Payload(), String>, ~Result<&2, &2, String, Maybe<&2, Requests.Payload()>>, ~(selectedMode => input => Requests.payloadHook(selectedMode, input)), requestMode(mode))
    +response : T.ResponseCallback(String, String) <- C.create(~U32, ~T.ResponseInput<String>, ~Result<&2, &2, String, Unit>, ~(selectedMode => input => Requests.responseHook(selectedMode, input)), requestMode(mode))
    +random : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Reference.randomBody, Unit{})
    +date : C.Callback<String, F.F64> <- C.create(~Unit, ~String, ~F.F64, ~Reference.dateBody, Unit{})
    +now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Reference.nowBody, Unit{})
    +sleep : C.Callback<Retry.SleepInput<String>, Result<&2, &2, Unit, Unit>> <- C.create(~Bool, ~Retry.SleepInput<String>, ~Result<&2, &2, Unit, Unit>, ~Reference.sleepBody, False{})
    result : Result<&2, &1, Request.Error<String>, Requests.Owner()> <- Request.run(~String, ~Requests.Payload(), ~String, ~String, ~Requests.Owner(), "model", T.PresentValue{7}, Some{payload}, Some{response}, request, Retry.Effects{random, date, now, sleep}, Retry.ProviderRetryOptions{Some{2n}, None{}, Some{A.signal(String, controller)}}, View.inspect(Exchange.Exchange<String>), Requests.release(False{}))
    C.dispose(Requests.Payload(), Result<&2, &1, Retry.RequestFailure<String>, Requests.Owner()>, request)
    C.dispose(T.PayloadInput<Requests.Payload(), String>, Result<&2, &2, String, Maybe<&2, Requests.Payload()>>, payload)
    C.dispose(T.ResponseInput<String>, Result<&2, &2, String, Unit>, response)
    C.dispose(Unit, F.F64, random)
    C.dispose(String, F.F64, date)
    C.dispose(Unit, F.F64, now)
    C.dispose(Retry.SleepInput<String>, Result<&2, &2, Unit, Unit>, sleep)
    return requestResult(result)

def detail(value: Message()) -> String:
  match value:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, None{}, _, _, _}: "none"
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, Some{text}, _, _, _}: Text.showText(text)

def stop(value: T.StopReason) -> String:
  match value:
    case T.Pending{}: "pending"
    case T.Stop{}: "stop"
    case T.Length{}: "length"
    case T.ToolUse{}: "toolUse"
    case T.Deferred{}: "deferred"
    case T.Error{}: "error"
    case T.Aborted{}: "aborted"

def snapshot(+value: Message()) -> String:
  match value:
    case T.AssistantMessage{blocks, _, _, _, _, id, _, _, tokens, reason, _, _, _, _, _}:
      "output:" ++ Process.contents(blocks) ++ ":" ++ Process.optional(id) ++ ":" ++ stop(reason) ++ ":" ++ Process.usage(tokens) ++ ":error:" ++ detail(value)

def kind(value: AssistantEvent()) -> String:
  match value:
    case T.Start{_}: "start"
    case T.StreamDone{_, _}: "done"
    case T.StreamError{_, _}: "error"
    case T.TextStart{_, _}: "text_start"
    case T.TextDelta{_, _, _}: "text_delta"
    case T.TextEnd{_, _, _}: "text_end"
    case _: "other"

def shown(+value: AssistantEvent()) -> String: kind(value) ++ ":" ++ snapshot(Content.eventSnapshot(Unit, value))

def fails(+mode: U32, value: AssistantEvent()) -> Bool:
  match value:
    case T.Start{_}: U32.is_eq(mode, 4)
    case T.TextDelta{_, _, _}: U32.is_eq(mode, 5)
    case T.StreamDone{_, _}: U32.is_eq(mode, 6)
    case T.StreamError{_, _}: U32.is_eq(mode, 7)
    case _: False{}

def publish(stream: Stream(), value: AssistantEvent(), fail: Bool) -> IO(Result<&2, &2, String, Unit>):
  match fail:
    case True{}: IO.pure(Result<&2, &2, String, Unit>, Fail{"sink"})
    case False{}:
      do IO<Result<&2, &2, String, Unit>>:
        Events.push(AssistantEvent(), Message(), stream, value)
        return Done{Unit{}}

type SinkEnvironment is Data:
  SinkEnvironment{mode: U32, stream: Stream()}

def emit(environment: SinkEnvironment, +value: AssistantEvent()) -> IO(Result<&2, &2, String, Unit>):
  match environment:
    case SinkEnvironment{mode, stream}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("emit:" ++ shown(value))
        publish(stream, value, fails(mode, value))

def closed(stream: Stream(), value: Message()) -> IO(Unit):
  do IO<Unit>:
    IO.print("close")
    Events.end(AssistantEvent(), Message(), stream, Some{value})

def aborted(controller: A.AbortController<String>, unused: Unit) -> IO(Bool):
  A.aborted(String, A.signal(String, controller))

def processingError(value: Maybe<&2, Content.Error<String>>) -> Maybe<&2, String>:
  match value:
    case None{}: None{}
    case Some{Content.ReadFailure{cause}}: Some{cause}
    case Some{Content.EmitFailure{cause}}: Some{cause}
    case Some{Content.TerminalFailure{cause}}: Some{Terminal.errorMessage(cause)}
    case Some{_}: Some{"processing"}

def processed(+mode: U32, value: Reader.Processed<String, Unit, String>) -> Life.Processed<V.Value, Unit, String>:
  match value:
    case Reader.Processed{Content.RunResult{+message, failure}, cleanup}:
      Life.Processed{Bool.pick(Message(), U32.is_eq(mode, 17), Terminal.withStop(Unit, message, Terminal.MappedStop{T.Pending{}, None{}}), message), processingError(failure), Bool.pick(Maybe<&2, String>, U32.is_eq(mode, 11) || U32.is_eq(mode, 12), Some{"cleanup"}, Bool.pick(Maybe<&2, String>, Result.is_done(&2, &2, Reader.CloseError<String>, Unit, cleanup), None{}, Some{"close"}))}

def afterProcess(shouldAbort: Bool, controller: A.AbortController<String>) -> IO(Unit):
  match shouldAbort:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- A.abort(String, controller, None{})
        return Unit{}

def process(+mode: U32, controller: A.AbortController<String>, hooks: SSE.Hooks<Errors.TransportError(String)>, sink: C.Callback<AssistantEvent(), Result<&2, &2, String, Unit>>, value: Requests.Owner(), output: Message()) -> IO(Life.Processed<V.Value, Unit, String>):
  match value:
    case Response.Response{_, body}:
      do IO<Life.Processed<V.Value, Unit, String>>:
        owner : Reader.Owner<String, String> <- Reader.create(~String, ~String, ~Process.mapError, body, hooks, False{})
        result : Reader.Processed<String, Unit, String> <- Reader.process(String, Unit, String, Unit, owner, output, sink, Process.model(), Pricing.defaultOptions(String))
        afterProcess(U32.is_eq(mode, 8), controller)
        return processed(mode, result)

@unsafe def drainStep(+cursor: Events.Iterator<AssistantEvent(), Message()>, value: Events.Iteration<AssistantEvent()>) -> IO(List<&2, AssistantEvent()>):
  match value:
    case Events.End{}: IO.pure(List<&2, AssistantEvent()>, Nil{})
    case Events.Yield{event}:
      do IO<List<&2, AssistantEvent()>>:
        next : Events.Iteration<AssistantEvent()> <- Events.nextValue(AssistantEvent(), Message(), cursor)
        tail : List<&2, AssistantEvent()> <- drainStep(cursor, next)
        return event <> tail

def drain(+cursor: Events.Iterator<AssistantEvent(), Message()>) -> IO(List<&2, AssistantEvent()>):
  do IO<List<&2, AssistantEvent()>>:
    next : Events.Iteration<AssistantEvent()> <- Events.nextValue(AssistantEvent(), Message(), cursor)
    drainStep(cursor, next)

def retained(values: List<&2, AssistantEvent()>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print("retained:" ++ shown(head))
        retained(rest)

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: text

def cause(value: Life.Terminal<V.Value, Unit, String>) -> String:
  match value:
    case Life.Successful{_, _}: "ok"
    case Life.Failed{_, _, error}: Life.describe(String, identity, error)

def finished(value: Life.RunResult<V.Value, Unit, String>) -> IO(Unit):
  match value:
    case Life.RunResult{+terminal, cleanup, delivery}:
      IO.print("run:" ++ cause(terminal) ++ ":cleanup:" ++ optional(cleanup) ++ ":delivery:" ++ optional(delivery))

def run(port: U32, +mode: U32) -> IO(Unit):
  do IO<Unit>:
    +controller : A.AbortController<String> <- A.new(String)
    +hooks : SSE.Hooks<Errors.TransportError(String)> <- Process.createHooks(controller)
    +stream : Stream() <- Events.createAssistantMessageEventStream(~V.Value, ~Unit)
    +cursor : Events.Iterator<AssistantEvent(), Message()> <- Events.iterator(AssistantEvent(), Message(), stream)
    consumed : Chan(List<&2, AssistantEvent()>) <- IO.fork(List<&2, AssistantEvent()>, drain(cursor))
    final : Chan(Message()) <- IO.fork(Message(), Events.resultValue(AssistantEvent(), Message(), stream))
    +sink : C.Callback<AssistantEvent(), Result<&2, &2, String, Unit>> <- C.create(~SinkEnvironment, ~AssistantEvent(), ~Result<&2, &2, String, Unit>, ~(environment => value => emit(environment, value)), SinkEnvironment{mode, stream})
    +signal : C.Callback<Unit, Bool> <- C.create(~A.AbortController<String>, ~Unit, ~Bool, ~aborted, controller)
    +close : C.Callback<Message(), Unit> <- C.create(~Stream(), ~Message(), ~Unit, ~closed, stream)
    result : Life.RunResult<V.Value, Unit, String> <- Driver.run(~String, ~identity, V.Value, Unit, Requests.Owner(), Driver.Effects{sink, signal, close}, Life.initial(V.Value, Unit, Unit, Process.model(), F.fromU32(123)), acquire(port, mode, controller), process(mode, controller, hooks, sink), Requests.release(False{}))
    finished(result)
    events : List<&2, AssistantEvent()> <- IO.join(List<&2, AssistantEvent()>, consumed)
    retained(events)
    output : Message() <- IO.join(Message(), final)
    IO.print("final:" ++ snapshot(output))
    Events.disposeIterator(AssistantEvent(), Message(), cursor)
    Events.disposeAssistantMessageEventStream(V.Value, Unit, stream)
    C.dispose(AssistantEvent(), Result<&2, &2, String, Unit>, sink)
    C.dispose(Unit, Bool, signal)
    C.dispose(Message(), Unit, close)
    Process.retireHooks(hooks)
    A.dispose(String, controller)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case port <> mode <> Nil{}: run(Text.decimal(port, 0), Text.decimal(mode, 0))
    case _: IO.die(Unit, 1, "expected port mode")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

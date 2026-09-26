import Base
import ../src/api/anthropic-messages-client.bend as Client
import ../src/api/anthropic-messages.bend as Messages
import ../src/api/anthropic-messages-stream.bend as Fold
import ../src/api/openai-client.bend as SDK
import ../src/utils/event-stream.bend as Events
import ../../runtime/src/record.bend as R
import ../src/providers/anthropic.models.bend as Models
import ../src/types.bend as T
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/deadline.bend as Deadline
import ../../runtime/src/dns-resolver.bend as DNS
import ../../runtime/src/connection-driver.bend as Connect
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-exchange.bend as HTTP
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/url.bend as URL
import ../../runtime/src/idna.bend as IDNA
import ../../runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../../runtime/src/unicode-17-normalization.bend as Normalization
import ../../runtime/src/unicode-17-idna-properties.bend as Properties
import ../../runtime/src/f64.bend as F
import ../../runtime/src/schema-value.bend as V

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def baseModel(base: String, value: T.Model<T.JsonValue>) -> T.Model<T.JsonValue>:
  match value:
    case T.Model{id, name, api, provider, _, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}:
      T.Model{id, name, api, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}

def model(base: String) -> T.Model<T.JsonValue>: baseModel(base, Models.model_claude_opus_5())

def context() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  T.TranscriptContext{T.User{T.UserMessage{T.UserText{"ping"}, F.fromU32(1)}} <> Nil{}}

def eventName(event: T.AssistantMessageEvent<V.Value, Unit>) -> String:
  match event:
    case T.Start{_}: "start"
    case T.TextStart{_, _}: "text_start"
    case T.TextDelta{_, _, _}: "text_delta"
    case T.TextEnd{_, _, _}: "text_end"
    case T.ToolcallStart{_, _}: "toolcall_start"
    case T.ToolcallDelta{_, _, _}: "toolcall_delta"
    case T.ToolcallEnd{_, _, _}: "toolcall_end"
    case T.StreamDone{_, _}: "done"
    case T.StreamError{_, _}: "error"
    case _: "other"

def options() -> Client.Options(Unit, Unit, String):
  Messages.AnthropicOptions{T.StreamOptions{None{}, None{}, Some{"test-key"}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{T.CacheNone{}}, None{}, None{}, None{}}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def networkOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}

def noDetails(values: List<&2, Fold.InputTransformation>) -> Unit: Unit{}

@unsafe def drain(next: Events.Iteration<T.AssistantMessageEvent<V.Value, Unit>>, +cursor: Events.Iterator<T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>>) -> IO(Unit):
  match next:
    case Events.Yield{event}:
      do IO<Unit>:
        IO.print(eventName(event))
        following : Events.Iteration<T.AssistantMessageEvent<V.Value, Unit>> <- Events.nextValue(T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>, cursor)
        drain(following, cursor)
    case Events.End{}: Events.disposeIterator(T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>, cursor)

def stopped(reason: T.StopReason) -> IO(Unit):
  match reason:
    case T.Stop{}: IO.print("success")
    case _: IO.die(Unit, 1, "request failed")

def checked(message: T.AssistantMessage<V.Value, Unit>) -> IO(Unit): stopped(T.assistantStopReason(V.Value, Unit, message))

# upstream `stream` over native fetch: the printed events, then the outcome.
def borrowed(base: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (owned, +fetch):
      +selected = model(base)
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        +events : Events.AssistantMessageEventStream(V.Value, Unit) <- Events.createAssistantMessageEventStream(~V.Value, ~Unit)
        Client.stream(~Unit, ~Unit, ~String, ~Unit, ~noDetails, ~Unit, ~(message => message), events, Abort.signal(Unit, controller), Client.Setup{urlContext(), SDK.Defaults{Client.sdkUserAgent(), R.new(String), None{}, None{}}, "pi-test", fetch}, selected, context(), options(), F.fromU32(1))
        +cursor : Events.Iterator<T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>> <- Events.iterator(T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>, events)
        first : Events.Iteration<T.AssistantMessageEvent<V.Value, Unit>> <- Events.nextValue(T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>, cursor)
        drain(first, cursor)
        message : T.AssistantMessage<V.Value, Unit> <- Events.resultValue(T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>, events)
        Abort.dispose(Unit, controller)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(owned)
        checked(message)

def active(base: String, runtime: Fetch.Runtime) -> IO(Unit):
  do IO<Unit>:
    pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
    borrowed(base, pair)

def initialized(base: String, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}: active(base, runtime)

def run(base: String) -> IO(Unit):
  do IO<Unit>:
    runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), networkOptions())
    initialized(base, runtime)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case base <> Nil{}: run(base)
    case _: IO.die(Unit, 1, "base URL required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

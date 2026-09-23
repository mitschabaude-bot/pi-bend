import Base
import ../src/api/google-generative-ai-client.bend as Client
import ../src/api/google-generative-ai.bend as Messages
import ../src/providers/google.models.bend as Models
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

def model(base: String) -> T.Model<T.JsonValue>: baseModel(base, Models.model_gemini_2_5_flash())

def context() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  T.TranscriptContext{T.User{T.UserMessage{T.UserText{"ping"}, F.fromU32(1)}} <> Nil{}}

def eventName(event: T.AssistantMessageEvent<V.Value, Unit>) -> String:
  match event:
    case T.Start{_}: "start"
    case T.TextStart{_, _}: "text_start"
    case T.TextDelta{_, _, _}: "text_delta"
    case T.TextEnd{_, _, _}: "text_end"
    case T.ThinkingStart{_, _}: "thinking_start"
    case T.ThinkingDelta{_, _, _}: "thinking_delta"
    case T.ThinkingEnd{_, _, _}: "thinking_end"
    case T.ToolcallStart{_, _}: "toolcall_start"
    case T.ToolcallDelta{_, _, _}: "toolcall_delta"
    case T.ToolcallEnd{_, _, _}: "toolcall_end"
    case T.StreamDone{_, _}: "done"
    case T.StreamError{_, _}: "error"
    case _: "other"

def notify(unused: Unit, event: T.AssistantMessageEvent<V.Value, Unit>) -> IO(Unit): IO.print(eventName(event))

def options() -> Messages.Options: Messages.Options{None{}, None{}, Messages.NoThinking{}, None{}}

def networkOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}

def checked(result: Result<&2, &2, Client.Error<Unit>, T.AssistantMessage<V.Value, Unit>>) -> IO(Unit):
  match result:
    case Done{_}: IO.print("success")
    case Fail{_}: IO.die(Unit, 1, "request failed")

def prepared(request: Result<&2, &2, Client.Error<Unit>, Client.Request>, fetch: Fetch.Fetch(Unit), signal: Fetch.Signal(Unit), callback: Client.Events(Unit), selected: T.Model<T.JsonValue>) -> IO(Unit):
  match request:
    case Fail{_}: IO.die(Unit, 1, "request preparation failed")
    case Done{value}:
      do IO<Unit>:
        result : Result<&2, &2, Client.Error<Unit>, T.AssistantMessage<V.Value, Unit>> <- Client.run(~Unit, ~Unit, fetch, signal, callback, selected, value, F.fromU32(1))
        checked(result)

def borrowed(base: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (owned, +fetch):
      +selected = model(base)
      do IO<Unit>:
        +controller : Abort.AbortController<Deadline.Cause<Unit>> <- Abort.new(Deadline.Cause<Unit>)
        +events : Client.Events(Unit) <- C.create(~Unit, ~T.AssistantMessageEvent<V.Value, Unit>, ~Unit, ~notify, Unit{})
        prepared(Client.prepare(Unit, Unit, Unit, urlContext(), selected, context(), options(), Some{"test-google-key"}, None{}), fetch, Abort.signal(Deadline.Cause<Unit>, controller), events, selected)
        C.dispose(T.AssistantMessageEvent<V.Value, Unit>, Unit, events)
        Abort.dispose(Deadline.Cause<Unit>, controller)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(owned)

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

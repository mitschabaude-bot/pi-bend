import Base
import ../src/proxy.bend as Proxy
import ../../ai/src/types.bend as T
import ../../ai/src/utils/event-stream.bend as Events
import ../../ai/src/utils/json.bend as JsonWire
import ../../ai/src/utils/message-json.bend as MessageJson
import ../../ai/src/utils/schema-json.bend as SchemaJson
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/connection-driver.bend as Connect
import ../../runtime/src/dns-resolver.bend as DNS
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-exchange.bend as HTTP
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/idna.bend as IDNA
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../../runtime/src/unicode-17-idna-properties.bend as Properties
import ../../runtime/src/unicode-17-normalization.bend as Normalization
import ../../runtime/src/url.bend as URL

# pi-mono f07218c4d packages/agent/test/proxy.test.ts. Upstream stubs the
# global fetch with a Response holding each test's body; here the native
# fetch reaches a loopback server run by tests/agent_proxy_check.py that
# answers POST /api/stream with the same body. `proxy <baseUrl>` streams one
# request and prints every event and the result as JSON lines; the checker
# asserts the upstream expectations and compares the whole trace with
# upstream proxy.ts against the same server.

def J() -> Data: T.JsonValue
def Error() -> Data: String
def StreamMessage() -> Data: T.AssistantMessage<V.Value, Unit>
def StreamEvent() -> Data: T.AssistantMessageEvent<V.Value, Unit>
def EventStream() -> Data: Events.AssistantMessageEventStream(V.Value, Unit)

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def networkOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}

def zero() -> F64: F.fromU32(0)

# The upstream test's model.
def model() -> T.Model<J()>:
  T.Model{"gpt-5.4", "GPT-5.4", T.OpenAIResponsesApi{}, "openai", "https://api.openai.com/v1", True{}, None{}, T.InputText{} <> Nil{}, None{}, T.ModelCost{zero(), zero(), zero(), zero(), None{}}, None{}, F.fromU32(400000), F.fromU32(128000), None{}, None{}, None{}}

# normalizeContext({ systemPrompt: "", messages: [] }).
def context() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>: T.TranscriptContext{Nil{}}

def options(baseUrl: String) -> Proxy.ProxyStreamOptions<Unit, Unit, Error()>:
  Proxy.ProxyStreamOptions{T.emptySimpleStreamOptions(J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()), "test-token", baseUrl}

def unitDetails(value: Unit) -> V.Value: V.Null{}

def json(value: V.Value) -> String: Maybe.default(&2, String, JsonWire.stringify(SchemaJson.toJson(value)), "null")

def eventLine(event: StreamEvent()) -> String: json(MessageJson.assistantMessageEvent(~Unit, ~unitDetails, event))

# `for await (const event of stream) events.push(event)`.
@unsafe def drain(+cursor: Events.Iterator<StreamEvent(), StreamMessage()>, step: Events.Iteration<StreamEvent()>) -> IO(Unit):
  match step:
    case Events.End{}: Events.disposeIterator(StreamEvent(), StreamMessage(), cursor)
    case Events.Yield{event}:
      do IO<Unit>:
        IO.print("event " ++ eventLine(event))
        next : Events.Iteration<StreamEvent()> <- Events.nextValue(StreamEvent(), StreamMessage(), cursor)
        drain(cursor, next)

def report(pair: Proxy.ProxyMessageEventStream<Unit> & EventStream()) -> IO(Unit):
  match pair:
    case (owner, +events):
      do IO<Unit>:
        +cursor : Events.Iterator<StreamEvent(), StreamMessage()> <- Events.iterator(StreamEvent(), StreamMessage(), events)
        first : Events.Iteration<StreamEvent()> <- Events.nextValue(StreamEvent(), StreamMessage(), cursor)
        drain(cursor, first)
        message : StreamMessage() <- Events.resultValue(StreamEvent(), StreamMessage(), events)
        IO.print("result " ++ json(MessageJson.assistantMessage(~Unit, ~unitDetails, message)))
        Proxy.disposeStream(Unit, owner)

def borrowed(baseUrl: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (owned, +fetch):
      do IO<Unit>:
        owner : Proxy.ProxyMessageEventStream<Unit> <- Proxy.streamProxy(~Unit, ~Unit, ~Error(), ~Unit, ~Unit, ~unitDetails, ~unitDetails, fetch, urlContext(), model(), context(), options(baseUrl))
        report(Proxy.borrowStream(Unit, owner))
        Fetch.retire(Unit, fetch)
        Fetch.dispose(owned)

def active(baseUrl: String, runtime: Fetch.Runtime) -> IO(Unit):
  do IO<Unit>:
    pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
    borrowed(baseUrl, pair)

def initialized(baseUrl: String, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}: active(baseUrl, runtime)

def run(baseUrl: String) -> IO(Unit):
  do IO<Unit>:
    runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), networkOptions())
    initialized(baseUrl, runtime)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case "proxy" <> baseUrl <> Nil{}: run(baseUrl)
    case _: IO.die(Unit, 1, "usage: proxy <baseUrl>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

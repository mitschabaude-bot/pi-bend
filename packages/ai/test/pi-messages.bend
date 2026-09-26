import Base
import ../src/api/pi-messages.bend as Pi
import ../src/types.bend as T
import ../src/utils/event-stream.bend as Events
import ../src/utils/message-json.bend as MessageJson
import ../src/utils/schema-json.bend as SchemaJson
import ../src/utils/json.bend as JsonWire
import ../src/utils/model-api.bend as ModelApi
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/connection-driver.bend as Connect
import ../../runtime/src/dns-resolver.bend as DNS
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-exchange.bend as HTTP
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/idna.bend as IDNA
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../../runtime/src/unicode-17-idna-properties.bend as Properties
import ../../runtime/src/unicode-17-normalization.bend as Normalization
import ../../runtime/src/url.bend as URL

# upstream pi-messages.test.ts against a loopback server run by
# tests/pi_messages_check.py: `pi-messages <case> <baseUrl>` streams one
# case and prints every event and the final message as JSON lines. The
# checker asserts the upstream expectations and compares the trace with the
# upstream implementation serving the same responses.

def J() -> Data: T.JsonValue
def Error() -> Data: String
def Stream() -> Data: Events.AssistantMessageEventStream(V.Value, J())
def Options() -> Data: Pi.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error())

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def networkOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}

# upstream createModel.
def createModel(baseUrl: String) -> T.Model<J()>:
  T.Model{"auto", "Radius Auto", T.PiMessagesApi{}, "radius", baseUrl, False{}, None{}, [T.InputText{}], None{}, T.ModelCost{F.fromU32(1), F.fromU32(2), F.divide(F.fromU32(1), F.fromU32(10)), F.divide(F.fromU32(2), F.fromU32(10)), None{}}, None{}, F.fromU32(128000), F.fromU32(16384), None{}, None{}, None{}}

# upstream `context` with a fixed timestamp, so the checker can compare the
# request body with it.
def context() -> T.TranscriptContext<V.Value, V.Value, J(), Unit>:
  T.TranscriptContext{[T.User{T.UserMessage{T.UserText{"Hello"}, F.fromU32(1700000000)}}]}

def identity(value: J()) -> J(): value
def render(value: Error()) -> String: value
def unitDetails(value: Unit) -> V.Value: V.Null{}

def base(key: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>, maxTokens: Maybe<&2, F64>, sessionId: Maybe<&2, String>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, Error())>) -> T.StreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>:
  T.StreamOptions{None{}, None{}, key, None{}, None{}, None{}, onResponse, headers, None{}, None{}, None{}, None{}, None{}, maxTokens, None{}, None{}, sessionId, None{}, None{}}

def keyed(key: String) -> Options():
  Pi.PiMessagesOptions{base(Some{key}, None{}, None{}, None{}, None{}), None{}, None{}, None{}}

# The first case's options: key, session, tool choice, max tokens and a header.
def detailed() -> Options():
  Pi.PiMessagesOptions{base(Some{"test-key"}, Some{R.Record{[R.Property{"x-custom", T.PresentValue{"1"}}]}}, Some{F.fromU32(100)}, Some{"session-1"}, None{}), None{}, Some{Pi.ToolChoiceAuto{}}, None{}}

def unkeyed() -> Options():
  Pi.PiMessagesOptions{base(None{}, None{}, None{}, None{}, None{}), None{}, None{}, None{}}

def json(value: V.Value) -> String: Maybe.default(&2, String, JsonWire.stringify(SchemaJson.toJson(value)), "null")

def eventLine(event: T.AssistantMessageEvent<V.Value, J()>) -> String:
  json(MessageJson.assistantMessageEvent(~J(), ~MessageJson.jsonValue, event))

@unsafe def drain(+cursor: Events.Iterator<T.AssistantMessageEvent<V.Value, J()>, T.AssistantMessage<V.Value, J()>>, step: Maybe<&2, Events.Iteration<T.AssistantMessageEvent<V.Value, J()>>>) -> IO(Unit):
  match step:
    case Some{Events.End{}}: Events.disposeIterator(T.AssistantMessageEvent<V.Value, J()>, T.AssistantMessage<V.Value, J()>, cursor)
    case Some{Events.Yield{event}}:
      do IO<Unit>:
        IO.print("event " ++ eventLine(event))
        drain(cursor, None{})
    case None{}:
      do IO<Unit>:
        next : Events.Iteration<T.AssistantMessageEvent<V.Value, J()>> <- Events.nextValue(T.AssistantMessageEvent<V.Value, J()>, T.AssistantMessage<V.Value, J()>, cursor)
        drain(cursor, Some{next})

def report(+events: Stream()) -> IO(Unit):
  do IO<Unit>:
    Events.end(T.AssistantMessageEvent<V.Value, J()>, T.AssistantMessage<V.Value, J()>, events, None{})
    +cursor : Events.Iterator<T.AssistantMessageEvent<V.Value, J()>, T.AssistantMessage<V.Value, J()>> <- Events.iterator(T.AssistantMessageEvent<V.Value, J()>, T.AssistantMessage<V.Value, J()>, events)
    drain(cursor, None{})
    message : T.AssistantMessage<V.Value, J()> <- Events.resultValue(T.AssistantMessageEvent<V.Value, J()>, T.AssistantMessage<V.Value, J()>, events)
    IO.print("result " ++ json(MessageJson.assistantMessage(~J(), ~MessageJson.jsonValue, message)))
    Events.disposeAssistantMessageEventStream(V.Value, J(), events)

def headerValue(value: Maybe<&2, String>) -> String: Maybe.default(&2, String, value, "<missing>")

def observe(unused: Unit, input: T.ResponseInput<T.Model<J()>>) -> IO(Result<&2, &2, Error(), Unit>):
  match input:
    case T.ResponseInput{T.ProviderResponse{status, headers}, _}:
      do IO<Result<&2, &2, Error(), Unit>>:
        IO.print("observed " ++ headerValue(R.get(String, headers, "x-pi-gateway-upstream-provider")))
        return Done{Unit{}}

def caseOptions(+mode: String) -> Options():
  match mode:
    case "stream": detailed()
    case "stale": keyed("stale")
    case "no-key": unkeyed()
    case _: keyed("test-key")

def streamed(fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +events: Stream(), mode: String, baseUrl: String) -> IO(Unit):
  match mode:
    case "debug":
      do IO<Unit>:
        +hook : T.ResponseCallback(T.Model<J()>, Error()) <- C.create(~Unit, ~T.ResponseInput<T.Model<J()>>, ~Result<&2, &2, Error(), Unit>, ~observe, Unit{})
        Pi.streamSimple(~Unit, ~Unit, ~Error(), ~J(), ~Unit, ~render, ~identity, ~MessageJson.jsonValue, ~unitDetails, events, fetch, urlContext(), signal, createModel(baseUrl), context(), Some{T.withOnResponse(J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error(), T.withApiKey(J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error(), T.emptySimpleStreamOptions(J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()), Some{"test-key"}), Some{hook})}, Some{True{}})
        C.dispose(T.ResponseInput<T.Model<J()>>, Result<&2, &2, Error(), Unit>, hook)
    case _: Pi.stream(~Unit, ~Unit, ~Error(), ~J(), ~Unit, ~render, ~identity, ~MessageJson.jsonValue, ~unitDetails, events, fetch, urlContext(), signal, createModel(baseUrl), context(), caseOptions(mode))

def borrowed(mode: String, baseUrl: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (owned, +fetch):
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        +events : Stream() <- Events.createAssistantMessageEventStream(~V.Value, ~J())
        streamed(fetch, Abort.signal(Unit, controller), events, mode, baseUrl)
        report(events)
        Abort.dispose(Unit, controller)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(owned)

def active(mode: String, baseUrl: String, runtime: Fetch.Runtime) -> IO(Unit):
  do IO<Unit>:
    pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
    borrowed(mode, baseUrl, pair)

def initialized(mode: String, baseUrl: String, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}: active(mode, baseUrl, runtime)

def run(mode: String, baseUrl: String) -> IO(Unit):
  do IO<Unit>:
    runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), networkOptions())
    initialized(mode, baseUrl, runtime)

# upstream "is a known api usable on models": the name selects the typed api.
def known(api: T.ModelApi) -> IO(Unit):
  match api:
    case T.PiMessagesApi{}: IO.print("api " ++ ModelApi.name(T.PiMessagesApi{}) ++ " registered")
    case _: IO.die(Unit, 1, "pi-messages is not a known api")

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case "api" <> _ <> Nil{}: known(ModelApi.fromString("pi-messages"))
    case mode <> baseUrl <> Nil{}: run(mode, baseUrl)
    case _: IO.die(Unit, 1, "usage: pi-messages <case> <baseUrl>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

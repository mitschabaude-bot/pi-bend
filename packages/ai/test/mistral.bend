import Base
import ../src/api/mistral-conversations.bend as Mistral
import ../src/providers/mistral.models.bend as Catalog
import ../src/types.bend as T
import ../src/utils/event-stream.bend as Events
import ../src/utils/message-json.bend as MessageJson
import ../src/utils/schema-json.bend as SchemaJson
import ../src/utils/json.bend as JsonWire
import ../src/utils/transcript.bend as Transcript
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

# The upstream Mistral suites (mistral-http-transport, mistral-raw-stop-reason,
# mistral-reasoning-mode, mistral-tool-schema) against a loopback server run by
# tests/mistral_check.py: `mistral <case> <baseUrl>` streams one case and
# prints the payload onPayload saw, the onResponse value, every event and the
# final message as JSON lines. Upstream's fetch stubs become loopback
# responses; the checker asserts the upstream expectations and compares the
# trace with upstream mistral-conversations.ts against the same server.

def J() -> Data: T.JsonValue

def Error() -> Data: String

def Stream() -> Data: Events.AssistantMessageEventStream(V.Value, Unit)

def Options() -> Data: Mistral.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error())

def Simple() -> Data: T.SimpleStreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>

def Base() -> Data: T.StreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>

def Context() -> Data: T.TranscriptContext<V.Value, V.Value, Unit, Unit>

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def networkOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}

def render(value: Error()) -> String: value

def zero() -> F64: F.fromU32(0)

def json(value: V.Value) -> String: Maybe.default(&2, String, JsonWire.stringify(SchemaJson.toJson(value)), "null")

def jsonValue(value: J()) -> String: Maybe.default(&2, String, JsonWire.stringify(value), "null")

def unitDetails(value: Unit) -> V.Value: V.Null{}

# Models
# ------

def base(key: Maybe<&2, String>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, Error())>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, Error())>, headers: Maybe<&2, T.ProviderHeaders()>, maxTokens: Maybe<&2, F64>, sessionId: Maybe<&2, String>, timeoutMs: Maybe<&2, F64>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> Base():
  T.StreamOptions{signal, None{}, key, None{}, None{}, onPayload, onResponse, headers, timeoutMs, None{}, None{}, None{}, None{}, maxTokens, None{}, None{}, sessionId, None{}, None{}}

def withBase(value: T.Model<J()>, base: String) -> T.Model<J()>:
  match value:
    case T.Model{id, name, api, provider, _, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}:
      T.Model{id, name, api, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}

def withHeaders(value: T.Model<J()>, headers: R.Record<String>) -> T.Model<J()>:
  match value:
    case T.Model{id, name, api, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, _, compat}:
      T.Model{id, name, api, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, Some{headers}, compat}

def large(base: String) -> T.Model<J()>: withBase(Catalog.model_mistral_large_latest(), base)

# upstream mistral-reasoning-mode.test.ts makeModel.
def makeModel(+id: String, reasoning: Bool, base: String) -> T.Model<J()>:
  T.Model{id, id, T.MistralConversationsApi{}, "mistral", base, reasoning, None{}, [T.InputText{}], None{}, T.ModelCost{zero(), zero(), zero(), zero(), None{}}, None{}, F.fromU32(128000), F.fromU32(16384), None{}, None{}, None{}}

# Contexts
# --------

def text(value: String) -> V.Value: V.Text{value}

def user(text: String) -> T.Message<V.Value, V.Value, Unit, Unit>: T.User{T.UserMessage{T.UserText{text}, F.fromU32(1)}}

def hello() -> Context(): T.TranscriptContext{[user("hello")]}

def object(fields: List<&2, R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}

# Type.Object({ query: Type.String() }) as TypeBox serializes it.
def lookupSchema() -> V.Value:
  object([R.Property{"type", text("object")}, R.Property{"required", V.ArrayValue{[text("query")]}}, R.Property{"properties", object([R.Property{"query", object([R.Property{"type", text("string")}])}])}])

def sdkContext() -> Context():
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{Some{"Be precise"}, [T.User{T.UserMessage{T.UserBlocks{[T.TextImageText{T.TextContent{"describe", None{}}}, T.TextImageImage{T.ImageContent{"aGVsbG8=", "image/png"}}]}, F.fromU32(1)}}], Some{[T.Tool{"lookup", "Look something up", lookupSchema(), None{}}]}})

def emptyUsage() -> T.Usage: T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}

def replayContext() -> Context():
  T.TranscriptContext{[T.Assistant{T.AssistantMessage{[T.AssistantThinking{T.ThinkingContent{"reason", None{}, None{}}}, T.AssistantText{T.TextContent{"answer", None{}}}, T.AssistantToolCall{T.ToolCall{"abc123456", "lookup", object([R.Property{"query", text("pi")}]), None{}, None{}}}], "mistral-conversations", "mistral", "mistral-large-latest", None{}, None{}, None{}, None{}, emptyUsage(), T.ToolUse{}, None{}, None{}, None{}, None{}, F.fromU32(1)}}, T.ToolResult{T.ToolResultMessage{"abc123456", "lookup", [T.TextImageText{T.TextContent{"found", None{}}}, T.TextImageImage{T.ImageContent{"aGVsbG8=", "image/png"}}], None{}, None{}, False{}, F.fromU32(2)}}]}

# Type.Object({ nested: Type.Object({ value: Type.String() }) }).
def nestedSchema() -> V.Value:
  object([R.Property{"type", text("object")}, R.Property{"required", V.ArrayValue{[text("nested")]}}, R.Property{"properties", object([R.Property{"nested", object([R.Property{"type", text("object")}, R.Property{"required", V.ArrayValue{[text("value")]}}, R.Property{"properties", object([R.Property{"value", object([R.Property{"type", text("string")}])}])}])}])}])

def toolSchemaContext() -> Context():
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{None{}, [user("Hi")], Some{[T.Tool{"inspect_schema", "Inspect the schema", nestedSchema(), Some{T.SamplingConfigured{T.JsonSchemaSampling{T.Require{}}}}}]}})

# Options
# -------

def keyed(key: String) -> Options():
  Mistral.MistralOptions{base(Some{key}, None{}, None{}, None{}, None{}, None{}, None{}, None{}), None{}, None{}, None{}}

def jnum(value: F64) -> J(): T.JsonNumber{value}

def jstr(value: String) -> J(): T.JsonString{value}

def jobj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}

def tenth(value: U32) -> F64: F.divide(F.fromU32(value), F.fromU32(10))

# The first transport case's onPayload: the SDK payload plus sampling members.
def extended(fields: R.Record<J()>) -> R.Record<J()>:
  +a = R.set(J(), fields, "topP", jnum(tenth(9)))
  +b = R.set(J(), a, "randomSeed", jnum(F.fromU32(42)))
  +c = R.set(J(), b, "responseFormat", jobj([R.Property{"type", jstr("json_schema")}, R.Property{"jsonSchema", jobj([R.Property{"name", jstr("result")}, R.Property{"schemaDefinition", jobj([R.Property{"type", jstr("object")}, R.Property{"properties", jobj([R.Property{"maxTokens", jobj([R.Property{"type", jstr("number")}])}])}])}])}]))
  +d = R.set(J(), c, "presencePenalty", jnum(tenth(1)))
  +e = R.set(J(), d, "frequencyPenalty", jnum(tenth(2)))
  +f = R.set(J(), e, "parallelToolCalls", T.JsonBoolean{True{}})
  R.set(J(), f, "safePrompt", T.JsonBoolean{True{}})

def extendedPayload(payload: J()) -> J():
  match payload:
    case T.JsonObject{fields}: T.JsonObject{extended(fields)}
    case other: other

def extend(unused: Unit, input: T.PayloadInput<J(), T.Model<J()>>) -> IO(Result<&2, &2, Error(), Maybe<&2, J()>>):
  match input:
    case T.PayloadInput{+payload, _}:
      do IO<Result<&2, &2, Error(), Maybe<&2, J()>>>:
        IO.print("payload " ++ jsonValue(payload))
        return Done{Some{extendedPayload(payload)}}

def capture(unused: Unit, input: T.PayloadInput<J(), T.Model<J()>>) -> IO(Result<&2, &2, Error(), Maybe<&2, J()>>):
  match input:
    case T.PayloadInput{+payload, _}:
      do IO<Result<&2, &2, Error(), Maybe<&2, J()>>>:
        IO.print("payload " ++ jsonValue(payload))
        return Done{None{}}

def headerFields(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<J()>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, jstr(value)} <> headerFields(rest)

def responseJson(value: T.ProviderResponse) -> J():
  match value:
    case T.ProviderResponse{status, R.Record{headers}}: jobj([R.Property{"status", jnum(status)}, R.Property{"headers", jobj(headerFields(headers))}])

def observe(unused: Unit, input: T.ResponseInput<T.Model<J()>>) -> IO(Result<&2, &2, Error(), Unit>):
  match input:
    case T.ResponseInput{response, _}:
      do IO<Result<&2, &2, Error(), Unit>>:
        IO.print("response " ++ jsonValue(responseJson(response)))
        return Done{Unit{}}

def present(value: String) -> T.Nullable<String>: T.PresentValue{value}

# Reporting
# ---------

def eventLine(event: T.AssistantMessageEvent<V.Value, Unit>) -> String:
  json(MessageJson.assistantMessageEvent(~Unit, ~unitDetails, event))

@unsafe def drain(+cursor: Events.Iterator<T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>>, step: Maybe<&2, Events.Iteration<T.AssistantMessageEvent<V.Value, Unit>>>) -> IO(Unit):
  match step:
    case Some{Events.End{}}: Events.disposeIterator(T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>, cursor)
    case Some{Events.Yield{event}}:
      do IO<Unit>:
        IO.print("event " ++ eventLine(event))
        drain(cursor, None{})
    case None{}:
      do IO<Unit>:
        next : Events.Iteration<T.AssistantMessageEvent<V.Value, Unit>> <- Events.nextValue(T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>, cursor)
        drain(cursor, Some{next})

def report(+events: Stream()) -> IO(Unit):
  do IO<Unit>:
    Events.end(T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>, events, None{})
    +cursor : Events.Iterator<T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>> <- Events.iterator(T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>, events)
    drain(cursor, None{})
    message : T.AssistantMessage<V.Value, Unit> <- Events.resultValue(T.AssistantMessageEvent<V.Value, Unit>, T.AssistantMessage<V.Value, Unit>, events)
    IO.print("result " ++ json(MessageJson.assistantMessage(~Unit, ~unitDetails, message)))
    Events.disposeAssistantMessageEventStream(V.Value, Unit, events)

def simpleReported(result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{message}: IO.print("thrown " ++ message)

# Cases
# -----

def streamed(fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +events: Stream(), model: T.Model<J()>, context: Context(), options: Options()) -> IO(Unit):
  Mistral.stream(~Unit, ~Unit, ~Error(), ~Unit, ~Unit, ~render, events, fetch, urlContext(), signal, model, context, options)

def simple(fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +events: Stream(), model: T.Model<J()>, context: Context(), options: Simple()) -> IO(Unit):
  do IO<Unit>:
    +hook : T.PayloadCallback(J(), T.Model<J()>, Error()) <- C.create(~Unit, ~T.PayloadInput<J(), T.Model<J()>>, ~Result<&2, &2, Error(), Maybe<&2, J()>>, ~capture, Unit{})
    result : Result<&2, &2, String, Unit> <- Mistral.streamSimple(~Unit, ~Unit, ~Error(), ~Unit, ~Unit, ~render, events, fetch, urlContext(), signal, model, context, Some{T.withOnPayload(J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error(), T.withApiKey(J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error(), options, Some{"fake-key"}), Some{hook})})
    simpleReported(result)
    C.dispose(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, Error(), Maybe<&2, J()>>, hook)

def emptySimple() -> Simple(): T.emptySimpleStreamOptions(J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error())

def reasoningOptions(level: Maybe<&2, T.ThinkingLevel>, sessionId: Maybe<&2, String>, retention: Maybe<&2, T.CacheRetention>) -> Simple():
  T.SimpleStreamOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, retention, sessionId, None{}, None{}, None{}, level, None{}, None{}}

def medium() -> Maybe<&2, T.ThinkingLevel>: Some{T.Medium{}}

def sdkCase(fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +events: Stream(), baseUrl: String) -> IO(Unit):
  do IO<Unit>:
    +payloadHook : T.PayloadCallback(J(), T.Model<J()>, Error()) <- C.create(~Unit, ~T.PayloadInput<J(), T.Model<J()>>, ~Result<&2, &2, Error(), Maybe<&2, J()>>, ~extend, Unit{})
    +responseHook : T.ResponseCallback(T.Model<J()>, Error()) <- C.create(~Unit, ~T.ResponseInput<T.Model<J()>>, ~Result<&2, &2, Error(), Unit>, ~observe, Unit{})
    streamed(fetch, signal, events, large(baseUrl), sdkContext(), Mistral.MistralOptions{base(Some{"secret"}, Some{payloadHook}, Some{responseHook}, Some{R.Record{[R.Property{"x-custom", present("value")}]}}, Some{F.fromU32(123)}, Some{"session-1"}, None{}, None{}), Some{Mistral.ChoiceFunction{"lookup"}}, Some{Unit{}}, Some{"high"}})
    C.dispose(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, Error(), Maybe<&2, J()>>, payloadHook)
    C.dispose(T.ResponseInput<T.Model<J()>>, Result<&2, &2, Error(), Unit>, responseHook)

def overridesCase(fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +events: Stream(), baseUrl: String) -> IO(Unit):
  streamed(fetch, signal, events, withHeaders(large(baseUrl), R.Record{[R.Property{"Authorization", "Bearer model-key"}, R.Property{"X-Affinity", "model-affinity"}]}), hello(), Mistral.MistralOptions{base(Some{"request-key"}, None{}, None{}, Some{R.Record{[R.Property{"authorization", T.NullValue{}}, R.Property{"x-affinity", T.NullValue{}}, R.Property{"User-Agent", present("custom-agent")}]}}, None{}, Some{"automatic-affinity"}, None{}, None{}), None{}, None{}, None{}})

def aborting(controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(300)
    aborted : Bool <- Abort.abort(Unit, controller, None{})
    return Unit{}

def abortCase(fetch: Fetch.Fetch(Unit), +events: Stream(), baseUrl: String) -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    task : Chan(Unit) <- IO.fork(Unit, aborting(controller))
    streamed(fetch, Abort.signal(Unit, controller), events, large(baseUrl), hello(), Mistral.MistralOptions{base(Some{"test"}, None{}, None{}, None{}, None{}, None{}, None{}, Some{Abort.signal(Unit, controller)}), None{}, None{}, None{}})
    finished : Unit <- IO.join(Unit, task)
    Abort.dispose(Unit, controller)

def toolSchemaCase(fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +events: Stream(), baseUrl: String) -> IO(Unit):
  do IO<Unit>:
    +hook : T.PayloadCallback(J(), T.Model<J()>, Error()) <- C.create(~Unit, ~T.PayloadInput<J(), T.Model<J()>>, ~Result<&2, &2, Error(), Maybe<&2, J()>>, ~capture, Unit{})
    streamed(fetch, signal, events, withBase(Catalog.model_devstral_medium_latest(), baseUrl), toolSchemaContext(), Mistral.MistralOptions{base(Some{"fake-key"}, Some{hook}, None{}, None{}, None{}, None{}, None{}, None{}), None{}, None{}, None{}})
    C.dispose(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, Error(), Maybe<&2, J()>>, hook)

def selected(fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +events: Stream(), +mode: String, baseUrl: String) -> IO(Unit):
  match mode:
    case "sdk-payload": sdkCase(fetch, signal, events, baseUrl)
    case "replay": streamed(fetch, signal, events, large(baseUrl), replayContext(), keyed("test"))
    case "header-overrides": overridesCase(fetch, signal, events, baseUrl)
    case "abort": abortCase(fetch, events, baseUrl)
    case "timeout": streamed(fetch, signal, events, large(baseUrl), hello(), Mistral.MistralOptions{base(Some{"test"}, None{}, None{}, None{}, None{}, None{}, Some{F.fromU32(5)}, None{}), None{}, None{}, None{}})
    case "raw-stop": streamed(fetch, signal, events, withBase(Catalog.model_devstral_medium_latest(), baseUrl), hello(), keyed("test"))
    case "raw-error": streamed(fetch, signal, events, withBase(Catalog.model_devstral_medium_latest(), baseUrl), hello(), keyed("test"))
    case "raw-unmapped": streamed(fetch, signal, events, withBase(Catalog.model_devstral_medium_latest(), baseUrl), hello(), keyed("test"))
    case "reasoning-small-medium": simple(fetch, signal, events, makeModel("mistral-small-2603", True{}, baseUrl), hello(), reasoningOptions(medium(), None{}, None{}))
    case "reasoning-small-off": simple(fetch, signal, events, makeModel("mistral-small-2603", True{}, baseUrl), hello(), emptySimple())
    case "reasoning-magistral": simple(fetch, signal, events, makeModel("magistral-medium-latest", True{}, baseUrl), hello(), reasoningOptions(medium(), None{}, None{}))
    case "reasoning-glm-on": simple(fetch, signal, events, makeModel("zai-glm-5-2", True{}, baseUrl), hello(), reasoningOptions(medium(), None{}, None{}))
    case "reasoning-glm-off": simple(fetch, signal, events, makeModel("zai-glm-5-2", True{}, baseUrl), hello(), emptySimple())
    case "reasoning-medium-2604-on": simple(fetch, signal, events, makeModel("mistral-medium-2604", True{}, baseUrl), hello(), reasoningOptions(medium(), None{}, None{}))
    case "reasoning-medium-2604-off": simple(fetch, signal, events, makeModel("mistral-medium-2604", True{}, baseUrl), hello(), emptySimple())
    case "reasoning-medium-latest-on": simple(fetch, signal, events, makeModel("mistral-medium-latest", True{}, baseUrl), hello(), reasoningOptions(medium(), None{}, None{}))
    case "reasoning-medium-latest-off": simple(fetch, signal, events, makeModel("mistral-medium-latest", True{}, baseUrl), hello(), emptySimple())
    case "reasoning-medium-2505": simple(fetch, signal, events, makeModel("mistral-medium-2505", False{}, baseUrl), hello(), reasoningOptions(medium(), None{}, None{}))
    case "cache-key": simple(fetch, signal, events, makeModel("mistral-large-latest", False{}, baseUrl), hello(), reasoningOptions(None{}, Some{"session-123"}, None{}))
    case "cache-none": simple(fetch, signal, events, makeModel("mistral-large-latest", False{}, baseUrl), hello(), reasoningOptions(None{}, Some{"session-123"}, Some{T.CacheNone{}}))
    case "tool-schema": toolSchemaCase(fetch, signal, events, baseUrl)
    case _: streamed(fetch, signal, events, large(baseUrl), hello(), keyed("test"))

def borrowed(mode: String, baseUrl: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (owned, +fetch):
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        +events : Stream() <- Events.createAssistantMessageEventStream(~V.Value, ~Unit)
        selected(fetch, Abort.signal(Unit, controller), events, mode, baseUrl)
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

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> baseUrl <> Nil{}: run(mode, baseUrl)
    case _: IO.die(Unit, 1, "usage: mistral <case> <baseUrl>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

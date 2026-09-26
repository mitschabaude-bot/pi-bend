import Base
import ../src/api/bedrock-converse-stream.bend as Bedrock
import ../src/providers/amazon-bedrock.models.bend as Catalog
import ../src/types.bend as T
import ../src/utils/event-stream.bend as Events
import ../src/utils/message-json.bend as MessageJson
import ../src/utils/schema-json.bend as SchemaJson
import ../src/utils/json.bend as JsonWire
import ../src/utils/transcript.bend as Transcript
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/aws-sigv4.bend as SigV4
import ../../runtime/src/callback.bend as C
import ../../runtime/src/connection-driver.bend as Connect
import ../../runtime/src/dns-resolver.bend as DNS
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-exchange.bend as HTTP
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/idna.bend as IDNA
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../../runtime/src/unicode-17-idna-properties.bend as Properties
import ../../runtime/src/unicode-17-normalization.bend as Normalization
import ../../runtime/src/url.bend as URL

# The upstream Bedrock suites against a loopback server run by
# tests/bedrock_check.py: `bedrock '<case JSON>'` streams one case described
# by the checker (catalog model and overrides, transcript, options, stream or
# streamSimple, a pre-aborted signal) and prints the client configuration,
# the payload onPayload saw, the onResponse value, every event and the final
# message as JSON lines. Upstream mocks the AWS SDK; here the requests reach
# the server, and the checker compares traces with upstream (real SDK).

def J() -> Data: T.JsonValue

def Error() -> Data: String

def Stream() -> Data: Events.AssistantMessageEventStream(V.Value, J())

def Options() -> Data: Bedrock.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error())

def Simple() -> Data: T.SimpleStreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>

def Context() -> Data: T.TranscriptContext<V.Value, V.Value, J(), J()>

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def networkOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}

def render(value: Error()) -> String: value

def identity(value: J()) -> J(): value

def jsonText(value: J()) -> String: Maybe.default(&2, String, JsonWire.stringify(value), "null")

def json(value: V.Value) -> String: jsonText(SchemaJson.toJson(value))

# Case fields
# -----------

def get(+fields: R.Record<V.Value>, name: String) -> Maybe<&2, V.Value>: R.get(V.Value, fields, name)

def text(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{value}}: Some{value}
    case _: None{}

def number(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{value}}: Some{value}
    case _: None{}

def flag(value: Maybe<&2, V.Value>) -> Maybe<&2, Bool>:
  match value:
    case Some{V.Boolean{value}}: Some{value}
    case _: None{}

def fieldsOf(value: Maybe<&2, V.Value>) -> R.Record<V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: fields
    case _: R.new(V.Value)

def itemsOf(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{items}}: items
    case _: Nil{}

def stringRecord(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<String>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, V.Text{value}} <> rest: R.Property{name, value} <> stringRecord(rest)
    case _ <> rest: stringRecord(rest)

def nullableRecord(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<T.Nullable<String>>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, V.Text{value}} <> rest: R.Property{name, T.PresentValue{value}} <> nullableRecord(rest)
    case R.Property{name, V.Null{}} <> rest: R.Property{name, T.NullValue{}} <> nullableRecord(rest)
    case _ <> rest: nullableRecord(rest)

def recordOf(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<String>>:
  match value:
    case Some{V.ObjectValue{R.Record{entries}}}: Some{R.Record{stringRecord(entries)}}
    case _: None{}

def headersOf(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ProviderHeaders()>:
  match value:
    case Some{V.ObjectValue{R.Record{entries}}}: Some{R.Record{nullableRecord(entries)}}
    case _: None{}

def level(value: Maybe<&2, String>) -> Maybe<&2, T.ThinkingLevel>:
  match value:
    case Some{"minimal"}: Some{T.Minimal{}}
    case Some{"low"}: Some{T.Low{}}
    case Some{"medium"}: Some{T.Medium{}}
    case Some{"high"}: Some{T.High{}}
    case Some{"xhigh"}: Some{T.XHigh{}}
    case Some{"max"}: Some{T.Max{}}
    case _: None{}

def retention(value: Maybe<&2, String>) -> Maybe<&2, T.CacheRetention>:
  match value:
    case Some{"none"}: Some{T.CacheNone{}}
    case Some{"short"}: Some{T.CacheShort{}}
    case Some{"long"}: Some{T.CacheLong{}}
    case _: None{}

def display(value: Maybe<&2, String>) -> Maybe<&2, Bedrock.BedrockThinkingDisplay>:
  match value:
    case Some{"summarized"}: Some{Bedrock.DisplaySummarized{}}
    case Some{"omitted"}: Some{Bedrock.DisplayOmitted{}}
    case _: None{}

def choice(value: Maybe<&2, V.Value>) -> Maybe<&2, Bedrock.BedrockToolChoice>:
  match value:
    case Some{V.Text{"auto"}}: Some{Bedrock.ChoiceAuto{}}
    case Some{V.Text{"any"}}: Some{Bedrock.ChoiceAny{}}
    case Some{V.Text{"none"}}: Some{Bedrock.ChoiceNone{}}
    case Some{V.ObjectValue{fields}}: Maybe.map(&2, String, Bedrock.BedrockToolChoice, name => Bedrock.ChoiceTool{name}, text(R.get(V.Value, fields, "name")))
    case _: None{}

def budgets(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ThinkingBudgets>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{T.ThinkingBudgets{number(get(fields, "minimal")), number(get(fields, "low")), number(get(fields, "medium")), number(get(fields, "high"))}}
    case _: None{}

# Models
# ------

def catalogModel(models: List<&2, T.Model<J()>>, +id: String) -> Maybe<&2, T.Model<J()>>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Maybe<&2, T.Model<J()>>, String.eq(T.modelId(model), id), Some{model}, catalogModel(rest, id))

def inputs(values: List<&2, V.Value>) -> List<&2, T.ModelInput>:
  match values:
    case Nil{}: Nil{}
    case V.Text{"image"} <> rest: T.InputImage{} <> inputs(rest)
    case _ <> rest: T.InputText{} <> inputs(rest)

def strictCompat(value: Maybe<&2, V.Value>, previous: Maybe<&2, T.BedrockCompat>) -> Maybe<&2, T.BedrockCompat>:
  match value:
    case Some{V.Null{}}: None{}
    case Some{V.ObjectValue{fields}}: Some{T.BedrockCompat{flag(R.get(V.Value, fields, "supportsStrictMode"))}}
    case _: previous

def compatOf(model: T.Model<J()>) -> Maybe<&2, T.BedrockCompat>:
  match model:
    case T.Model{_, _, T.BedrockConverseStreamApi{}, _, _, _, _, _, _, _, _, _, _, _, _, compat}: compat
    case _: None{}

def overriddenWith(+fields: R.Record<V.Value>, model: T.Model<J()>, compat: Maybe<&2, T.BedrockCompat>) -> T.Model<J()>:
  match model:
    case T.Model{id, name, _, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, _}:
      T.Model{Maybe.default(&2, String, text(get(fields, "id")), id), Maybe.default(&2, String, text(get(fields, "name")), name), T.BedrockConverseStreamApi{}, provider, Maybe.default(&2, String, text(get(fields, "baseUrl")), base), Maybe.default(&2, Bool, flag(get(fields, "reasoning")), reasoning), levels, Bool.pick(List<&2, T.ModelInput>, Maybe.is_some(&2, V.Value, get(fields, "input")), inputs(itemsOf(get(fields, "input"))), input), limits, cost, cache, Maybe.default(&2, F64, number(get(fields, "contextWindow")), window), Maybe.default(&2, F64, number(get(fields, "maxTokens")), maximum), sampling, headers, strictCompat(get(fields, "compat"), compat)}

# The catalog model with the case's overrides (upstream `{ ...model, ... }`).
def overridden(+fields: R.Record<V.Value>, +model: T.Model<J()>) -> T.Model<J()>:
  overriddenWith(fields, model, compatOf(model))

def modelOf(+spec: R.Record<V.Value>) -> T.Model<J()>:
  overridden(fieldsOf(get(spec, "model")), Maybe.default(&2, T.Model<J()>, catalogModel(Catalog.AMAZON_BEDROCK_MODELS(), Maybe.default(&2, String, text(get(fieldsOf(get(spec, "model")), "catalog")), "")), Catalog.model_us_anthropic_claude_opus_4_8()))

# Contexts
# --------

def decodedValue(-A: Data, result: Result<&2, &2, Decode.Error, A>, fallback: A) -> A:
  match result:
    case Done{value}: value
    case Fail{_}: fallback

def jsonDetails(value: V.Value) -> Result<&2, &2, Decode.Error, J()>: Done{SchemaJson.toJson(value)}

def decodedMessage(result: Result<&2, &2, Decode.Error, T.Message<V.Value, V.Value, J(), J()>>, rest: List<&2, T.Message<V.Value, V.Value, J(), J()>>) -> List<&2, T.Message<V.Value, V.Value, J(), J()>>:
  match result:
    case Done{message}: message <> rest
    case Fail{_}: rest

def messages(values: List<&2, V.Value>) -> List<&2, T.Message<V.Value, V.Value, J(), J()>>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: decodedMessage(MessageJson.decodeMessage(~J(), ~J(), ~jsonDetails, ~jsonDetails, value), messages(rest))

def decodedTool(result: Result<&2, &2, Decode.Error, T.Tool<V.Value>>, rest: List<&2, T.Tool<V.Value>>) -> List<&2, T.Tool<V.Value>>:
  match result:
    case Done{tool}: tool <> rest
    case Fail{_}: rest

def tools(values: List<&2, V.Value>) -> List<&2, T.Tool<V.Value>>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: decodedTool(MessageJson.decodeTool(value), tools(rest))

def toolList(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, T.Tool<V.Value>>>:
  match value:
    case Some{V.ArrayValue{items}}: Some{tools(items)}
    case _: None{}

# upstream normalizeContext over the case's systemPrompt, messages and tools.
def contextOf(+spec: R.Record<V.Value>) -> Context():
  +context = fieldsOf(get(spec, "context"))
  Transcript.normalizeContext(V.Value, V.Value, J(), J(), T.Context{text(get(context, "systemPrompt")), messages(itemsOf(get(context, "messages"))), toolList(get(context, "tools"))})

# Options and hooks
# -----------------

def capture(unused: Unit, input: T.PayloadInput<J(), T.Model<J()>>) -> IO(Result<&2, &2, Error(), Maybe<&2, J()>>):
  match input:
    case T.PayloadInput{payload, _}:
      do IO<Result<&2, &2, Error(), Maybe<&2, J()>>>:
        IO.print("payload " ++ jsonText(payload))
        return Done{None{}}

def headerFields(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<J()>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, T.JsonString{value}} <> headerFields(rest)

def responseJson(value: T.ProviderResponse) -> J():
  match value:
    case T.ProviderResponse{status, R.Record{headers}}: T.JsonObject{R.Record{[R.Property{"status", T.JsonNumber{status}}, R.Property{"headers", T.JsonObject{R.Record{headerFields(headers)}}}]}}

def observe(unused: Unit, input: T.ResponseInput<T.Model<J()>>) -> IO(Result<&2, &2, Error(), Unit>):
  match input:
    case T.ResponseInput{response, _}:
      do IO<Result<&2, &2, Error(), Unit>>:
        IO.print("response " ++ jsonText(responseJson(response)))
        return Done{Unit{}}

def hookWhen(-A: Data, enabled: Maybe<&2, Bool>, hook: A) -> Maybe<&2, A>:
  match enabled:
    case Some{True{}}: Some{hook}
    case _: None{}

def envOf(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ProviderEnv()>: recordOf(value)

def baseOptions(+options: R.Record<V.Value>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, Error())>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, Error())>) -> T.StreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>:
  T.StreamOptions{signal, None{}, text(get(options, "apiKey")), None{}, envOf(get(options, "env")), onPayload, onResponse, headersOf(get(options, "headers")), None{}, None{}, None{}, number(get(options, "temperature")), None{}, number(get(options, "maxTokens")), None{}, retention(text(get(options, "cacheRetention"))), None{}, None{}, None{}}

def streamOptions(+options: R.Record<V.Value>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, Error())>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, Error())>) -> Options():
  Bedrock.BedrockOptions{baseOptions(options, signal, onPayload, onResponse), text(get(options, "region")), text(get(options, "profile")), choice(get(options, "toolChoice")), level(text(get(options, "reasoning"))), budgets(get(options, "thinkingBudgets")), flag(get(options, "interleavedThinking")), display(text(get(options, "thinkingDisplay"))), recordOf(get(options, "requestMetadata")), text(get(options, "bearerToken"))}

def simpleChoice(value: Maybe<&2, String>) -> Maybe<&2, T.ToolChoice>:
  match value:
    case Some{"auto"}: Some{T.AutoTool{}}
    case Some{"none"}: Some{T.NoTool{}}
    case _: None{}

def simpleOptions(+options: R.Record<V.Value>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, Error())>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, Error())>) -> Simple():
  T.SimpleStreamOptions{signal, None{}, text(get(options, "apiKey")), None{}, envOf(get(options, "env")), onPayload, onResponse, headersOf(get(options, "headers")), None{}, None{}, None{}, number(get(options, "temperature")), None{}, number(get(options, "maxTokens")), None{}, retention(text(get(options, "cacheRetention"))), None{}, None{}, None{}, simpleChoice(text(get(options, "toolChoice"))), level(text(get(options, "reasoning"))), None{}, budgets(get(options, "thinkingBudgets"))}

# Reporting
# ---------

def optionalProperty(name: String, value: Maybe<&2, J()>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match value:
    case None{}: rest
    case Some{item}: R.Property{name, item} <> rest

def credentialsJson(value: SigV4.Credentials) -> J():
  match value:
    case SigV4.Credentials{access, secret, token}: T.JsonObject{R.Record{R.Property{"accessKeyId", T.JsonString{access}} <> R.Property{"secretAccessKey", T.JsonString{secret}} <> optionalProperty("sessionToken", Maybe.map(&2, String, J(), value => T.JsonString{value}, token), Nil{})}}

def str(value: String) -> J(): T.JsonString{value}

# The SDK client configuration upstream builds, in its member names.
def configJson(config: Bedrock.ClientConfig) -> J():
  match config:
    case Bedrock.ClientConfig{profile, region, endpoint, credentials, +token}:
      T.JsonObject{R.Record{optionalProperty("profile", Maybe.map(&2, String, J(), str, profile), optionalProperty("endpoint", Maybe.map(&2, String, J(), str, endpoint), optionalProperty("region", Maybe.map(&2, String, J(), str, region), optionalProperty("credentials", Maybe.map(&2, SigV4.Credentials, J(), credentialsJson, credentials), optionalProperty("token", Maybe.map(&2, String, J(), value => T.JsonObject{R.Record{[R.Property{"token", str(value)}]}}, token), optionalProperty("authSchemePreference", Maybe.map(&2, String, J(), value => T.JsonArray{[str("httpBearerAuth")]}, token), Nil{}))))))}}

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

# Running
# -------

def mode(+spec: R.Record<V.Value>) -> String: Maybe.default(&2, String, text(get(spec, "mode")), "stream")

def streamedIn(fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +events: Stream(), +spec: R.Record<V.Value>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, Error())>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, Error())>, kind: String, +options: R.Record<V.Value>, requestSignal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Unit):
  match kind:
    case "simple": Bedrock.streamSimple(~Unit, ~Unit, ~Error(), ~J(), ~J(), ~render, ~identity, events, fetch, urlContext(), signal, modelOf(spec), contextOf(spec), Some{simpleOptions(options, requestSignal, onPayload, onResponse)})
    case _: Bedrock.stream(~Unit, ~Unit, ~Error(), ~J(), ~J(), ~render, ~identity, events, fetch, urlContext(), signal, modelOf(spec), contextOf(spec), streamOptions(options, requestSignal, onPayload, onResponse))

def streamed(fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +events: Stream(), +spec: R.Record<V.Value>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, Error())>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, Error())>) -> IO(Unit):
  streamedIn(fetch, signal, events, spec, onPayload, onResponse, mode(spec), fieldsOf(get(spec, "options")), Bool.pick(Maybe<&2, Abort.AbortSignal<Unit>>, Maybe.default(&2, Bool, flag(get(spec, "abort")), False{}), Some{signal}, None{}))

def abortedIf(controller: Abort.AbortController<Unit>, abort: Bool) -> IO(Unit):
  match abort:
    case True{}:
      do IO<Unit>:
        done : Bool <- Abort.abort(Unit, controller, None{})
        return Unit{}
    case False{}: IO.pure(Unit, Unit{})

def aborted(controller: Abort.AbortController<Unit>, +spec: R.Record<V.Value>) -> IO(Unit): abortedIf(controller, Maybe.default(&2, Bool, flag(get(spec, "abort")), False{}))

def borrowed(+spec: R.Record<V.Value>, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (owned, +fetch):
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        aborted(controller, spec)
        +events : Stream() <- Events.createAssistantMessageEventStream(~V.Value, ~J())
        +payloadHook : T.PayloadCallback(J(), T.Model<J()>, Error()) <- C.create(~Unit, ~T.PayloadInput<J(), T.Model<J()>>, ~Result<&2, &2, Error(), Maybe<&2, J()>>, ~capture, Unit{})
        +responseHook : T.ResponseCallback(T.Model<J()>, Error()) <- C.create(~Unit, ~T.ResponseInput<T.Model<J()>>, ~Result<&2, &2, Error(), Unit>, ~observe, Unit{})
        streamed(fetch, Abort.signal(Unit, controller), events, spec, hookWhen(T.PayloadCallback(J(), T.Model<J()>, Error()), flag(get(spec, "capture")), payloadHook), hookWhen(T.ResponseCallback(T.Model<J()>, Error()), flag(get(spec, "observe")), responseHook))
        report(events)
        C.dispose(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, Error(), Maybe<&2, J()>>, payloadHook)
        C.dispose(T.ResponseInput<T.Model<J()>>, Result<&2, &2, Error(), Unit>, responseHook)
        Abort.dispose(Unit, controller)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(owned)

def active(+spec: R.Record<V.Value>, runtime: Fetch.Runtime) -> IO(Unit):
  do IO<Unit>:
    pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
    borrowed(spec, pair)

def initialized(+spec: R.Record<V.Value>, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}: active(spec, runtime)

def configuredWith(+spec: R.Record<V.Value>, +options: R.Record<V.Value>) -> IO(Unit):
  do IO<Unit>:
    config : Bedrock.ClientConfig <- Bedrock.clientConfig(modelOf(spec), urlContext(), text(get(options, "profile")), text(get(options, "region")), text(get(options, "bearerToken")), text(get(options, "apiKey")), envOf(get(options, "env")))
    IO.print("config " ++ jsonText(configJson(config)))

# The client configuration for the case's model and options.
def configured(+spec: R.Record<V.Value>) -> IO(Unit): configuredWith(spec, fieldsOf(get(spec, "options")))

def runMode(+spec: R.Record<V.Value>, kind: String) -> IO(Unit):
  match kind:
    case "config": configured(spec)
    case _:
      do IO<Unit>:
        runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), networkOptions())
        initialized(spec, runtime)

def run(+spec: R.Record<V.Value>) -> IO(Unit): runMode(spec, mode(spec))

def parsed(result: Result<&2, &2, Decode.ParseError, V.Value>) -> IO(Unit):
  match result:
    case Done{V.ObjectValue{spec}}: run(spec)
    case _: IO.die(Unit, 1, "invalid case JSON")

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case spec <> Nil{}: parsed(Decode.parse(spec))
    case _: IO.die(Unit, 1, "usage: bedrock '<case JSON>'")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

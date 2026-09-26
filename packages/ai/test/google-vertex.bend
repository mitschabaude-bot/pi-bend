import Base
import ../src/api/google-vertex.bend as Vertex
import ../src/api/google-vertex-credentials.bend as Credentials
import ../src/api/google-generative-ai.bend as Google
import ../src/api/google-shared.bend as Shared
import ../src/providers/google-vertex.models.bend as Catalog
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
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../../runtime/src/unicode-17-idna-properties.bend as Properties
import ../../runtime/src/unicode-17-normalization.bend as Normalization
import ../../runtime/src/url.bend as URL
import ../../runtime/src/pi-user-agent.bend as Agent

# The Google Vertex suites against a loopback server run by
# tests/google_vertex_check.py: `google-vertex '<case JSON>'` runs one case
# (catalog model and overrides, transcript, options, stream or streamSimple,
# a pre-aborted signal, the token endpoint) and prints the client
# configuration, the payload onPayload saw, the onResponse value, every event
# and the final message as JSON lines. The checker compares traces with
# upstream google-vertex.ts driving the pinned @google/genai SDK.

def J() -> Data: T.JsonValue

def Error() -> Data: String

def Stream() -> Data: Events.AssistantMessageEventStream(V.Value, J())

def Options() -> Data: Vertex.Options(Unit, Unit, Error())

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

def levelName(+name: String) -> Maybe<&2, T.ModelThinkingLevel>:
  match name:
    case "off": Some{T.Off{}}
    case "minimal": Some{T.Thinking{T.Minimal{}}}
    case "low": Some{T.Thinking{T.Low{}}}
    case "medium": Some{T.Thinking{T.Medium{}}}
    case "high": Some{T.Thinking{T.High{}}}
    case "xhigh": Some{T.Thinking{T.XHigh{}}}
    case "max": Some{T.Thinking{T.Max{}}}
    case _: None{}

def mapped(name: Maybe<&2, T.ModelThinkingLevel>, value: V.Value, rest: List<&2, T.ThinkingLevelMapping>) -> List<&2, T.ThinkingLevelMapping>:
  match name value:
    case Some{selected} V.Text{text}: T.ThinkingLevelMapping{selected, Some{T.PresentValue{text}}} <> rest
    case Some{selected} _: T.ThinkingLevelMapping{selected, Some{T.NullValue{}}} <> rest
    case None{} _: rest

def mappings(values: List<&2, R.Property<V.Value>>) -> List<&2, T.ThinkingLevelMapping>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: mapped(levelName(name), value, mappings(rest))

def levelMap(value: Maybe<&2, V.Value>, previous: Maybe<&2, T.ThinkingLevelMap>) -> Maybe<&2, T.ThinkingLevelMap>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{T.ThinkingLevelMap{mappings(values)}}
    case _: previous

def overridden(+fields: R.Record<V.Value>, model: T.Model<J()>) -> T.Model<J()>:
  match model:
    case T.Model{id, name, api, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}:
      T.Model{Maybe.default(&2, String, text(get(fields, "id")), id), Maybe.default(&2, String, text(get(fields, "name")), name), api, Maybe.default(&2, String, text(get(fields, "provider")), provider), Maybe.default(&2, String, text(get(fields, "baseUrl")), base), Maybe.default(&2, Bool, flag(get(fields, "reasoning")), reasoning), levelMap(get(fields, "thinkingLevelMap"), levels), Bool.pick(List<&2, T.ModelInput>, Maybe.is_some(&2, V.Value, get(fields, "input")), inputs(itemsOf(get(fields, "input"))), input), limits, cost, cache, Maybe.default(&2, F64, number(get(fields, "contextWindow")), window), Maybe.default(&2, F64, number(get(fields, "maxTokens")), maximum), sampling, Bool.pick(Maybe<&2, R.Record<String>>, Maybe.is_some(&2, V.Value, get(fields, "headers")), recordOf(get(fields, "headers")), headers), compat}

def modelOf(+spec: R.Record<V.Value>) -> T.Model<J()>:
  overridden(fieldsOf(get(spec, "model")), Maybe.default(&2, T.Model<J()>, catalogModel(Catalog.GOOGLE_VERTEX_MODELS(), Maybe.default(&2, String, text(get(fieldsOf(get(spec, "model")), "catalog")), "")), Catalog.model_gemini_3_flash_preview()))

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

# With `throwPayload` the hook throws "payload captured" as the upstream
# thinking-level suite's does.
def capture(throws: Bool, input: T.PayloadInput<J(), T.Model<J()>>) -> IO(Result<&2, &2, Error(), Maybe<&2, J()>>):
  match input:
    case T.PayloadInput{payload, _}:
      do IO<Result<&2, &2, Error(), Maybe<&2, J()>>>:
        IO.print("payload " ++ jsonText(payload))
        return Bool.pick(Result<&2, &2, Error(), Maybe<&2, J()>>, throws, Fail{"payload captured"}, Done{None{}})

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
  T.StreamOptions{signal, None{}, text(get(options, "apiKey")), None{}, envOf(get(options, "env")), onPayload, onResponse, headersOf(get(options, "headers")), None{}, number(get(options, "maxRetries")), None{}, number(get(options, "temperature")), None{}, number(get(options, "maxTokens")), None{}, None{}, None{}, None{}, None{}}

def googleLevel(value: Maybe<&2, String>) -> Maybe<&2, Shared.GoogleApiThinkingLevel>:
  match value:
    case Some{"THINKING_LEVEL_UNSPECIFIED"}: Some{Shared.ThinkingLevelUnspecified{}}
    case Some{"MINIMAL"}: Some{Shared.MinimalLevel{}}
    case Some{"LOW"}: Some{Shared.LowLevel{}}
    case Some{"MEDIUM"}: Some{Shared.MediumLevel{}}
    case Some{"HIGH"}: Some{Shared.HighLevel{}}
    case _: None{}

def thinkingOf(value: Maybe<&2, V.Value>) -> Maybe<&2, Google.GoogleThinking>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{Google.GoogleThinking{Maybe.default(&2, Bool, flag(get(fields, "enabled")), False{}), number(get(fields, "budgetTokens")), googleLevel(text(get(fields, "level")))}}
    case _: None{}

def streamOptions(+options: R.Record<V.Value>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, Error())>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, Error())>) -> Options():
  Vertex.GoogleVertexOptions{Google.GoogleOptions{baseOptions(options, signal, onPayload, onResponse), text(get(options, "toolChoice")), thinkingOf(get(options, "thinking"))}, text(get(options, "project")), text(get(options, "location"))}

def simpleChoice(value: Maybe<&2, String>) -> Maybe<&2, T.ToolChoice>:
  match value:
    case Some{"auto"}: Some{T.AutoTool{}}
    case Some{"none"}: Some{T.NoTool{}}
    case _: None{}

def simpleOptions(+options: R.Record<V.Value>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, Error())>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, Error())>) -> Simple():
  T.SimpleStreamOptions{signal, None{}, text(get(options, "apiKey")), None{}, envOf(get(options, "env")), onPayload, onResponse, headersOf(get(options, "headers")), None{}, number(get(options, "maxRetries")), None{}, number(get(options, "temperature")), None{}, number(get(options, "maxTokens")), None{}, None{}, None{}, None{}, None{}, simpleChoice(text(get(options, "toolChoice"))), level(text(get(options, "reasoning"))), None{}, budgets(get(options, "thinkingBudgets"))}

# Reporting
# ---------

def optionalProperty(name: String, value: Maybe<&2, J()>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match value:
    case None{}: rest
    case Some{item}: R.Property{name, item} <> rest

def str(value: String) -> J(): T.JsonString{value}

def recordJson(entries: List<&2, R.Property<String>>) -> J(): T.JsonObject{R.Record{headerFields(entries)}}

def httpJson(value: Vertex.HttpOptions) -> J():
  match value:
    case Vertex.HttpOptions{base, collection, version, headers}:
      T.JsonObject{R.Record{optionalProperty("baseUrl", Maybe.map(&2, String, J(), str, base), optionalProperty("baseUrlResourceScope", Bool.pick(Maybe<&2, J()>, collection, Some{str("COLLECTION")}, None{}), optionalProperty("apiVersion", Maybe.map(&2, String, J(), str, version), optionalProperty("headers", Maybe.map(&2, R.Record<String>, J(), record => recordJson(R.entries(String, record)), headers), Nil{}))))}}

# The GoogleGenAI constructor options upstream passes, in its member names.
def configJson(config: Vertex.ClientConfig) -> J():
  match config:
    case Vertex.ApiKeyClient{key, version, http}: T.JsonObject{R.Record{R.Property{"vertexai", T.JsonBoolean{True{}}} <> R.Property{"apiKey", str(key)} <> R.Property{"apiVersion", str(version)} <> optionalProperty("httpOptions", Maybe.map(&2, Vertex.HttpOptions, J(), httpJson, http), Nil{})}}
    case Vertex.AdcClient{project, location, file, version, http}: T.JsonObject{R.Record{R.Property{"vertexai", T.JsonBoolean{True{}}} <> R.Property{"project", str(project)} <> R.Property{"location", str(location)} <> R.Property{"apiVersion", str(version)} <> optionalProperty("googleAuthOptions", Maybe.map(&2, String, J(), name => T.JsonObject{R.Record{[R.Property{"keyFilename", str(name)}]}}, file), optionalProperty("httpOptions", Maybe.map(&2, Vertex.HttpOptions, J(), httpJson, http), Nil{}))}}

def configResult(value: Result<&2, &2, String, Vertex.ClientConfig>) -> String:
  match value:
    case Fail{message}: "thrown " ++ message
    case Done{config}: "config " ++ jsonText(configJson(config))

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

def thrownLine(result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("thrown " ++ message)
    case Done{_}: IO.pure(Unit, Unit{})

def agentText(value: Result<&1, &1, U32 & String, String>) -> String:
  match value:
    case Done{text}: text
    case Fail{_}: "pi"

def setupOf(agent: String, fetch: Fetch.Fetch(Unit), +spec: R.Record<V.Value>) -> Vertex.Setup<Unit>:
  Vertex.Setup{urlContext(), agent, fetch, Maybe.default(&2, String, text(get(spec, "tokenUrl")), Credentials.TOKEN_URL())}

def streamedIn(agent: String, fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +events: Stream(), +spec: R.Record<V.Value>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, Error())>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, Error())>, kind: String, +options: R.Record<V.Value>, requestSignal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Unit):
  match kind:
    case "simple":
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Vertex.streamSimple(~Unit, ~Unit, ~Error(), ~J(), ~J(), ~render, events, signal, setupOf(agent, fetch, spec), modelOf(spec), contextOf(spec), Some{simpleOptions(options, requestSignal, onPayload, onResponse)}, F.fromU32(1))
        thrownLine(result)
    case _: Vertex.stream(~Unit, ~Unit, ~Error(), ~J(), ~J(), ~render, events, signal, setupOf(agent, fetch, spec), modelOf(spec), contextOf(spec), streamOptions(options, requestSignal, onPayload, onResponse), F.fromU32(1))

def streamed(agent: String, fetch: Fetch.Fetch(Unit), +signal: Abort.AbortSignal<Unit>, +events: Stream(), +spec: R.Record<V.Value>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, Error())>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, Error())>) -> IO(Unit):
  streamedIn(agent, fetch, signal, events, spec, onPayload, onResponse, mode(spec), fieldsOf(get(spec, "options")), Bool.pick(Maybe<&2, Abort.AbortSignal<Unit>>, Maybe.default(&2, Bool, flag(get(spec, "abort")), False{}), Some{signal}, None{}))

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
        +payloadHook : T.PayloadCallback(J(), T.Model<J()>, Error()) <- C.create(~Bool, ~T.PayloadInput<J(), T.Model<J()>>, ~Result<&2, &2, Error(), Maybe<&2, J()>>, ~capture, Maybe.default(&2, Bool, flag(get(spec, "throwPayload")), False{}))
        +responseHook : T.ResponseCallback(T.Model<J()>, Error()) <- C.create(~Unit, ~T.ResponseInput<T.Model<J()>>, ~Result<&2, &2, Error(), Unit>, ~observe, Unit{})
        agentResult : Result<&1, &1, U32 & String, String> <- Agent.get()
        streamed(agentText(agentResult), fetch, Abort.signal(Unit, controller), events, spec, hookWhen(T.PayloadCallback(J(), T.Model<J()>, Error()), flag(get(spec, "capture")), payloadHook), hookWhen(T.ResponseCallback(T.Model<J()>, Error()), flag(get(spec, "observe")), responseHook))
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
    config : Result<&2, &2, String, Vertex.ClientConfig> <- Vertex.clientConfig("pi-bend-test", modelOf(spec), text(get(options, "apiKey")), text(get(options, "project")), text(get(options, "location")), headersOf(get(options, "headers")), envOf(get(options, "env")))
    IO.print(configResult(config))

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
    case _: IO.die(Unit, 1, "usage: google-vertex '<case JSON>'")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

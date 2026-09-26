import Base
import ../src/api/anthropic-messages.bend as Messages
import ../src/api/anthropic-messages-client.bend as Client
import ../src/api/anthropic-messages-stream.bend as Fold
import ../src/api/openai-client.bend as SDK
import ../src/types.bend as T
import ../src/utils/event-stream.bend as Events
import ../src/utils/diagnostics.bend as Diagnostics
import ../src/utils/json.bend as Wire
import ../src/utils/transcript.bend as Transcript
import ./anthropic-messages-client.bend as Network
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-message.bend as H
import ../../runtime/src/json.bend as Parse
import ../../runtime/src/record.bend as R
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/pi-user-agent.bend as UserAgent
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/sse.bend as Body
import ../src/utils/schema-json.bend as SchemaJson
import ../../runtime/src/utf8.bend as UTF8

# Native stand-ins for the upstream suites' seams. Upstream captures the
# params in `onPayload` (throwing to stop), injects `options.client` with a
# fixed SSE body, or mocks the SDK/fetch to observe the request. Here one run
# goes through the real `stream` lifecycle with: a payload hook that records
# and fails, an injected client whose body yields the given chunks, and a
# fetch that records the exact wire request and then fails.
def J() -> Data: T.JsonValue

def Error() -> Data: String

def Options() -> Data: Client.Options(Unit, Unit, String)

def Simple() -> Data: T.SimpleStreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String>

def Diagnostics() -> Data: List<&2, Fold.InputTransformation>

def Message() -> Data: T.AssistantMessage<V.Value, Diagnostics()>

def Context() -> Data: T.TranscriptContext<V.Value, V.Value, Diagnostics(), Unit>

type Mode is Data:
  Capture{}
  Respond{chunks: List<&2, String>}
  Replace{chunks: List<&2, String>}
  Send{}

def Event() -> Data: T.AssistantMessageEvent<V.Value, Diagnostics()>

type Outcome is Data:
  Outcome{message: Message(), payload: Maybe<&2, J()>, sent: Maybe<&2, J()>, request: Maybe<&2, Fetch.Input<Unit>>, events: List<&2, Event()>}

# Content
# -------
def textOf(value: String) -> V.Value: V.Text{value}

def user(content: String, timestamp: U32) -> T.Message<V.Value, V.Value, Diagnostics(), Unit>: T.User{T.UserMessage{T.UserText{content}, F.fromU32(timestamp)}}

def zero() -> F64: F.fromU32(0)

def usage() -> T.Usage: T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}

def context(messages: List<&2, T.Message<V.Value, V.Value, Diagnostics(), Unit>>) -> Context():
  Transcript.normalizeContext(V.Value, V.Value, Diagnostics(), Unit, T.Context{None{}, messages, None{}})

def contextWith(systemPrompt: Maybe<&2, String>, messages: List<&2, T.Message<V.Value, V.Value, Diagnostics(), Unit>>, tools: Maybe<&2, List<&2, T.Tool<V.Value>>>) -> Context():
  Transcript.normalizeContext(V.Value, V.Value, Diagnostics(), Unit, T.Context{systemPrompt, messages, tools})

def hello() -> Context(): context(user("Hello", 1) <> Nil{})

def withBase(model: T.Model<J()>, base: String) -> T.Model<J()>:
  match model:
    case T.Model{id, name, api, provider, _, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}:
      T.Model{id, name, api, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}

def withCompat(model: T.Model<J()>, compat: T.AnthropicMessagesCompat) -> T.Model<J()>:
  match model:
    case T.Model{id, name, _, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, _}:
      T.Model{id, name, T.AnthropicMessagesApi{}, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, Some{compat}}

def noCompat() -> T.AnthropicMessagesCompat:
  T.AnthropicMessagesCompat{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def zeroCost() -> T.ModelCost: T.ModelCost{zero(), zero(), zero(), zero(), None{}}

# A custom Anthropic Messages model like the suites' makeCustomModel.
def custom(id: String, name: String, provider: String, base: String, maxTokens: U32, window: U32, levels: Maybe<&2, T.ThinkingLevelMap>, compat: Maybe<&2, T.AnthropicMessagesCompat>) -> T.Model<J()>:
  T.Model{id, name, T.AnthropicMessagesApi{}, provider, base, True{}, levels, T.InputText{} <> Nil{}, None{}, zeroCost(), None{}, F.fromU32(window), F.fromU32(maxTokens), None{}, None{}, compat}

# Options
# -------
def emptySimple() -> Simple(): T.emptySimpleStreamOptions(J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String)

def simple(apiKey: Maybe<&2, String>, temperature: Maybe<&2, F64>, reasoning: Maybe<&2, T.ThinkingLevel>) -> Simple():
  T.SimpleStreamOptions{None{}, None{}, apiKey, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, temperature, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, reasoning, None{}, None{}}

def fromSimple(+model: T.Model<J()>, +context: Context(), options: Simple()) -> Result<&2, &2, String, Options()>:
  Messages.streamSimpleOptions(~Diagnostics(), ~Unit, ~Abort.AbortSignal<Unit>, ~Unit, ~Fetch.Fetch(Unit), ~String, ~Client.AnthropicClient(), model, context, Some{options})

def streamOptions(apiKey: Maybe<&2, String>, retention: Maybe<&2, T.CacheRetention>, headers: Maybe<&2, T.ProviderHeaders()>) -> T.StreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String>:
  T.StreamOptions{None{}, None{}, apiKey, None{}, None{}, None{}, None{}, headers, None{}, None{}, None{}, None{}, None{}, None{}, None{}, retention, None{}, None{}, None{}}

# Seams
# -----
def capturePayload(reference: Ref.Ref<Maybe<&2, J()>>, input: T.PayloadInput<J(), T.Model<J()>>) -> IO(Result<&2, &2, String, Maybe<&2, J()>>):
  match input:
    case T.PayloadInput{payload, _}:
      do IO<Result<&2, &2, String, Maybe<&2, J()>>>:
        Ref.write(Maybe<&2, J()>, reference, Some{payload})
        return Fail{"payload captured"}

# An onPayload replacement: a non-streaming copy of the params.
def replacePayload(unused: Unit, input: T.PayloadInput<J(), T.Model<J()>>) -> IO(Result<&2, &2, String, Maybe<&2, J()>>):
  match input:
    case T.PayloadInput{T.JsonObject{fields}, _}: IO.pure(Result<&2, &2, String, Maybe<&2, J()>>, Done{Some{T.JsonObject{R.set(J(), fields, "stream", T.JsonBoolean{False{}})}}})
    case T.PayloadInput{other, _}: IO.pure(Result<&2, &2, String, Maybe<&2, J()>>, Done{Some{other}})

def utf8(value: String) -> List<&2, U32>: UTF8.encode(value)

def popChunk(chunks: List<&2, String>) -> List<&2, String> & Result<&2, &2, String, Maybe<&2, Body.Chunk>>:
  match chunks:
    case Nil{}: (Nil{}, Done{None{}})
    case chunk <> rest: (rest, Done{Some{Body.Bytes{utf8(chunk)}}})

def nextChunk(reference: Ref.Ref<List<&2, String>>, unused: Unit) -> IO(Result<&2, &2, String, Maybe<&2, Body.Chunk>>):
  Ref.modify(List<&2, String>, Result<&2, &2, String, Maybe<&2, Body.Chunk>>, reference, popChunk)

def closeChunks(unused: Unit, input: Unit) -> IO(Result<&2, &2, String, Unit>): IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})

type Injected is Data:
  Injected{sent: Ref.Ref<Maybe<&2, J()>>, chunks: Ref.Ref<List<&2, String>>}

def respond(environment: Injected, params: J()) -> IO(Result<&2, &2, String, Client.ClientResponse>):
  match environment:
    case Injected{sent, chunks}:
      do IO<Result<&2, &2, String, Client.ClientResponse>>:
        Ref.write(Maybe<&2, J()>, sent, Some{params})
        +next : C.Callback<Unit, Result<&2, &2, String, Maybe<&2, Body.Chunk>>> <- C.create(~Ref.Ref<List<&2, String>>, ~Unit, ~Result<&2, &2, String, Maybe<&2, Body.Chunk>>, ~nextChunk, chunks)
        +close : C.Callback<Unit, Result<&2, &2, String, Unit>> <- C.create(~Unit, ~Unit, ~Result<&2, &2, String, Unit>, ~closeChunks, Unit{})
        return Done{Client.ClientResponse{F.fromU32(200), R.Record{R.Property{"content-type", "text/event-stream"} <> Nil{}}, Body.Source{next, close}}}

def rejected() -> Fetch.Result_(Unit): Fail{Fetch.InvalidRequest{H.BufferedRequestHeaderError{H.InvalidName{}}}}

def recordFetch(reference: Ref.Ref<Maybe<&2, Fetch.Input<Unit>>>, input: Fetch.Input<Unit>) -> IO(Fetch.Result_(Unit)):
  do IO<Fetch.Result_(Unit)>:
    Ref.write(Maybe<&2, Fetch.Input<Unit>>, reference, Some{input})
    return rejected()

def transformations(values: List<&2, Fold.InputTransformation>) -> Diagnostics(): values

def optionalHook(mode: Mode, hook: T.PayloadCallback(J(), T.Model<J()>, String), replacement: T.PayloadCallback(J(), T.Model<J()>, String)) -> Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, String)>:
  match mode:
    case Capture{}: Some{hook}
    case Replace{_}: Some{replacement}
    case _: None{}

def optionalClient(mode: Mode, client: Client.AnthropicClient()) -> Maybe<&2, Client.AnthropicClient()>:
  match mode:
    case Respond{_}: Some{client}
    case Replace{_}: Some{client}
    case _: None{}

def chunksOf(mode: Mode) -> List<&2, String>:
  match mode:
    case Respond{chunks}: chunks
    case Replace{chunks}: chunks
    case _: Nil{}

def setup(fetch: Fetch.Fetch(Unit), agent: String) -> Client.Setup<Unit>:
  Client.Setup{Network.urlContext(), SDK.Defaults{Client.sdkUserAgent(), R.new(String), None{}, None{}}, agent, fetch}

# pi's User-Agent, as the app supplies it.
def piUserAgent() -> IO(String): IO.try(String, UserAgent.get())

# Assertions
# ----------
def fail(message: String) -> IO(Unit): IO.die(Unit, 1, "FAIL " ++ message)

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: fail(message)

def showJson(value: Maybe<&2, J()>) -> String:
  match value:
    case None{}: "(none)"
    case Some{item}: Maybe.default(&2, String, Wire.stringify(item), "(unencodable)")

def parsedValue(value: Result<&2, &2, Parse.ParseError, V.Value>) -> Maybe<&2, V.Value>:
  match value:
    case Done{item}: Some{item}
    case Fail{_}: None{}

def parseText(text: Maybe<&2, String>) -> Maybe<&2, V.Value>:
  match text:
    case Some{value}: parsedValue(Parse.parse(value))
    case None{}: None{}

def asValue(value: Maybe<&2, J()>) -> Maybe<&2, V.Value>:
  match value:
    case Some{item}: parseText(Wire.stringify(item))
    case None{}: None{}

def sameValue(actual: Maybe<&2, V.Value>, want: Maybe<&2, V.Value>) -> Bool:
  match actual want:
    case None{} None{}: True{}
    case Some{left} Some{right}: V.equal(left, right)
    case _ _: False{}

# Deep JSON equality, independent of object key order (toEqual).
def equalJson(+actual: Maybe<&2, J()>, +want: String, message: String) -> IO(Unit):
  check(sameValue(asValue(actual), parsedValue(Parse.parse(want))), message ++ ": " ++ showJson(actual) ++ " != " ++ want)

def fieldOf(value: Maybe<&2, J()>, name: String) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonObject{fields}}: R.get(J(), fields, name)
    case _: None{}

def pathOf(names: List<&2, String>, value: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match names:
    case Nil{}: value
    case name <> rest: pathOf(rest, fieldOf(value, name))

def elements(value: Maybe<&2, J()>) -> List<&2, J()>:
  match value:
    case Some{T.JsonArray{values}}: values
    case _: Nil{}

def isString(value: Maybe<&2, J()>, expected: String) -> Bool:
  match value:
    case Some{T.JsonString{name}}: String.eq(name, expected)
    case _: False{}

def isRole(value: J(), role: String) -> Bool: isString(fieldOf(Some{value}, "role"), role)

def findRole(values: List<&2, J()>, +role: String) -> Maybe<&2, J()>:
  match values:
    case Nil{}: None{}
    case +value <> rest: Bool.pick(Maybe<&2, J()>, isRole(value, role), Some{value}, findRole(rest, role))

def containsString(values: List<&2, J()>, +text: String) -> Bool:
  match values:
    case Nil{}: False{}
    case T.JsonString{item} <> rest: String.eq(item, text) || containsString(rest, text)
    case _ <> rest: containsString(rest, text)

def payloadOf(outcome: Outcome) -> Maybe<&2, J()>:
  match outcome:
    case Outcome{_, payload, _, _, _}: payload

def sentOf(outcome: Outcome) -> Maybe<&2, J()>:
  match outcome:
    case Outcome{_, _, sent, _, _}: sent

def messageOf(outcome: Outcome) -> Message():
  match outcome:
    case Outcome{message, _, _, _, _}: message

def requestOf(outcome: Outcome) -> Maybe<&2, Fetch.Input<Unit>>:
  match outcome:
    case Outcome{_, _, _, request, _}: request

def foundHeader(value: Result<&2, &2, H.HeaderSyntaxError, Maybe<&2, String>>) -> Maybe<&2, String>:
  match value:
    case Done{item}: item
    case Fail{_}: None{}

def header(request: Maybe<&2, Fetch.Input<Unit>>, name: String) -> Maybe<&2, String>:
  match request:
    case Some{Fetch.Input{_, _, headers, _, _}}: foundHeader(H.get(headers, name))
    case None{}: None{}

def jsonOf(value: Maybe<&2, V.Value>) -> Maybe<&2, J()>: Maybe.map(&2, V.Value, J(), SchemaJson.toJson, value)

def requestBody(request: Maybe<&2, Fetch.Input<Unit>>) -> Maybe<&2, J()>:
  match request:
    case Some{Fetch.Input{_, _, _, H.Text{body}, _}}: jsonOf(parsedValue(Parse.parse(body)))
    case _: None{}

def showMaybe(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "(none)"
    case Some{text}: "\"" ++ text ++ "\""

def sameText(actual: Maybe<&2, String>, want: Maybe<&2, String>) -> Bool:
  match actual want:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}

def equalText(+actual: Maybe<&2, String>, +want: Maybe<&2, String>, message: String) -> IO(Unit):
  check(sameText(actual, want), message ++ ": " ++ showMaybe(actual) ++ " != " ++ showMaybe(want))

def stopName(reason: T.StopReason) -> String:
  match reason:
    case T.Pending{}: "pending"
    case T.Stop{}: "stop"
    case T.Length{}: "length"
    case T.ToolUse{}: "toolUse"
    case T.Error{}: "error"
    case T.Aborted{}: "aborted"
    case T.Deferred{}: "deferred"

def equalStop(+message: Message(), +want: String) -> IO(Unit):
  +actual = stopName(T.assistantStopReason(V.Value, Diagnostics(), message))
  check(String.eq(actual, want), "stopReason " ++ actual ++ " != " ++ want ++ " (" ++ showMaybe(T.assistantErrorMessage(V.Value, Diagnostics(), message)) ++ ")")

def pass(name: String) -> IO(Unit): IO.print("PASS " ++ name)

# Server-sent events as upstream's createSseResponse writes them.
def sse(events: List<&2, String>) -> String:
  String.join(events, "\n")

def sseEvent(name: String, data: String) -> String: "event: " ++ name ++ "\ndata: " ++ data ++ "\n"

def absent(value: Maybe<&2, T.JsonValue>, message: String) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{item}: fail(message ++ ": expected undefined, got " ++ showJson(Some{item}))

def assistant(content: List<&2, T.AssistantContent<V.Value>>, provider: String, model: String, level: Maybe<&2, String>) -> T.Message<V.Value, V.Value, Diagnostics(), Unit>:
  T.Assistant{T.AssistantMessage{content, "anthropic-messages", provider, model, None{}, None{}, level, None{}, usage(), T.Stop{}, None{}, None{}, None{}, None{}, F.fromU32(1)}}

def thinkingBlock(value: String, signature: String) -> T.AssistantContent<V.Value>: T.AssistantThinking{T.ThinkingContent{value, Some{signature}, None{}}}

# upstream `stream` options: base options plus thinkingEnabled and effort.
def direct(base: T.StreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String>, thinking: Maybe<&2, Bool>, effort: Maybe<&2, String>) -> Options():
  Messages.AnthropicOptions{base, thinking, None{}, effort, None{}, None{}, None{}, None{}}

def withInterleaved(options: Options(), value: Maybe<&2, Bool>) -> Options():
  match options:
    case Messages.AnthropicOptions{base, thinking, budget, effort, display, _, choice, client}: Messages.AnthropicOptions{base, thinking, budget, effort, display, value, choice, client}

def withHook(options: Options(), hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, String)>) -> Options():
  match options:
    case Messages.AnthropicOptions{T.StreamOptions{signal, telemetry, key, fetch, env, previous, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata}, thinking, budget, effort, display, interleaved, choice, client}:
      Messages.AnthropicOptions{T.StreamOptions{signal, telemetry, key, fetch, env, Maybe.or(&2, T.PayloadCallback(J(), T.Model<J()>, String), hook, previous), response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata}, thinking, budget, effort, display, interleaved, choice, client}

def withClient(options: Options(), client: Maybe<&2, Client.AnthropicClient()>) -> Options():
  match options:
    case Messages.AnthropicOptions{base, thinking, budget, effort, display, interleaved, choice, _}: Messages.AnthropicOptions{base, thinking, budget, effort, display, interleaved, choice, client}

# One `stream` run through the given seam; the result is the final message.
# The stream's buffered events, in order.
@unsafe def collect(next: Events.Iteration<Event()>, +cursor: Events.Iterator<Event(), Message()>, reversed: List<&2, Event()>) -> IO(List<&2, Event()>):
  match next:
    case Events.Yield{event}:
      do IO<List<&2, Event()>>:
        following : Events.Iteration<Event()> <- Events.nextValue(Event(), Message(), cursor)
        collect(following, cursor, event <> reversed)
    case Events.End{}:
      do IO<List<&2, Event()>>:
        Events.disposeIterator(Event(), Message(), cursor)
        return List.reverse(&2, Event(), reversed)

def run(+model: T.Model<J()>, +context: Context(), options: Options(), +mode: Mode) -> IO(Outcome):
  do IO<Outcome>:
    +payload : Ref.Ref<Maybe<&2, J()>> <- Ref.new(Maybe<&2, J()>, None{})
    +sent : Ref.Ref<Maybe<&2, J()>> <- Ref.new(Maybe<&2, J()>, None{})
    +chunks : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, chunksOf(mode))
    +request : Ref.Ref<Maybe<&2, Fetch.Input<Unit>>> <- Ref.new(Maybe<&2, Fetch.Input<Unit>>, None{})
    +hook : T.PayloadCallback(J(), T.Model<J()>, String) <- C.create(~Ref.Ref<Maybe<&2, J()>>, ~T.PayloadInput<J(), T.Model<J()>>, ~Result<&2, &2, String, Maybe<&2, J()>>, ~capturePayload, payload)
    +replacement : T.PayloadCallback(J(), T.Model<J()>, String) <- C.create(~Unit, ~T.PayloadInput<J(), T.Model<J()>>, ~Result<&2, &2, String, Maybe<&2, J()>>, ~replacePayload, Unit{})
    +client : Client.AnthropicClient() <- C.create(~Injected, ~J(), ~Result<&2, &2, String, Client.ClientResponse>, ~respond, Injected{sent, chunks})
    +fetch : Fetch.Fetch(Unit) <- C.create(~Ref.Ref<Maybe<&2, Fetch.Input<Unit>>>, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~recordFetch, request)
    +events : Events.AssistantMessageEventStream(V.Value, Diagnostics()) <- Events.createAssistantMessageEventStream(~V.Value, ~Diagnostics())
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    agent : String <- piUserAgent()
    Client.stream(~Unit, ~Unit, ~String, ~Diagnostics(), ~transformations, ~Unit, ~(message => message), events, Abort.signal(Unit, controller), setup(fetch, agent), model, context, withClient(withHook(options, optionalHook(mode, hook, replacement)), optionalClient(mode, client)), F.fromU32(1))
    +cursor : Events.Iterator<Event(), Message()> <- Events.iterator(Event(), Message(), events)
    first : Events.Iteration<Event()> <- Events.nextValue(Event(), Message(), cursor)
    emitted : List<&2, Event()> <- collect(first, cursor, Nil{})
    message : Message() <- Events.resultValue(T.AssistantMessageEvent<V.Value, Diagnostics()>, Message(), events)
    captured : Maybe<&2, J()> <- Ref.read(Maybe<&2, J()>, payload)
    received : Maybe<&2, J()> <- Ref.read(Maybe<&2, J()>, sent)
    recorded : Maybe<&2, Fetch.Input<Unit>> <- Ref.read(Maybe<&2, Fetch.Input<Unit>>, request)
    Abort.dispose(Unit, controller)
    return Outcome{message, captured, received, recorded, emitted}

def simpleSelected(+model: T.Model<J()>, +context: Context(), selected: Result<&2, &2, String, Options()>, +mode: Mode) -> IO(Outcome):
  match selected:
    case Fail{message}: IO.die(Outcome, 1, "streamSimple threw: " ++ message)
    case Done{options}: run(model, context, options, mode)

# A streamSimple run whose options are expected to be accepted.
def runSimple(+model: T.Model<J()>, +context: Context(), options: Simple(), +mode: Mode) -> IO(Outcome):
  simpleSelected(model, context, fromSimple(model, context, options), mode)

def textBlock(value: String) -> T.AssistantContent<V.Value>: T.AssistantText{T.TextContent{value, None{}}}

# The first message with the given role in the captured payload.
def payloadMessage(payload: Maybe<&2, J()>, role: String) -> Maybe<&2, J()>: findRole(elements(fieldOf(payload, "messages")), role)

# Message views
# -------------
def str(value: String) -> J(): T.JsonString{value}

def obj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}

def prop(name: String, value: J()) -> R.Property<J()>: R.Property{name, value}

def optionalProp(name: String, value: Maybe<&2, String>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match value:
    case None{}: rest
    case Some{text}: prop(name, str(text)) <> rest

def redactedProp(value: Maybe<&2, Bool>) -> List<&2, R.Property<J()>>:
  match value:
    case Some{flag}: prop("redacted", T.JsonBoolean{flag}) <> Nil{}
    case None{}: Nil{}

# Content blocks as upstream's objects, for toEqual comparisons.
def blockJson(block: T.AssistantContent<V.Value>) -> J():
  match block:
    case T.AssistantText{T.TextContent{value, _}}: obj(prop("type", str("text")) <> prop("text", str(value)) <> Nil{})
    case T.AssistantThinking{T.ThinkingContent{value, signature, redacted}}: obj(prop("type", str("thinking")) <> prop("thinking", str(value)) <> optionalProp("thinkingSignature", signature, redactedProp(redacted)))
    case T.AssistantToolCall{T.ToolCall{id, name, arguments, _, _}}: obj(prop("type", str("toolCall")) <> prop("id", str(id)) <> prop("name", str(name)) <> prop("arguments", SchemaJson.toJson(arguments)) <> Nil{})

def blocksJson(blocks: List<&2, T.AssistantContent<V.Value>>) -> List<&2, J()>:
  match blocks:
    case Nil{}: Nil{}
    case block <> rest: blockJson(block) <> blocksJson(rest)

def contentJson(-G: Data, message: T.AssistantMessage<V.Value, G>) -> Maybe<&2, J()>:
  Some{T.JsonArray{blocksJson(T.assistantContent(V.Value, G, message))}}

def responseModel(message: Message()) -> Maybe<&2, String>:
  match message:
    case T.AssistantMessage{_, _, _, _, value, _, _, _, _, _, _, _, _, _, _}: value

def modelOf(message: Message()) -> String: T.assistantModel(V.Value, Diagnostics(), message)

def errorMessage(message: Message()) -> Maybe<&2, String>: T.assistantErrorMessage(V.Value, Diagnostics(), message)

def rawStopReason(message: Message()) -> Maybe<&2, String>:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, _, value, _, _}: value

def providerLevel(message: Message()) -> Maybe<&2, String>:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, value, _, _, _, _, _, _, _, _}: value

def usageOf(message: Message()) -> T.Usage: T.assistantUsage(V.Value, Diagnostics(), message)

def diagnosticsOf(message: Message()) -> Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<Diagnostics()>>>:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, value, _, _, _, _, _, _, _}: value

# toBeCloseTo(want, digits): |actual - want| < 10^-digits / 2.
def near(+actual: F64, +want: F64, +tolerance: F64) -> Bool:
  +difference = F.subtract(actual, want)
  F.isGreater(F.compare(tolerance, difference)) && F.isGreater(F.compare(difference, F.negate(tolerance)))

def equalNumber(+actual: F64, +want: F64, message: String) -> IO(Unit):
  check(F.isEqual(F.compare(actual, want)), message)

def contains(+text: Maybe<&2, String>, part: String) -> Bool:
  match text:
    case Some{value}: String.contains(value, part)
    case None{}: False{}

def hasString(value: J(), name: String, expected: String) -> Bool: isString(fieldOf(Some{value}, name), expected)

def findString(values: List<&2, J()>, +name: String, +expected: String) -> Maybe<&2, J()>:
  match values:
    case Nil{}: None{}
    case +value <> rest: Bool.pick(Maybe<&2, J()>, hasString(value, name, expected), Some{value}, findString(rest, name, expected))

# A JSON-schema value written as JSON text (TypeBox's output).
def schema(text: String) -> V.Value: Maybe.default(&2, V.Value, parsedValue(Parse.parse(text)), V.Null{})

def firstElement(value: Maybe<&2, J()>) -> Maybe<&2, J()>: List.head(&2, J(), elements(value))

def headersOf(fields: List<&2, R.Property<T.Nullable<String>>>) -> T.ProviderHeaders(): R.Record{fields}

def present(name: String, value: String) -> R.Property<T.Nullable<String>>: R.Property{name, T.PresentValue{value}}

def removed(name: String) -> R.Property<T.Nullable<String>>: R.Property{name, T.NullValue{}}

def eventsOf(outcome: Outcome) -> List<&2, Event()>:
  match outcome:
    case Outcome{_, _, _, _, events}: events

def textOf2(value: Maybe<&2, J()>) -> Maybe<&2, String>:
  match value:
    case Some{T.JsonString{text}}: Some{text}
    case _: None{}

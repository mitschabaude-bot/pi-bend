import Base
import ./types.bend as AgentTypes
import ../../ai/src/types.bend as T
import ../../ai/src/api/openai-sse.bend as Sse
import ../../ai/src/api/provider-fetch.bend as Http
import ../../ai/src/utils/event-stream.bend as Events
import ../../ai/src/utils/json.bend as JsonWire
import ../../ai/src/utils/json-parse.bend as JsonRepair
import ../../ai/src/utils/message-json.bend as MessageJson
import ../../ai/src/utils/model-api.bend as ModelApi
import ../../ai/src/utils/model-json.bend as ModelJson
import ../../ai/src/utils/schema-json.bend as SchemaJson
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/date.bend as Date
import ../../runtime/src/deadline.bend as Deadline
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/text.bend as Space
import ../../runtime/src/url.bend as URL
import ../../runtime/src/utf8.bend as Utf8

# pi-mono f07218c4d packages/agent/src/proxy.ts: a stream function for apps
# that route LLM calls through a server. The server manages auth and proxies
# requests to providers; it streams ProxyAssistantMessageEvents, assistant
# message events with the `partial` field stripped, as `data: ` lines. The
# client rebuilds the partial message from them.
#
# Language-driven changes:
# - The caller supplies the fetch (upstream globalThis.fetch) and the URL
#   parsing context; ProxyStreamOptions carries the caller's
#   SimpleStreamOptions whole (upstream picks eleven members of it and adds
#   signal, authToken and proxyUrl), of which the same members are sent.
# - Partials are immutable snapshots (docs/scope-decisions.md); the tool call's
#   accumulating `partialJson` is kept beside the message per content index,
#   and `partial.content[index] = block` past the end appends.
# - Decoding is typed: an event whose required members are missing or of the
#   wrong type fails the stream like a JSON.parse failure, and messages of
#   JSON syntax errors are the port's own (engines word them differently).
# - Reading stops at the terminal event; upstream keeps reading to the end of
#   the body, but its event stream ignores everything after a terminal event.

def J() -> Data: T.JsonValue
def Message(-G: Data) -> Data: T.AssistantMessage<V.Value, G>
def Event(-G: Data) -> Data: T.AssistantMessageEvent<V.Value, G>
def Content() -> Data: T.AssistantContent<V.Value>
def EventStream(-G: Data) -> Data: Events.AssistantMessageEventStream(V.Value, G)

# Proxy event types: what the server sends, with `partial` stripped.
type ProxyAssistantMessageEvent is Data:
  ProxyStart{}
  ProxyTextStart{contentIndex: F64}
  ProxyTextDelta{contentIndex: F64, delta: String}
  ProxyTextEnd{contentIndex: F64, contentSignature: Maybe<&2, String>}
  ProxyThinkingStart{contentIndex: F64}
  ProxyThinkingDelta{contentIndex: F64, delta: String}
  ProxyThinkingEnd{contentIndex: F64, contentSignature: Maybe<&2, String>}
  ProxyToolcallStart{contentIndex: F64, id: String, toolName: String}
  ProxyToolcallDelta{contentIndex: F64, delta: String}
  ProxyToolcallEnd{contentIndex: F64, toolCall: T.ToolCall<V.Value>}
  ProxyDone{reason: T.DoneReason, usage: T.Usage, providerThinkingLevel: Maybe<&2, String>}
  ProxyError{reason: T.ErrorReason, errorMessage: Maybe<&2, String>, usage: T.Usage, providerThinkingLevel: Maybe<&2, String>}

# upstream ProxyStreamOptions. `options.signal` is the local abort signal for
# the proxy request.
type ProxyStreamOptions<-Reason: Data, -Telemetry: Data, -Error: Data> is Data:
  ProxyStreamOptions{options: T.SimpleStreamOptions<J(), Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), Error>, authToken: String, proxyUrl: String}

# Request
# -------
def optionalField(key: String, value: Maybe<&2, V.Value>, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  MessageJson.optional(key, value, rest)

def levelName(level: T.ThinkingLevel) -> String:
  match level:
    case T.Minimal{}: "minimal"
    case T.Low{}: "low"
    case T.Medium{}: "medium"
    case T.High{}: "high"
    case T.XHigh{}: "xhigh"
    case T.Max{}: "max"

def retentionName(value: T.CacheRetention) -> String:
  match value:
    case T.CacheNone{}: "none"
    case T.CacheShort{}: "short"
    case T.CacheLong{}: "long"

def transportName(value: T.Transport) -> String:
  match value:
    case T.Sse{}: "sse"
    case T.WebSocket{}: "websocket"
    case T.WebSocketCached{}: "websocket-cached"
    case T.AutoTransport{}: "auto"

def jsonRecord(record: R.Record<J()>) -> V.Value: MessageJson.jsonValue(T.JsonObject{record})

def headerValue(value: T.Nullable<String>) -> V.Value:
  match value:
    case T.NullValue{}: V.Null{}
    case T.PresentValue{text}: V.Text{text}

def headerEntries(entries: List<&2, R.Property<T.Nullable<String>>>) -> List<&2, R.Property<V.Value>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, headerValue(value)} <> headerEntries(rest)

def headersValue(headers: T.ProviderHeaders()) -> V.Value:
  match headers:
    case R.Record{entries}: MessageJson.object(headerEntries(entries))

def budgetsValue(budgets: T.ThinkingBudgets) -> V.Value:
  match budgets:
    case T.ThinkingBudgets{minimal, low, medium, high}:
      MessageJson.object(MessageJson.optionalNumber("minimal", minimal, MessageJson.optionalNumber("low", low, MessageJson.optionalNumber("medium", medium, MessageJson.optionalNumber("high", high, Nil{})))))

def text(value: String) -> V.Value: V.Text{value}

# upstream buildProxyRequestOptions, as JSON.stringify writes it: absent
# members are omitted.
def buildProxyRequestOptions(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>) -> V.Value:
  match options:
    case T.SimpleStreamOptions{_, _, _, _, _, _, _, headers, _, _, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, _, metadata, _, reasoning, _, thinkingBudgets}:
      MessageJson.object(
        MessageJson.optionalNumber("temperature", temperature,
        optionalField("samplingParams", Maybe.map(&2, R.Record<J()>, V.Value, jsonRecord, samplingParams),
        MessageJson.optionalNumber("maxTokens", maxTokens,
        optionalField("reasoning", Maybe.map(&2, T.ThinkingLevel, V.Value, level => text(levelName(level)), reasoning),
        optionalField("cacheRetention", Maybe.map(&2, T.CacheRetention, V.Value, value => text(retentionName(value)), cacheRetention),
        MessageJson.optionalText("sessionId", sessionId,
        optionalField("headers", Maybe.map(&2, T.ProviderHeaders(), V.Value, headersValue, headers),
        optionalField("metadata", Maybe.map(&2, R.Record<J()>, V.Value, jsonRecord, metadata),
        optionalField("transport", Maybe.map(&2, T.Transport, V.Value, value => text(transportName(value)), transport),
        optionalField("thinkingBudgets", Maybe.map(&2, T.ThinkingBudgets, V.Value, budgetsValue, thinkingBudgets),
        MessageJson.optionalNumber("maxRetryDelayMs", maxRetryDelayMs, Nil{}))))))))))))

def messageValues(~G: Data, ~D: Data, ~diagnosticDetails: G -> V.Value, ~toolDetails: D -> V.Value, messages: List<&2, T.Message<V.Value, V.Value, G, D>>) -> List<&2, V.Value>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest:
      value = MessageJson.message(~G, ~D, ~diagnosticDetails, ~toolDetails, message)
      value <> messageValues(~G, ~D, ~diagnosticDetails, ~toolDetails, rest)

def contextValue(~G: Data, ~D: Data, ~diagnosticDetails: G -> V.Value, ~toolDetails: D -> V.Value, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> V.Value:
  match context:
    case T.TranscriptContext{messages}: MessageJson.object(MessageJson.field("messages", V.ArrayValue{messageValues(~G, ~D, ~diagnosticDetails, ~toolDetails, messages)}, Nil{}))

# The POST body: { model, context, options }.
def requestBody(~G: Data, ~D: Data, ~diagnosticDetails: G -> V.Value, ~toolDetails: D -> V.Value, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>) -> Maybe<&2, String>:
  JsonWire.stringify(SchemaJson.toJson(MessageJson.object(MessageJson.field("model", ModelJson.model(model), MessageJson.field("context", contextValue(~G, ~D, ~diagnosticDetails, ~toolDetails, context), MessageJson.field("options", buildProxyRequestOptions(Signal, Telemetry, Fetch, Error, options), Nil{}))))))

def requestHeaders(token: String) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  Http.headerList(R.Property{"Authorization", "Bearer " ++ token} <> R.Property{"Content-Type", "application/json"} <> Nil{})

# The partial message
# -------------------
def zero() -> F64: F.fromU32(0)

def emptyUsage() -> T.Usage: T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}

def initialPartial(-G: Data, model: T.Model<J()>, timestamp: F64) -> Message(G):
  match model:
    case T.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _, _, _}: T.AssistantMessage{Nil{}, ModelApi.name(api), provider, id, None{}, None{}, None{}, None{}, emptyUsage(), T.Pending{}, None{}, None{}, None{}, None{}, timestamp}

def contentOf(-G: Data, message: Message(G)) -> List<&2, Content()>: T.assistantContent(V.Value, G, message)

def withContent(-G: Data, message: Message(G), content: List<&2, Content()>) -> Message(G):
  match message:
    case T.AssistantMessage{_, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def chosenLevel(incoming: Maybe<&2, String>, current: Maybe<&2, String>) -> Maybe<&2, String>:
  match incoming:
    case Some{level}: Some{level}
    case None{}: current

# The terminal members: stopReason and usage, the error message of an error
# event, and providerThinkingLevel when the event carries one.
def withTerminal(-G: Data, message: Message(G), +stop: T.StopReason, errorMessage: Maybe<&2, Maybe<&2, String>>, usage: T.Usage, incoming: Maybe<&2, String>) -> Message(G):
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, _, _, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, chosenLevel(incoming, level), diagnostics, usage, stop, deferred, Maybe.default(&2, Maybe<&2, String>, errorMessage, error), raw, endTurn, timestamp}

def failedWith(-G: Data, message: Message(G), +stop: T.StopReason, errorMessage: String) -> Message(G):
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, _, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, Some{errorMessage}, raw, endTurn, timestamp}

def natural(value: Result<&2, &2, F.Error, Nat>) -> Nat:
  match value:
    case Done{number}: number
    case Fail{_}: 0n

def indexOf(value: F64) -> Nat: natural(F.convert(F.truncate(value)))

def placed(content: List<&2, Content()>, +index: Nat, block: Content()) -> List<&2, Content()>:
  match content index:
    case Nil{} _: block <> Nil{}
    case _ <> rest 0n: block <> rest
    case head <> rest 1n+previous: head <> placed(rest, previous, block)

def blockAt(content: List<&2, Content()>, +index: Nat) -> Maybe<&2, Content()>:
  match content index:
    case Nil{} _: None{}
    case head <> _ 0n: Some{head}
    case _ <> rest 1n+previous: blockAt(rest, previous)

# Tool-call argument JSON accumulated per content index (upstream's
# `partialJson` member, deleted at toolcall_end).
type ToolJson is Data:
  ToolJson{index: Nat, json: String}

def jsonAt(entries: List<&2, ToolJson>, +index: Nat) -> String:
  match entries:
    case Nil{}: ""
    case ToolJson{+at, +json} <> rest: Bool.pick(String, Nat.is_eq(at, index), json, jsonAt(rest, index))

def withoutJson(entries: List<&2, ToolJson>, +index: Nat) -> List<&2, ToolJson>:
  match entries:
    case Nil{}: Nil{}
    case ToolJson{+at, json} <> rest:
      +tail = withoutJson(rest, index)
      Bool.pick(List<&2, ToolJson>, Nat.is_eq(at, index), tail, ToolJson{at, json} <> tail)

def withJson(entries: List<&2, ToolJson>, +index: Nat, json: String) -> List<&2, ToolJson>:
  ToolJson{index, json} <> withoutJson(entries, index)

# Rebuilding events
# -----------------
type Reading<-G: Data> is Data:
  Reading{decoder: Utf8.Decoder, buffer: String, partial: Message(G), toolJson: List<&2, ToolJson>}

def partialOf(-G: Data, reading: Reading<G>) -> Message(G):
  match reading:
    case Reading{_, _, partial, _}: partial

# One processed line: nothing to publish, an event (terminal or not), an
# unknown event type to warn about, or the error upstream throws.
type Step<-G: Data> is Data:
  Skipped{reading: Reading<G>}
  Emitted{reading: Reading<G>, event: Event(G), terminal: Bool}
  Unhandled{reading: Reading<G>, kind: String}
  Thrown{partial: Message(G), message: String}

def updated(-G: Data, reading: Reading<G>, +index: Nat, block: Content(), json: List<&2, ToolJson> -> List<&2, ToolJson>, event: Message(G) -> Event(G)) -> Step<G>:
  match reading:
    case Reading{decoder, buffer, +partial, entries}:
      +next = withContent(G, partial, placed(contentOf(G, partial), index, block))
      Emitted{Reading{decoder, buffer, next, json(entries)}, event(next), False{}}

def unchangedJson(entries: List<&2, ToolJson>) -> List<&2, ToolJson>: entries

def terminal(-G: Data, reading: Reading<G>, change: Message(G) -> Message(G), event: Message(G) -> Event(G)) -> Step<G>:
  match reading:
    case Reading{decoder, buffer, partial, entries}:
      +next = change(partial)
      Emitted{Reading{decoder, buffer, next, entries}, event(next), True{}}

def thrown(-G: Data, reading: Reading<G>, message: String) -> Step<G>: Thrown{partialOf(G, reading), message}

def textDelta(-G: Data, reading: Reading<G>, +index: F64, +delta: String, block: Maybe<&2, Content()>) -> Step<G>:
  match block:
    case Some{T.AssistantText{T.TextContent{text, signature}}}: updated(G, reading, indexOf(index), T.AssistantText{T.TextContent{text ++ delta, signature}}, unchangedJson, partial => T.TextDelta{index, delta, partial})
    case _: thrown(G, reading, "Received text_delta for non-text content")

def textEnded(-G: Data, reading: Reading<G>, +index: F64, +text: String, signature: Maybe<&2, String>) -> Step<G>:
  updated(G, reading, indexOf(index), T.AssistantText{T.TextContent{text, signature}}, unchangedJson, partial => T.TextEnd{index, text, partial})

def textEnd(-G: Data, reading: Reading<G>, +index: F64, signature: Maybe<&2, String>, block: Maybe<&2, Content()>) -> Step<G>:
  match block:
    case Some{T.AssistantText{T.TextContent{text, _}}}: textEnded(G, reading, index, text, signature)
    case _: thrown(G, reading, "Received text_end for non-text content")

def thinkingDelta(-G: Data, reading: Reading<G>, +index: F64, +delta: String, block: Maybe<&2, Content()>) -> Step<G>:
  match block:
    case Some{T.AssistantThinking{T.ThinkingContent{thinking, signature, redacted}}}: updated(G, reading, indexOf(index), T.AssistantThinking{T.ThinkingContent{thinking ++ delta, signature, redacted}}, unchangedJson, partial => T.ThinkingDelta{index, delta, partial})
    case _: thrown(G, reading, "Received thinking_delta for non-thinking content")

def thinkingEnded(-G: Data, reading: Reading<G>, +index: F64, +thinking: String, signature: Maybe<&2, String>, redacted: Maybe<&2, Bool>) -> Step<G>:
  updated(G, reading, indexOf(index), T.AssistantThinking{T.ThinkingContent{thinking, signature, redacted}}, unchangedJson, partial => T.ThinkingEnd{index, thinking, partial})

def thinkingEnd(-G: Data, reading: Reading<G>, +index: F64, signature: Maybe<&2, String>, block: Maybe<&2, Content()>) -> Step<G>:
  match block:
    case Some{T.AssistantThinking{T.ThinkingContent{thinking, _, redacted}}}: thinkingEnded(G, reading, index, thinking, signature, redacted)
    case _: thrown(G, reading, "Received thinking_end for non-thinking content")

def jsonOf(-G: Data, reading: Reading<G>, +index: Nat) -> String:
  match reading:
    case Reading{_, _, _, entries}: jsonAt(entries, index)

# `partialJson += delta; arguments = parseStreamingJson(partialJson) || {}`.
def toolcallDelta(-G: Data, reading: Reading<G>, +index: F64, +delta: String, +accumulated: String, block: Maybe<&2, Content()>) -> Step<G>:
  match block:
    case Some{T.AssistantToolCall{T.ToolCall{id, name, _, signature, namespace}}}: updated(G, reading, indexOf(index), T.AssistantToolCall{T.ToolCall{id, name, JsonRepair.parseStreamingJson(Some{accumulated}), signature, namespace}}, entries => withJson(entries, indexOf(index), accumulated), partial => T.ToolcallDelta{index, delta, partial})
    case _: thrown(G, reading, "Received toolcall_delta for non-toolCall content")

def either(incoming: Maybe<&2, String>, current: Maybe<&2, String>) -> Maybe<&2, String>:
  match incoming:
    case Some{value}: Some{value}
    case None{}: current

# `Object.assign(content, toolCall)`: the event's members replace the block's;
# an optional member the event lacks keeps the block's value.
def assigned(call: T.ToolCall<V.Value>, current: T.ToolCall<V.Value>) -> T.ToolCall<V.Value>:
  match call current:
    case T.ToolCall{id, name, arguments, signature, namespace} T.ToolCall{_, _, _, oldSignature, oldNamespace}: T.ToolCall{id, name, arguments, either(signature, oldSignature), either(namespace, oldNamespace)}

def endedCall(-G: Data, reading: Reading<G>, +index: F64, +merged: T.ToolCall<V.Value>) -> Step<G>:
  updated(G, reading, indexOf(index), T.AssistantToolCall{merged}, entries => withoutJson(entries, indexOf(index)), partial => T.ToolcallEnd{index, merged, partial})

# A toolcall_end for content that is not a tool call publishes nothing.
def toolcallEnd(-G: Data, reading: Reading<G>, +index: F64, call: T.ToolCall<V.Value>, block: Maybe<&2, Content()>) -> Step<G>:
  match block:
    case Some{T.AssistantToolCall{current}}: endedCall(G, reading, index, assigned(call, current))
    case _: Skipped{reading}

def doneStop(reason: T.DoneReason) -> T.StopReason:
  match reason:
    case T.DoneStop{}: T.Stop{}
    case T.DoneLength{}: T.Length{}
    case T.DoneToolUse{}: T.ToolUse{}
    case T.DoneDeferred{}: T.Deferred{}

def errorStop(reason: T.ErrorReason) -> T.StopReason:
  match reason:
    case T.ErrorAborted{}: T.Aborted{}
    case T.ErrorError{}: T.Error{}

def blockOf(-G: Data, reading: Reading<G>, +index: F64) -> Maybe<&2, Content()>: blockAt(contentOf(G, partialOf(G, reading)), indexOf(index))

# upstream processProxyEvent.
def processProxyEvent(-G: Data, +reading: Reading<G>, event: ProxyAssistantMessageEvent) -> Step<G>:
  match event:
    case ProxyStart{}: Emitted{reading, T.Start{partialOf(G, reading)}, False{}}
    case ProxyTextStart{+index}: updated(G, reading, indexOf(index), T.AssistantText{T.TextContent{"", None{}}}, unchangedJson, partial => T.TextStart{index, partial})
    case ProxyTextDelta{+index, delta}: textDelta(G, reading, index, delta, blockOf(G, reading, index))
    case ProxyTextEnd{+index, signature}: textEnd(G, reading, index, signature, blockOf(G, reading, index))
    case ProxyThinkingStart{+index}: updated(G, reading, indexOf(index), T.AssistantThinking{T.ThinkingContent{"", None{}, None{}}}, unchangedJson, partial => T.ThinkingStart{index, partial})
    case ProxyThinkingDelta{+index, delta}: thinkingDelta(G, reading, index, delta, blockOf(G, reading, index))
    case ProxyThinkingEnd{+index, signature}: thinkingEnd(G, reading, index, signature, blockOf(G, reading, index))
    case ProxyToolcallStart{+index, id, name}: updated(G, reading, indexOf(index), T.AssistantToolCall{T.ToolCall{id, name, V.ObjectValue{R.new(V.Value)}, None{}, None{}}}, entries => withJson(entries, indexOf(index), ""), partial => T.ToolcallStart{index, partial})
    case ProxyToolcallDelta{+index, +delta}: toolcallDelta(G, reading, index, delta, jsonOf(G, reading, indexOf(index)) ++ delta, blockOf(G, reading, index))
    case ProxyToolcallEnd{+index, call}: toolcallEnd(G, reading, index, call, blockOf(G, reading, index))
    case ProxyDone{+reason, usage, level}: terminal(G, reading, partial => withTerminal(G, partial, doneStop(reason), None{}, usage, level), message => T.StreamDone{reason, message})
    case ProxyError{+reason, error, usage, level}: terminal(G, reading, partial => withTerminal(G, partial, errorStop(reason), Some{error}, usage, level), message => T.StreamError{reason, message})

# Decoding events
# ---------------
def Decoded(-A: Data) -> Data: Result<&2, &2, Decode.Error, A>

# A decoded line: an event, or an event type processProxyEvent does not know.
type Parsed is Data:
  Known{event: ProxyAssistantMessageEvent}
  Unknown{kind: String}

def indexField(+fields: R.Record<V.Value>) -> Decoded(F64): Decode.required(F64, fields, "contentIndex", Decode.number)
def textField(+fields: R.Record<V.Value>, +key: String) -> Decoded(String): Decode.required(String, fields, key, Decode.string)
def optionalTextField(+fields: R.Record<V.Value>, +key: String) -> Decoded(Maybe<&2, String>): Decode.optional(String, fields, key, Decode.string)

def known(result: Decoded(ProxyAssistantMessageEvent)) -> Decoded(Parsed):
  Result.map(&2, &2, Decode.Error, ProxyAssistantMessageEvent, Parsed, event => Known{event}, result)

def indexed(+fields: R.Record<V.Value>, make: F64 -> ProxyAssistantMessageEvent) -> Decoded(ProxyAssistantMessageEvent):
  Result.map(&2, &2, Decode.Error, F64, ProxyAssistantMessageEvent, make, indexField(fields))

def delta(+fields: R.Record<V.Value>, make: F64 -> String -> ProxyAssistantMessageEvent) -> Decoded(ProxyAssistantMessageEvent):
  do Result<&2, &2, Decode.Error, ProxyAssistantMessageEvent>:
    at : F64 <- indexField(fields)
    value : String <- textField(fields, "delta")
    return make(at, value)

def ended(+fields: R.Record<V.Value>, make: F64 -> Maybe<&2, String> -> ProxyAssistantMessageEvent) -> Decoded(ProxyAssistantMessageEvent):
  do Result<&2, &2, Decode.Error, ProxyAssistantMessageEvent>:
    at : F64 <- indexField(fields)
    signature : Maybe<&2, String> <- optionalTextField(fields, "contentSignature")
    return make(at, signature)

def toolcallStart(+fields: R.Record<V.Value>) -> Decoded(ProxyAssistantMessageEvent):
  do Result<&2, &2, Decode.Error, ProxyAssistantMessageEvent>:
    at : F64 <- indexField(fields)
    id : String <- textField(fields, "id")
    name : String <- textField(fields, "toolName")
    return ProxyToolcallStart{at, id, name}

def toolCallValue(value: V.Value) -> Decoded(T.ToolCall<V.Value>):
  Result.bind(&2, &2, Decode.Error, R.Record<V.Value>, T.ToolCall<V.Value>, Decode.object(value), fields => MessageJson.toolCallFields(fields))

def toolcallEndEvent(+fields: R.Record<V.Value>) -> Decoded(ProxyAssistantMessageEvent):
  do Result<&2, &2, Decode.Error, ProxyAssistantMessageEvent>:
    at : F64 <- indexField(fields)
    call : T.ToolCall<V.Value> <- Decode.required(T.ToolCall<V.Value>, fields, "toolCall", toolCallValue)
    return ProxyToolcallEnd{at, call}

def doneReasonOf(+value: String) -> Decoded(T.DoneReason):
  match value:
    case "stop": Done{T.DoneStop{}}
    case "length": Done{T.DoneLength{}}
    case "toolUse": Done{T.DoneToolUse{}}
    case _: Fail{Decode.InvalidValue{Decode.Field{"reason"} <> Nil{}, "stop, length or toolUse"}}

def errorReasonOf(+value: String) -> Decoded(T.ErrorReason):
  match value:
    case "aborted": Done{T.ErrorAborted{}}
    case "error": Done{T.ErrorError{}}
    case _: Fail{Decode.InvalidValue{Decode.Field{"reason"} <> Nil{}, "aborted or error"}}

def doneEvent(+fields: R.Record<V.Value>) -> Decoded(ProxyAssistantMessageEvent):
  do Result<&2, &2, Decode.Error, ProxyAssistantMessageEvent>:
    name : String <- textField(fields, "reason")
    reason : T.DoneReason <- doneReasonOf(name)
    usage : T.Usage <- Decode.required(T.Usage, fields, "usage", MessageJson.decodeUsage)
    level : Maybe<&2, String> <- optionalTextField(fields, "providerThinkingLevel")
    return ProxyDone{reason, usage, level}

def errorEvent(+fields: R.Record<V.Value>) -> Decoded(ProxyAssistantMessageEvent):
  do Result<&2, &2, Decode.Error, ProxyAssistantMessageEvent>:
    name : String <- textField(fields, "reason")
    reason : T.ErrorReason <- errorReasonOf(name)
    message : Maybe<&2, String> <- optionalTextField(fields, "errorMessage")
    usage : T.Usage <- Decode.required(T.Usage, fields, "usage", MessageJson.decodeUsage)
    level : Maybe<&2, String> <- optionalTextField(fields, "providerThinkingLevel")
    return ProxyError{reason, message, usage, level}

def eventOf(+kind: String, +fields: R.Record<V.Value>) -> Decoded(Parsed):
  match kind:
    case "start": Done{Known{ProxyStart{}}}
    case "text_start": known(indexed(fields, at => ProxyTextStart{at}))
    case "text_delta": known(delta(fields, at => value => ProxyTextDelta{at, value}))
    case "text_end": known(ended(fields, at => signature => ProxyTextEnd{at, signature}))
    case "thinking_start": known(indexed(fields, at => ProxyThinkingStart{at}))
    case "thinking_delta": known(delta(fields, at => value => ProxyThinkingDelta{at, value}))
    case "thinking_end": known(ended(fields, at => signature => ProxyThinkingEnd{at, signature}))
    case "toolcall_start": known(toolcallStart(fields))
    case "toolcall_delta": known(delta(fields, at => value => ProxyToolcallDelta{at, value}))
    case "toolcall_end": known(toolcallEndEvent(fields))
    case "done": known(doneEvent(fields))
    case "error": known(errorEvent(fields))
    case other: Done{Unknown{other}}

def typeName(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{name}}: name
    case _: "undefined"

def typedEvent(kind: Maybe<&2, V.Value>, +fields: R.Record<V.Value>) -> Decoded(Parsed):
  match kind:
    case Some{V.Text{name}}: eventOf(name, fields)
    case other: Done{Unknown{typeName(other)}}

# `proxyEvent.type` selects the event; any other value is an unhandled type.
def decodeEvent(value: V.Value) -> Decoded(Parsed):
  match value:
    case V.ObjectValue{+fields}: typedEvent(R.get(V.Value, fields, "type"), fields)
    case _: Done{Unknown{"undefined"}}

# Reading the stream
# ------------------
def lineData(+line: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, String.starts_with(line, "data: "), Some{Space.trim(String.drop(line, 6n))}, None{})

def decoded(-G: Data, +reading: Reading<G>, result: Decoded(Parsed)) -> Step<G>:
  match result:
    case Fail{_}: thrown(G, reading, "Invalid proxy event")
    case Done{Unknown{kind}}: Unhandled{reading, kind}
    case Done{Known{event}}: processProxyEvent(G, reading, event)

def parsed(-G: Data, +reading: Reading<G>, result: Result<&2, &2, Decode.ParseError, V.Value>) -> Step<G>:
  match result:
    case Fail{cause}: thrown(G, reading, "Invalid JSON in proxy event: " ++ Sse.json(cause))
    case Done{value}: decoded(G, reading, decodeEvent(value))

def processData(-G: Data, +reading: Reading<G>, data: Maybe<&2, String>) -> Step<G>:
  match data:
    case None{}: Skipped{reading}
    case Some{SNil{}}: Skipped{reading}
    case Some{text}: parsed(G, reading, Decode.parse(text))

# upstream processLine: a `data: ` line's trimmed payload, if not empty, is
# one JSON event.
def processLine(-G: Data, +reading: Reading<G>, line: String) -> Step<G>: processData(G, reading, lineData(line))

# What ended the reading.
type Ending is Data:
  Finished{}
  Failed{message: String}
  Unterminated{}

type Loop<-G: Data> is Data:
  Pull{reading: Reading<G>}
  Lines{reading: Reading<G>, lines: List<&2, String>, final: Bool}
  Stop{partial: Message(G), ending: Ending}

# `buffer.split("\n")` with the last piece kept as the new buffer.
def splitLines(text: String, current: String, lines: List<&2, String>) -> List<&2, String> & String:
  match text:
    case SNil{}: (List.reverse(&2, String, lines), String.reverse(current))
    case SCon{'\n', rest}: splitLines(rest, SNil{}, String.reverse(current) <> lines)
    case SCon{c, rest}: splitLines(rest, SCon{c, current}, lines)

def framed(-G: Data, decoder: Utf8.Decoder, partial: Message(G), entries: List<&2, ToolJson>, pair: List<&2, String> & String) -> Loop<G>:
  match pair:
    case (lines, rest): Lines{Reading{decoder, rest, partial, entries}, lines, False{}}

def appended(-G: Data, reading: Reading<G>, result: Utf8.Decoded) -> Loop<G>:
  match reading result:
    case Reading{_, buffer, partial, entries} Utf8.Decoded{decoder, text}: framed(G, decoder, partial, entries, splitLines(buffer ++ text, SNil{}, Nil{}))

# The final event may not be newline-terminated: flush the decoder and process
# whatever is left in the buffer.
def remaining(+buffer: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(buffer), Nil{}, buffer <> Nil{})

def flushed(-G: Data, reading: Reading<G>, result: Utf8.Decoded) -> Loop<G>:
  match reading result:
    case Reading{_, buffer, partial, entries} Utf8.Decoded{decoder, text}: Lines{Reading{decoder, "", partial, entries}, remaining(buffer ++ text), True{}}

def decoderOf(-G: Data, reading: Reading<G>) -> Utf8.Decoder:
  match reading:
    case Reading{decoder, _, _, _}: decoder

def bodyEnded(-G: Data, +reading: Reading<G>) -> Loop<G>: flushed(G, reading, Utf8.finish(decoderOf(G, reading)))

def chunk(-G: Data, +reading: Reading<G>, bytes: List<&2, U32>) -> Loop<G>: appended(G, reading, Utf8.decode(decoderOf(G, reading), bytes))

# A read that fails or returns after the caller aborted ends the stream with
# upstream's abort message; other read failures are the transport's.
def pulled(-Reason: Data, -G: Data, +reading: Reading<G>, result: Result<&2, &2, Http.ReadError(Reason), Maybe<&2, List<&2, U32>>>, aborted: Bool) -> Loop<G>:
  match result aborted:
    case _ True{}: Stop{partialOf(G, reading), Failed{"Request aborted by user"}}
    case Fail{_} False{}: Stop{partialOf(G, reading), Failed{"terminated"}}
    case Done{None{}} False{}: bodyEnded(G, reading)
    case Done{Some{bytes}} False{}: chunk(G, reading, bytes)

def push(-G: Data, events: EventStream(G), event: Event(G)) -> IO(Unit):
  Events.push(Event(G), Message(G), events, event)

def published(-G: Data, +events: EventStream(G), rest: List<&2, String>, +final: Bool, step: Step<G>) -> IO(Loop<G>):
  match step:
    case Skipped{reading}: IO.pure(Loop<G>, Lines{reading, rest, final})
    case Unhandled{reading, kind}:
      do IO<Loop<G>>:
        IO.print_err("Unhandled proxy event type: " ++ kind)
        return Lines{reading, rest, final}
    case Emitted{+reading, event, +closing}:
      do IO<Loop<G>>:
        push(G, events, event)
        return Bool.pick(Loop<G>, closing, Stop{partialOf(G, reading), Finished{}}, Lines{reading, rest, final})
    case Thrown{partial, message}: IO.pure(Loop<G>, Stop{partial, Failed{message}})

@unsafe def drive(~Reason: Data, ~G: Data, +events: EventStream(G), +source: Http.Source(Reason), +signal: Abort.AbortSignal<Reason>, state: Loop<G>) -> IO(Message(G) & Ending):
  match state:
    case Stop{partial, ending}: IO.pure(Message(G) & Ending, (partial, ending))
    case Pull{reading}:
      do IO<Message(G) & Ending>:
        result : Result<&2, &2, Http.ReadError(Reason), Maybe<&2, List<&2, U32>>> <- Http.read(~Reason, source)
        aborted : Bool <- Abort.aborted(Reason, signal)
        drive(~Reason, ~G, events, source, signal, pulled(Reason, G, reading, result, aborted))
    case Lines{reading, Nil{}, True{}}: drive(~Reason, ~G, events, source, signal, Stop{partialOf(G, reading), Unterminated{}})
    case Lines{reading, Nil{}, False{}}: drive(~Reason, ~G, events, source, signal, Pull{reading})
    case Lines{reading, line <> rest, final}:
      do IO<Message(G) & Ending>:
        next : Loop<G> <- published(G, events, rest, final, processLine(G, reading, line))
        drive(~Reason, ~G, events, source, signal, next)

# Failures
# --------
# upstream's catch: the partial so far ends with the error, `aborted` when the
# caller's signal is aborted.
def errorFor(-G: Data, partial: Message(G), +aborted: Bool, message: String) -> Event(G):
  +reason = Bool.pick(T.ErrorReason, aborted, T.ErrorAborted{}, T.ErrorError{})
  T.StreamError{reason, failedWith(G, partial, errorStop(reason), message)}

def failure(~Reason: Data, ~G: Data, +events: EventStream(G), +signal: Abort.AbortSignal<Reason>, partial: Message(G), message: String) -> IO(Unit):
  do IO<Unit>:
    aborted : Bool <- Abort.aborted(Reason, signal)
    push(G, events, errorFor(G, partial, aborted, message))

# A clean end of the body without a done/error event means the server dropped
# the response mid-stream.
def finish(~Reason: Data, ~G: Data, +events: EventStream(G), +signal: Abort.AbortSignal<Reason>, pair: Message(G) & Ending) -> IO(Unit):
  match pair:
    case (_, Finished{}): IO.pure(Unit, Unit{})
    case (partial, Unterminated{}): push(G, events, T.StreamError{T.ErrorError{}, failedWith(G, partial, T.Error{}, "Connection closed by proxy server before the response completed")})
    case (partial, Failed{message}): failure(~Reason, ~G, events, signal, partial, message)

# Exchange
# --------
def streamed(~Reason: Data, ~G: Data, +events: EventStream(G), +signal: Abort.AbortSignal<Reason>, partial: Message(G), pair: Http.Owner(Reason) & Http.Source(Reason)) -> IO(Unit):
  match pair:
    case (owner, source):
      do IO<Unit>:
        ending : Message(G) & Ending <- drive(~Reason, ~G, events, source, signal, Pull{Reading{Utf8.create(), "", partial, Nil{}}})
        Http.release(~Reason, owner)
        finish(~Reason, ~G, events, signal, ending)

def releasedPair(~Reason: Data, pair: Http.Owner(Reason) & Http.Source(Reason)) -> IO(Unit):
  match pair:
    case (owner, _): Http.release(~Reason, owner)

def discarded(~Reason: Data, body: Http.Body(Reason)) -> IO(Unit):
  do IO<Unit>:
    pair : Http.Owner(Reason) & Http.Source(Reason) <- Http.reader(~Reason, body)
    releasedPair(~Reason, pair)

# Upstream reads `response.body!`; a response without a body fails there.
def okResponse(~Reason: Data, ~G: Data, +events: EventStream(G), +signal: Abort.AbortSignal<Reason>, partial: Message(G), present: Bool, body: Http.Body(Reason)) -> IO(Unit):
  match present:
    case True{}:
      do IO<Unit>:
        pair : Http.Owner(Reason) & Http.Source(Reason) <- Http.reader(~Reason, body)
        streamed(~Reason, ~G, events, signal, partial, pair)
    case False{}:
      do IO<Unit>:
        discarded(~Reason, body)
        failure(~Reason, ~G, events, signal, partial, "Proxy response has no body")

def errorText(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SNil{}}}: None{}
    case Some{V.Text{text}}: Some{text}
    case _: None{}

def errorMember(result: Result<&2, &2, Decode.ParseError, V.Value>) -> Maybe<&2, String>:
  match result:
    case Done{V.ObjectValue{fields}}: errorText(R.get(V.Value, fields, "error"))
    case _: None{}

def bodyError(-Reason: Data, text: Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String>) -> Maybe<&2, String>:
  match text:
    case Done{body}: errorMember(Decode.parse(body))
    case Fail{_}: None{}

# `Proxy error: ${status} ${statusText}`, or the JSON body's `error` string.
def proxyError(-Reason: Data, +status: U32, +statusText: String, text: Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String>) -> String:
  "Proxy error: " ++ Maybe.default(&2, String, bodyError(Reason, text), U32.show(status) ++ " " ++ statusText)

def statusChecked(~Reason: Data, ~G: Data, +events: EventStream(G), +signal: Abort.AbortSignal<Reason>, partial: Message(G), +metadata: Response.Metadata, body: Http.Body(Reason), ok: Bool) -> IO(Unit):
  match ok:
    case True{}: okResponse(~Reason, ~G, events, signal, partial, Response.bodyPresent(metadata), body)
    case False{}:
      do IO<Unit>:
        text : Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String> <- Http.responseText(~Reason, 1048576n, body)
        failure(~Reason, ~G, events, signal, partial, proxyError(Reason, Response.metadataStatus(metadata), Response.statusText(metadata), text))

def checkedStatus(~Reason: Data, ~G: Data, +events: EventStream(G), +signal: Abort.AbortSignal<Reason>, partial: Message(G), +metadata: Response.Metadata, body: Http.Body(Reason)) -> IO(Unit):
  statusChecked(~Reason, ~G, events, signal, partial, metadata, body, Response.ok(metadata))

# A rejected fetch: the abort, or a network failure.
def responded(~Reason: Data, ~G: Data, +events: EventStream(G), +signal: Abort.AbortSignal<Reason>, partial: Message(G), response: Fetch.Result_(Reason)) -> IO(Unit):
  match response:
    case Fail{_}:
      do IO<Unit>:
        aborted : Bool <- Abort.aborted(Reason, signal)
        failure(~Reason, ~G, events, signal, partial, Bool.pick(String, aborted, "This operation was aborted", "fetch failed"))
    case Done{Response.Response{metadata, body}}: checkedStatus(~Reason, ~G, events, signal, partial, metadata, body)

def exchanged(~Reason: Data, ~G: Data, +events: EventStream(G), +signal: Abort.AbortSignal<Reason>, partial: Message(G), fetch: Fetch.Fetch(Reason), request: Http.Request, pair: Deadline.Scope<Reason> & Fetch.Signal(Reason)) -> IO(Unit):
  match pair:
    case (scope, requestSignal):
      do IO<Unit>:
        response : Fetch.Result_(Reason) <- Http.post(~Reason, fetch, requestSignal, request)
        responded(~Reason, ~G, events, signal, partial, response)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Unit{}

# Upstream passes only the caller's signal to fetch; the native fetch takes a
# deadline scope, which here never expires (the maximum U32 milliseconds).
def exchange(~Reason: Data, ~G: Data, +events: EventStream(G), +signal: Abort.AbortSignal<Reason>, partial: Message(G), fetch: Fetch.Fetch(Reason), request: Http.Request) -> IO(Unit):
  do IO<Unit>:
    scope : Deadline.Scope<Reason> <- Deadline.create(Reason, 4294967295, signal)
    exchanged(~Reason, ~G, events, signal, partial, fetch, request, Deadline.borrow(Reason, scope))

def prepared(~Reason: Data, ~G: Data, +events: EventStream(G), +signal: Abort.AbortSignal<Reason>, partial: Message(G), fetch: Fetch.Fetch(Reason), body: Maybe<&2, String>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, url: Result<&2, &2, URL.Error, URL.URL>) -> IO(Unit):
  match body headers url:
    case None{} _ _: failure(~Reason, ~G, events, signal, partial, "Could not serialize the proxy request")
    case _ Fail{_} _: failure(~Reason, ~G, events, signal, partial, "Invalid header value")
    case _ _ Fail{_}: failure(~Reason, ~G, events, signal, partial, "Invalid URL")
    case Some{text} Done{fields} Done{address}: exchange(~Reason, ~G, events, signal, partial, fetch, Http.Request{address, fields, text})

def produce(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~diagnosticDetails: G -> V.Value, ~toolDetails: D -> V.Value, +events: EventStream(G), fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: ProxyStreamOptions<Reason, Telemetry, E>, +signal: Abort.AbortSignal<Reason>) -> IO(Unit):
  match options:
    case ProxyStreamOptions{simple, token, proxyUrl}:
      do IO<Unit>:
        timestamp : F64 <- Date.now()
        prepared(~Reason, ~G, events, signal, initialPartial(G, model, timestamp), fetch, requestBody(~G, ~D, ~diagnosticDetails, ~toolDetails, Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), E, model, context, simple), requestHeaders(token), URL.parse(urlContext, proxyUrl ++ "/api/stream"))

# The stream
# ----------
def optionSignal(-Reason: Data, -Telemetry: Data, -E: Data, options: ProxyStreamOptions<Reason, Telemetry, E>) -> Maybe<&2, Abort.AbortSignal<Reason>>:
  match options:
    case ProxyStreamOptions{T.SimpleStreamOptions{signal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _}: signal

# Without a caller signal the request runs under a local one nobody aborts.
def signalled(~Reason: Data, run: Abort.AbortSignal<Reason> -> IO(Unit), parent: Maybe<&2, Abort.AbortSignal<Reason>>) -> IO(Unit):
  match parent:
    case Some{signal}: run(signal)
    case None{}:
      do IO<Unit>:
        +controller : Abort.AbortController<Reason> <- Abort.new(Reason)
        run(Abort.signal(Reason, controller))
        Abort.dispose(Reason, controller)

def worker(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~diagnosticDetails: G -> V.Value, ~toolDetails: D -> V.Value, +events: EventStream(G), fetch: Fetch.Fetch(Reason), urlContext: URL.Context, model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: ProxyStreamOptions<Reason, Telemetry, E>) -> IO(Unit):
  do IO<Unit>:
    signalled(~Reason, signal => produce(~Reason, ~Telemetry, ~E, ~G, ~D, ~diagnosticDetails, ~toolDetails, events, fetch, urlContext, model, context, options, signal), optionSignal(Reason, Telemetry, E, options))
    Events.end(Event(G), Message(G), events, None{})

# upstream ProxyMessageEventStream: the event stream and the task producing it.
type ProxyMessageEventStream<-G: Data> is Type:
  ProxyMessageEventStream{events: EventStream(G), task: Chan(Unit)}

# upstream streamProxy. The request runs in its own task; the returned stream
# ends with a done or error event, including when the proxy fails or drops
# the response. The caller supplies the fetch (upstream globalThis.fetch).
def streamProxy(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~diagnosticDetails: G -> V.Value, ~toolDetails: D -> V.Value, fetch: Fetch.Fetch(Reason), urlContext: URL.Context, model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: ProxyStreamOptions<Reason, Telemetry, E>) -> IO(ProxyMessageEventStream<G>):
  do IO<ProxyMessageEventStream<G>>:
    +events : EventStream(G) <- Events.createAssistantMessageEventStream(~V.Value, ~G)
    task : Chan(Unit) <- IO.fork(Unit, worker(~Reason, ~Telemetry, ~E, ~G, ~D, ~diagnosticDetails, ~toolDetails, events, fetch, urlContext, model, context, options))
    return ProxyMessageEventStream{events, task}

def borrowStream(-G: Data, owner: ProxyMessageEventStream<G>) -> ProxyMessageEventStream<G> & EventStream(G):
  match owner:
    case ProxyMessageEventStream{+events, task}: (ProxyMessageEventStream{events, task}, events)

# Waits for the request task, then disposes the event stream.
def disposeStream(-G: Data, owner: ProxyMessageEventStream<G>) -> IO(Unit):
  match owner:
    case ProxyMessageEventStream{events, task}:
      do IO<Unit>:
        done : Unit <- IO.join(Unit, task)
        Events.disposeAssistantMessageEventStream(V.Value, G, events)

def released(-E: Data, -G: Data, owner: ProxyMessageEventStream<G>) -> IO(Result<&2, &2, E, Unit>):
  do IO<Result<&2, &2, E, Unit>>:
    disposeStream(G, owner)
    return Done{Unit{}}

# The stream as an Agent streamFn result: the loop releases it after its last
# read.
def leased(-G: Data, -E: Data, pair: ProxyMessageEventStream<G> & EventStream(G)) -> AgentTypes.StreamLease<G, E>:
  match pair:
    case (kept, events): AgentTypes.StreamLease{events, released(E, G, kept)}

def streamLease(-G: Data, -E: Data, owner: ProxyMessageEventStream<G>) -> AgentTypes.StreamLease<G, E>: leased(G, E, borrowStream(G, owner))

import Base
import ../types.bend as T
import ../utils/diagnostics.bend as Diagnostics
import ../utils/message-json.bend as MessageJson
import ../utils/schema-json.bend as SchemaJson
import ../utils/json.bend as JsonWire
import ../utils/json-parse.bend as JsonRepair
import ../utils/headers.bend as HeaderUtils
import ../utils/provider-env.bend as Env
import ../utils/event-stream.bend as Events
import ../utils/model-api.bend as ModelApi
import ./provider-fetch.bend as Http
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/sse.bend as SSE
import ../../../runtime/src/utf16.bend as Utf16

# pi's own message protocol (upstream api/pi-messages.ts): one POST of
# `{ model, context, options }` to `<baseUrl>/messages`, answered by an SSE
# stream of serialized assistant-message events that ends with `done` or
# `error`. The Radius gateway speaks it; models.json custom providers can
# select it with `"api": "pi-messages"`.

def J() -> Data: T.JsonValue
def str(value: String) -> J(): T.JsonString{value}
def num(value: F64) -> J(): T.JsonNumber{value}
def obj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}
def field(name: String, value: J(), rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>: R.Property{name, value} <> rest
def optional(name: String, value: Maybe<&2, J()>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match value:
    case None{}: rest
    case Some{item}: R.Property{name, item} <> rest

# Options
# -------

# upstream PiMessagesOptions["toolChoice"].
type PiMessagesToolChoice is Data:
  ToolChoiceAuto{}
  ToolChoiceNone{}
  ToolChoiceRequired{}
  ToolChoiceFunction{name: String}

# upstream PiMessagesOptions extends StreamOptions; the shared options are one
# field.
type PiMessagesOptions<-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data> is Data:
  PiMessagesOptions{base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, reasoning: Maybe<&2, T.ThinkingLevel>, toolChoice: Maybe<&2, PiMessagesToolChoice>, debug: Maybe<&2, Bool>}

def Options(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data) -> Data: PiMessagesOptions<Signal, Telemetry, Fetch, Error>

def simpleChoice(value: T.ToolChoice) -> PiMessagesToolChoice:
  match value:
    case T.AutoTool{}: ToolChoiceAuto{}
    case T.NoTool{}: ToolChoiceNone{}

def simpleToolChoice(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>) -> Maybe<&2, T.ToolChoice>:
  match options:
    case T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, choice, _, _, _}: choice

def emptyStreamOptions(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data) -> T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>:
  T.toStreamOptions(J(), Signal, Telemetry, Fetch, Error, T.emptySimpleStreamOptions(J(), Signal, Telemetry, Fetch, Error))

# upstream streamSimple: the simple options with their reasoning level and
# tool choice. Upstream also reads `debug` from a caller object that is
# really a PiMessagesOptions; the typed port takes it as an argument.
def streamSimpleOptions(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>, debug: Maybe<&2, Bool>) -> Options(Signal, Telemetry, Fetch, Error):
  match options:
    case None{}: PiMessagesOptions{emptyStreamOptions(Signal, Telemetry, Fetch, Error), None{}, None{}, debug}
    case Some{+simple}:
      PiMessagesOptions{T.toStreamOptions(J(), Signal, Telemetry, Fetch, Error, simple), T.reasoningOption(J(), Signal, Telemetry, Fetch, Error, simple), Maybe.map(&2, T.ToolChoice, PiMessagesToolChoice, simpleChoice, simpleToolChoice(Signal, Telemetry, Fetch, Error, simple)), debug}

# Payload
# -------

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

def choiceJson(value: PiMessagesToolChoice) -> J():
  match value:
    case ToolChoiceAuto{}: str("auto")
    case ToolChoiceNone{}: str("none")
    case ToolChoiceRequired{}: str("required")
    case ToolChoiceFunction{name}: obj(field("type", str("function"), field("function", obj(field("name", str(name), Nil{})), Nil{})))

# upstream resolveCacheRetention: backend defaults apply when unset; only the
# legacy PI_CACHE_RETENTION=long opt-in is mapped.
def legacyRetention(value: Maybe<&2, String>) -> Maybe<&2, T.CacheRetention>:
  match value:
    case Some{"long"}: Some{T.CacheLong{}}
    case _: None{}

def resolveCacheRetention(cacheRetention: Maybe<&2, T.CacheRetention>, env: Maybe<&2, T.ProviderEnv()>) -> IO(Maybe<&2, T.CacheRetention>):
  match cacheRetention:
    case Some{value}: IO.pure(Maybe<&2, T.CacheRetention>, Some{value})
    case None{}:
      do IO<Maybe<&2, T.CacheRetention>>:
        legacy : Maybe<&2, String> <- Env.getProviderEnvValue("PI_CACHE_RETENTION", env)
        return legacyRetention(legacy)

# The `options` member as JSON.stringify writes it: absent values are omitted.
def optionsJson(temperature: Maybe<&2, F64>, maxTokens: Maybe<&2, F64>, reasoning: Maybe<&2, T.ThinkingLevel>, retention: Maybe<&2, T.CacheRetention>, sessionId: Maybe<&2, String>, choice: Maybe<&2, PiMessagesToolChoice>) -> J():
  obj(optional("temperature", Maybe.map(&2, F64, J(), num, temperature), optional("maxTokens", Maybe.map(&2, F64, J(), num, maxTokens), optional("reasoning", Maybe.map(&2, T.ThinkingLevel, J(), level => str(levelName(level)), reasoning), optional("cacheRetention", Maybe.map(&2, T.CacheRetention, J(), value => str(retentionName(value)), retention), optional("sessionId", Maybe.map(&2, String, J(), str, sessionId), optional("toolChoice", Maybe.map(&2, PiMessagesToolChoice, J(), choiceJson, choice), Nil{})))))))

def messagesJson(~G: Data, ~D: Data, ~diagnosticDetails: G -> V.Value, ~toolDetails: D -> V.Value, messages: List<&2, T.Message<V.Value, V.Value, G, D>>) -> List<&2, J()>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest:
      value = MessageJson.message(~G, ~D, ~diagnosticDetails, ~toolDetails, message)
      tail = messagesJson(~G, ~D, ~diagnosticDetails, ~toolDetails, rest)
      SchemaJson.toJson(value) <> tail

def contextJson(~G: Data, ~D: Data, ~diagnosticDetails: G -> V.Value, ~toolDetails: D -> V.Value, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> J():
  match context:
    case T.TranscriptContext{messages}:
      values = messagesJson(~G, ~D, ~diagnosticDetails, ~toolDetails, messages)
      obj(field("messages", arrayOf(values), Nil{}))

def arrayOf(values: List<&2, J()>) -> J(): T.JsonArray{values}

def payloadJson(id: String, context: J(), options: J()) -> J():
  obj(field("model", str(id), field("context", context, field("options", options, Nil{}))))

# Stream events
# -------------

# upstream PiMessagesRewriteImpact.
type PiMessagesRewriteImpact is Data:
  PiMessagesRewriteImpact{policyId: String, policyVersion: F64, changed: Bool, tokenCountChange: F64, messageCountChange: F64, systemPromptChanged: Bool}

# upstream PiMessagesEvent, as a pi-messages backend serializes it.
type PiMessagesEvent is Data:
  EventStart{}
  EventTextStart{contentIndex: F64}
  EventTextDelta{contentIndex: F64, delta: String}
  EventTextEnd{contentIndex: F64, content: String, contentSignature: Maybe<&2, String>}
  EventThinkingStart{contentIndex: F64}
  EventThinkingDelta{contentIndex: F64, delta: String}
  EventThinkingEnd{contentIndex: F64, content: String, contentSignature: Maybe<&2, String>, redacted: Maybe<&2, Bool>}
  EventToolcallStart{contentIndex: F64, id: String, toolName: String}
  EventToolcallDelta{contentIndex: F64, delta: String}
  EventToolcallEnd{contentIndex: F64, toolCall: T.ToolCall<V.Value>}
  EventDone{reason: T.DoneReason, usage: T.Usage, responseId: Maybe<&2, String>, providerThinkingLevel: Maybe<&2, String>, rewrite: Maybe<&2, PiMessagesRewriteImpact>}
  EventError{reason: T.ErrorReason, usage: T.Usage, errorMessage: Maybe<&2, String>, responseId: Maybe<&2, String>, providerThinkingLevel: Maybe<&2, String>, rewrite: Maybe<&2, PiMessagesRewriteImpact>}

def Decoded(-A: Data) -> Data: Result<&2, &2, Decode.Error, A>

def boolean(value: V.Value) -> Decoded(Bool):
  match value:
    case V.Boolean{flag}: Done{flag}
    case _: Fail{Decode.WrongType{Nil{}, "boolean"}}

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

def rewriteFields(+fields: R.Record<V.Value>) -> Decoded(PiMessagesRewriteImpact):
  do Result<&2, &2, Decode.Error, PiMessagesRewriteImpact>:
    policyId : String <- Decode.required(String, fields, "policyId", Decode.string)
    policyVersion : F64 <- Decode.required(F64, fields, "policyVersion", Decode.number)
    changed : Bool <- Decode.required(Bool, fields, "changed", boolean)
    tokens : F64 <- Decode.required(F64, fields, "tokenCountChange", Decode.number)
    messages : F64 <- Decode.required(F64, fields, "messageCountChange", Decode.number)
    system : Bool <- Decode.required(Bool, fields, "systemPromptChanged", boolean)
    return PiMessagesRewriteImpact{policyId, policyVersion, changed, tokens, messages, system}

def decodeRewrite(value: V.Value) -> Decoded(PiMessagesRewriteImpact):
  Result.bind(&2, &2, Decode.Error, R.Record<V.Value>, PiMessagesRewriteImpact, Decode.object(value), fields => rewriteFields(fields))

def indexField(+fields: R.Record<V.Value>) -> Decoded(F64): Decode.required(F64, fields, "contentIndex", Decode.number)
def textField(+fields: R.Record<V.Value>, +key: String) -> Decoded(String): Decode.required(String, fields, key, Decode.string)
def optionalTextField(+fields: R.Record<V.Value>, +key: String) -> Decoded(Maybe<&2, String>): Decode.optional(String, fields, key, Decode.string)

def doneFields(+fields: R.Record<V.Value>) -> Decoded(PiMessagesEvent):
  do Result<&2, &2, Decode.Error, PiMessagesEvent>:
    reason : String <- textField(fields, "reason")
    kind : T.DoneReason <- doneReasonOf(reason)
    usage : T.Usage <- Decode.required(T.Usage, fields, "usage", MessageJson.decodeUsage)
    responseId : Maybe<&2, String> <- optionalTextField(fields, "responseId")
    level : Maybe<&2, String> <- optionalTextField(fields, "providerThinkingLevel")
    rewrite : Maybe<&2, PiMessagesRewriteImpact> <- Decode.optional(PiMessagesRewriteImpact, fields, "rewrite", decodeRewrite)
    return EventDone{kind, usage, responseId, level, rewrite}

def errorFields(+fields: R.Record<V.Value>) -> Decoded(PiMessagesEvent):
  do Result<&2, &2, Decode.Error, PiMessagesEvent>:
    reason : String <- textField(fields, "reason")
    kind : T.ErrorReason <- errorReasonOf(reason)
    usage : T.Usage <- Decode.required(T.Usage, fields, "usage", MessageJson.decodeUsage)
    message : Maybe<&2, String> <- optionalTextField(fields, "errorMessage")
    responseId : Maybe<&2, String> <- optionalTextField(fields, "responseId")
    level : Maybe<&2, String> <- optionalTextField(fields, "providerThinkingLevel")
    rewrite : Maybe<&2, PiMessagesRewriteImpact> <- Decode.optional(PiMessagesRewriteImpact, fields, "rewrite", decodeRewrite)
    return EventError{kind, usage, message, responseId, level, rewrite}

def indexed(+fields: R.Record<V.Value>, make: F64 -> PiMessagesEvent) -> Decoded(PiMessagesEvent):
  Result.map(&2, &2, Decode.Error, F64, PiMessagesEvent, make, indexField(fields))

def deltaEvent(+fields: R.Record<V.Value>, make: F64 -> String -> PiMessagesEvent) -> Decoded(PiMessagesEvent):
  do Result<&2, &2, Decode.Error, PiMessagesEvent>:
    at : F64 <- indexField(fields)
    value : String <- textField(fields, "delta")
    return make(at, value)

def textEnd(+fields: R.Record<V.Value>) -> Decoded(PiMessagesEvent):
  do Result<&2, &2, Decode.Error, PiMessagesEvent>:
    at : F64 <- indexField(fields)
    content : String <- textField(fields, "content")
    signature : Maybe<&2, String> <- optionalTextField(fields, "contentSignature")
    return EventTextEnd{at, content, signature}

def thinkingEnd(+fields: R.Record<V.Value>) -> Decoded(PiMessagesEvent):
  do Result<&2, &2, Decode.Error, PiMessagesEvent>:
    at : F64 <- indexField(fields)
    content : String <- textField(fields, "content")
    signature : Maybe<&2, String> <- optionalTextField(fields, "contentSignature")
    redacted : Maybe<&2, Bool> <- Decode.optional(Bool, fields, "redacted", boolean)
    return EventThinkingEnd{at, content, signature, redacted}

def toolcallStart(+fields: R.Record<V.Value>) -> Decoded(PiMessagesEvent):
  do Result<&2, &2, Decode.Error, PiMessagesEvent>:
    at : F64 <- indexField(fields)
    id : String <- textField(fields, "id")
    name : String <- textField(fields, "toolName")
    return EventToolcallStart{at, id, name}

def toolCallValue(value: V.Value) -> Decoded(T.ToolCall<V.Value>):
  Result.bind(&2, &2, Decode.Error, R.Record<V.Value>, T.ToolCall<V.Value>, Decode.object(value), fields => MessageJson.toolCallFields(fields))

def toolcallEnd(+fields: R.Record<V.Value>) -> Decoded(PiMessagesEvent):
  do Result<&2, &2, Decode.Error, PiMessagesEvent>:
    at : F64 <- indexField(fields)
    call : T.ToolCall<V.Value> <- Decode.required(T.ToolCall<V.Value>, fields, "toolCall", toolCallValue)
    return EventToolcallEnd{at, call}

def someEvent(result: Decoded(PiMessagesEvent)) -> Decoded(Maybe<&2, PiMessagesEvent>):
  Result.map(&2, &2, Decode.Error, PiMessagesEvent, Maybe<&2, PiMessagesEvent>, event => Some{event}, result)

# Unknown event types decode as None: upstream forwards them unchanged, and
# the typed event union has no member to carry them.
def eventOf(+kind: String, +fields: R.Record<V.Value>) -> Decoded(Maybe<&2, PiMessagesEvent>):
  match kind:
    case "start": Done{Some{EventStart{}}}
    case "text_start": someEvent(indexed(fields, at => EventTextStart{at}))
    case "text_delta": someEvent(deltaEvent(fields, at => value => EventTextDelta{at, value}))
    case "text_end": someEvent(textEnd(fields))
    case "thinking_start": someEvent(indexed(fields, at => EventThinkingStart{at}))
    case "thinking_delta": someEvent(deltaEvent(fields, at => value => EventThinkingDelta{at, value}))
    case "thinking_end": someEvent(thinkingEnd(fields))
    case "toolcall_start": someEvent(toolcallStart(fields))
    case "toolcall_delta": someEvent(deltaEvent(fields, at => value => EventToolcallDelta{at, value}))
    case "toolcall_end": someEvent(toolcallEnd(fields))
    case "done": someEvent(doneFields(fields))
    case "error": someEvent(errorFields(fields))
    case _: Done{None{}}

def decodeEvent(value: V.Value) -> Decoded(Maybe<&2, PiMessagesEvent>):
  do Result<&2, &2, Decode.Error, Maybe<&2, PiMessagesEvent>>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    kind : String <- textField(fields, "type")
    eventOf(kind, fields)

# Event conversion
# ----------------

# upstream createEventConverter: the partial message the events update and
# the tool-call argument JSON accumulated per content index.
type ToolJson is Data:
  ToolJson{index: Nat, json: String}

type Converter<-G: Data> is Data:
  Converter{partial: T.AssistantMessage<V.Value, G>, toolJson: List<&2, ToolJson>}

def Message(-G: Data) -> Data: T.AssistantMessage<V.Value, G>
def Event(-G: Data) -> Data: T.AssistantMessageEvent<V.Value, G>
def Content() -> Data: T.AssistantContent<V.Value>

def zeroCost() -> T.UsageCost: T.UsageCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0)}

def createEmptyUsage() -> T.Usage: T.Usage{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}, None{}, F.fromU32(0), zeroCost()}

def emptyMessage(-G: Data, model: T.Model<J()>, stop: T.StopReason, errorMessage: Maybe<&2, String>, timestamp: F64) -> Message(G):
  match model:
    case T.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _, _, _}: T.AssistantMessage{Nil{}, ModelApi.name(api), provider, id, None{}, None{}, None{}, None{}, createEmptyUsage(), stop, None{}, errorMessage, None{}, None{}, timestamp}

def createConverter(-G: Data, model: T.Model<J()>, timestamp: F64) -> Converter<G>:
  Converter{emptyMessage(G, model, T.Pending{}, None{}, timestamp), Nil{}}

def natural(value: Result<&2, &2, F.Error, Nat>) -> Nat:
  match value:
    case Done{number}: number
    case Fail{_}: 0n

def indexOf(value: F64) -> Nat: natural(F.convert(F.truncate(value)))

# `partial.content[index] = block`. Upstream arrays may become sparse; the
# port appends a block placed past the end.
def placed(content: List<&2, Content()>, +index: Nat, block: Content()) -> List<&2, Content()>:
  match content index:
    case Nil{} _: block <> Nil{}
    case _ <> rest 0n: block <> rest
    case head <> rest 1n+previous: head <> placed(rest, previous, block)

def updated(content: List<&2, Content()>, +index: Nat, change: Content() -> Content()) -> List<&2, Content()>:
  match content index:
    case Nil{} _: Nil{}
    case head <> rest 0n: change(head) <> rest
    case head <> rest 1n+previous: head <> updated(rest, previous, change)

def withContent(-G: Data, message: Message(G), change: List<&2, Content()> -> List<&2, Content()>) -> Message(G):
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{change(content), api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def appendText(block: Content(), +delta: String) -> Content():
  match block:
    case T.AssistantText{T.TextContent{text, signature}}: T.AssistantText{T.TextContent{text ++ delta, signature}}
    case other: other

def endText(block: Content(), +content: String, +signature: Maybe<&2, String>) -> Content():
  match block:
    case T.AssistantText{T.TextContent{_, _}}: T.AssistantText{T.TextContent{content, signature}}
    case other: other

def appendThinking(block: Content(), +delta: String) -> Content():
  match block:
    case T.AssistantThinking{T.ThinkingContent{thinking, signature, redacted}}: T.AssistantThinking{T.ThinkingContent{thinking ++ delta, signature, redacted}}
    case other: other

def endThinking(block: Content(), +content: String, +signature: Maybe<&2, String>, +redacted: Maybe<&2, Bool>) -> Content():
  match block:
    case T.AssistantThinking{T.ThinkingContent{_, _, _}}: T.AssistantThinking{T.ThinkingContent{content, signature, redacted}}
    case other: other

def withArguments(block: Content(), +arguments: V.Value) -> Content():
  match block:
    case T.AssistantToolCall{T.ToolCall{id, name, _, signature, namespace}}: T.AssistantToolCall{T.ToolCall{id, name, arguments, signature, namespace}}
    case other: other

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

def blockAt(content: List<&2, Content()>, +index: Nat) -> Maybe<&2, Content()>:
  match content index:
    case Nil{} _: None{}
    case head <> _ 0n: Some{head}
    case _ <> rest 1n+previous: blockAt(rest, previous)

def contentOf(-G: Data, message: Message(G)) -> List<&2, Content()>: T.assistantContent(V.Value, G, message)

def callOr(block: Maybe<&2, Content()>, fallback: T.ToolCall<V.Value>) -> T.ToolCall<V.Value>:
  match block:
    case Some{T.AssistantToolCall{call}}: call
    case _: fallback

def toolCallAt(-G: Data, message: Message(G), +index: Nat, fallback: T.ToolCall<V.Value>) -> T.ToolCall<V.Value>:
  callOr(blockAt(contentOf(G, message), index), fallback)

def rewriteDetails(value: PiMessagesRewriteImpact) -> J():
  match value:
    case PiMessagesRewriteImpact{policyId, policyVersion, changed, tokens, messages, system}:
      obj(field("policyId", str(policyId), field("policyVersion", num(policyVersion), field("changed", T.JsonBoolean{changed}, field("tokenCountChange", num(tokens), field("messageCountChange", num(messages), field("systemPromptChanged", T.JsonBoolean{system}, Nil{})))))))

def appendDiagnostic(-G: Data, diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>, diagnostic: Diagnostics.AssistantMessageDiagnostic<G>) -> Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>:
  Some{List.append(&2, Diagnostics.AssistantMessageDiagnostic<G>, Maybe.default(&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>, diagnostics, Nil{}), diagnostic <> Nil{})}

# upstream appendRewriteDiagnostic.
def rewriteDiagnostic(~G: Data, ~details: J() -> G, diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>, rewrite: Maybe<&2, PiMessagesRewriteImpact>, now: F64) -> Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>:
  match rewrite:
    case None{}: diagnostics
    case Some{impact}:
      detail = details(rewriteDetails(impact))
      appendDiagnostic(G, diagnostics, Diagnostics.AssistantMessageDiagnostic{"pi_messages_rewrite", now, None{}, Some{detail}})

# The terminal events: Object.assign(partial, { stopReason, usage,
# [errorMessage,] responseId }), providerThinkingLevel when present, and the
# rewrite diagnostic.
def settled(~G: Data, ~details: J() -> G, message: Message(G), stop: T.StopReason, usage: T.Usage, errorMessage: Maybe<&2, String>, keepError: Bool, responseId: Maybe<&2, String>, level: Maybe<&2, String>, rewrite: Maybe<&2, PiMessagesRewriteImpact>, now: F64) -> Message(G):
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, _, previousLevel, diagnostics, _, _, deferred, previousError, raw, endTurn, timestamp}:
      diagnosticList = rewriteDiagnostic(~G, ~details, diagnostics, rewrite, now)
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, Maybe.or(&2, String, level, previousLevel), diagnosticList, usage, stop, deferred, Bool.pick(Maybe<&2, String>, keepError, previousError, errorMessage), raw, endTurn, timestamp}

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

type Converted<-G: Data> is Data:
  Converted{converter: Converter<G>, event: Event(G)}

def partialEvent(-G: Data, converter: Converter<G>, make: Message(G) -> Event(G)) -> Converted<G>:
  match converter:
    case Converter{+partial, json}: Converted{Converter{partial, json}, make(partial)}

def changed(-G: Data, converter: Converter<G>, change: List<&2, Content()> -> List<&2, Content()>, make: Message(G) -> Event(G)) -> Converted<G>:
  match converter:
    case Converter{partial, json}: partialEvent(G, Converter{withContent(G, partial, change), json}, make)

def toolDelta(-G: Data, converter: Converter<G>, +at: F64, +delta: String) -> Converted<G>:
  match converter:
    case Converter{partial, +json}:
      +index = indexOf(at)
      +accumulated = jsonAt(json, index) ++ delta
      +arguments = JsonRepair.parseStreamingJson(Some{accumulated})
      partialEvent(G, Converter{withContent(G, partial, content => updated(content, index, block => withArguments(block, arguments))), withJson(json, index, accumulated)}, message => T.ToolcallDelta{at, delta, message})

def toolEnd(-G: Data, converter: Converter<G>, +at: F64, +call: T.ToolCall<V.Value>) -> Converted<G>:
  match converter:
    case Converter{partial, json}:
      +index = indexOf(at)
      +message = withContent(G, partial, content => updated(content, index, block => T.AssistantToolCall{call}))
      Converted{Converter{message, withoutJson(json, index)}, T.ToolcallEnd{at, toolCallAt(G, message, index, call), message}}

def terminal(-G: Data, converter: Converter<G>, +message: Message(G), event: Event(G)) -> Converted<G>:
  match converter:
    case Converter{_, json}: Converted{Converter{message, json}, event}

def toolStart(-G: Data, converter: Converter<G>, +at: F64, id: String, name: String) -> Converted<G>:
  match converter:
    case Converter{partial, json}: partialEvent(G, Converter{withContent(G, partial, content => placed(content, indexOf(at), T.AssistantToolCall{T.ToolCall{id, name, V.ObjectValue{R.new(V.Value)}, None{}, None{}}})), withJson(json, indexOf(at), "")}, message => T.ToolcallStart{at, message})

def doneEvent(~G: Data, ~details: J() -> G, converter: Converter<G>, +reason: T.DoneReason, usage: T.Usage, responseId: Maybe<&2, String>, level: Maybe<&2, String>, rewrite: Maybe<&2, PiMessagesRewriteImpact>, now: F64) -> Converted<G>:
  match converter:
    case Converter{partial, json}:
      +message = settled(~G, ~details, partial, doneStop(reason), usage, None{}, True{}, responseId, level, rewrite, now)
      Converted{Converter{message, json}, T.StreamDone{reason, message}}

def errorEvent(~G: Data, ~details: J() -> G, converter: Converter<G>, +reason: T.ErrorReason, usage: T.Usage, errorMessage: Maybe<&2, String>, responseId: Maybe<&2, String>, level: Maybe<&2, String>, rewrite: Maybe<&2, PiMessagesRewriteImpact>, now: F64) -> Converted<G>:
  match converter:
    case Converter{partial, json}:
      +message = settled(~G, ~details, partial, errorStop(reason), usage, errorMessage, False{}, responseId, level, rewrite, now)
      Converted{Converter{message, json}, T.StreamError{reason, message}}

def convertEvent(~G: Data, ~details: J() -> G, converter: Converter<G>, event: PiMessagesEvent, now: F64) -> Converted<G>:
  match event:
    case EventStart{}: partialEvent(G, converter, message => T.Start{message})
    case EventTextStart{+at}: changed(G, converter, content => placed(content, indexOf(at), T.AssistantText{T.TextContent{"", None{}}}), message => T.TextStart{at, message})
    case EventTextDelta{+at, +delta}: changed(G, converter, content => updated(content, indexOf(at), block => appendText(block, delta)), message => T.TextDelta{at, delta, message})
    case EventTextEnd{+at, +content, +signature}: changed(G, converter, blocks => updated(blocks, indexOf(at), block => endText(block, content, signature)), message => T.TextEnd{at, content, message})
    case EventThinkingStart{+at}: changed(G, converter, content => placed(content, indexOf(at), T.AssistantThinking{T.ThinkingContent{"", None{}, None{}}}), message => T.ThinkingStart{at, message})
    case EventThinkingDelta{+at, +delta}: changed(G, converter, content => updated(content, indexOf(at), block => appendThinking(block, delta)), message => T.ThinkingDelta{at, delta, message})
    case EventThinkingEnd{+at, +content, +signature, +redacted}: changed(G, converter, blocks => updated(blocks, indexOf(at), block => endThinking(block, content, signature, redacted)), message => T.ThinkingEnd{at, content, message})
    case EventToolcallStart{at, id, name}: toolStart(G, converter, at, id, name)
    case EventToolcallDelta{at, delta}: toolDelta(G, converter, at, delta)
    case EventToolcallEnd{at, call}: toolEnd(G, converter, at, call)
    case EventDone{reason, usage, responseId, level, rewrite}: doneEvent(~G, ~details, converter, reason, usage, responseId, level, rewrite, now)
    case EventError{reason, usage, errorMessage, responseId, level, rewrite}: errorEvent(~G, ~details, converter, reason, usage, errorMessage, responseId, level, rewrite, now)

def isTerminal(-G: Data, event: Event(G)) -> Bool:
  match event:
    case T.StreamDone{_, _}: True{}
    case T.StreamError{_, _}: True{}
    case _: False{}

# Reading the stream
# ------------------

# upstream readPiMessagesEvents: decoded text, CRLF folded to LF, split at
# blank lines; the first `data:` line of a block, trimmed, is the event
# unless it is empty or `[DONE]`.
def splitFrames(text: String, current: String, frames: List<&2, String>) -> List<&2, String> & String:
  match text:
    case SNil{}: (List.reverse(&2, String, frames), String.reverse(current))
    case SCon{'\n', SCon{'\n', rest}}: splitFrames(rest, SNil{}, String.reverse(current) <> frames)
    case SCon{c, rest}: splitFrames(rest, SCon{c, current}, frames)

def firstData(lines: List<&2, String>) -> Maybe<&2, String>:
  match lines:
    case Nil{}: None{}
    case +line <> rest: Bool.pick(Maybe<&2, String>, String.starts_with(line, "data:"), Some{Space.trim(String.drop(line, 5n))}, firstData(rest))

def decodedEvent(result: Decoded(Maybe<&2, PiMessagesEvent>)) -> Result<&2, &2, String, Maybe<&2, PiMessagesEvent>>:
  match result:
    case Fail{_}: Fail{"Invalid pi-messages event"}
    case Done{event}: Done{event}

def parsedEvent(result: Result<&2, &2, Decode.ParseError, V.Value>) -> Result<&2, &2, String, Maybe<&2, PiMessagesEvent>>:
  match result:
    case Fail{_}: Fail{"Invalid JSON in pi-messages event"}
    case Done{value}: decodedEvent(decodeEvent(value))

def dataEvent(value: Maybe<&2, String>) -> Result<&2, &2, String, Maybe<&2, PiMessagesEvent>>:
  match value:
    case None{}: Done{None{}}
    case Some{SNil{}}: Done{None{}}
    case Some{"[DONE]"}: Done{None{}}
    case Some{data}: parsedEvent(Decode.parse(data))

def parsePiMessagesEvent(raw: String) -> Result<&2, &2, String, Maybe<&2, PiMessagesEvent>>:
  dataEvent(firstData(String.split(raw, '\n')))

# Where the reader stands: still streaming, past the final chunk with the
# remaining buffer to parse, or finished with it.
type Phase is Data:
  Streaming{}
  Ending{}
  Ended{}

type Reading<-G: Data> is Data:
  Reading{decoder: Utf8.Decoder, buffer: String, converter: Converter<G>}

# What ends reading without a terminal event.
type Thrown is Data:
  Unterminated{}
  ThrownMessage{message: String}

type Loop<-G: Data> is Data:
  Pull{reading: Reading<G>}
  Frames{reading: Reading<G>, frames: List<&2, String>, phase: Phase}
  Stop{error: Maybe<&2, Thrown>}

def framed(-G: Data, decoder: Utf8.Decoder, converter: Converter<G>, phase: Phase, pair: List<&2, String> & String) -> Loop<G>:
  match pair:
    case (frames, rest): Frames{Reading{decoder, rest, converter}, frames, phase}

def appended(-G: Data, reading: Reading<G>, decoded: Utf8.Decoded, phase: Phase) -> Loop<G>:
  match reading decoded:
    case Reading{_, buffer, converter} Utf8.Decoded{decoder, text}: framed(G, decoder, converter, phase, splitFrames(Strings.replaceAll(buffer ++ text, "\r\n", "\n"), SNil{}, Nil{}))

def decoderOf(-G: Data, reading: Reading<G>) -> Utf8.Decoder:
  match reading:
    case Reading{decoder, _, _}: decoder

def pulled(-Reason: Data, -G: Data, +reading: Reading<G>, result: Result<&2, &2, Http.ReadError(Reason), Maybe<&2, List<&2, U32>>>) -> Loop<G>:
  match result:
    case Fail{_}: Stop{Some{ThrownMessage{"terminated"}}}
    case Done{None{}}: appended(G, reading, Utf8.finish(decoderOf(G, reading)), Ending{})
    case Done{Some{bytes}}: appended(G, reading, Utf8.decode(decoderOf(G, reading), bytes), Streaming{})

def EventStream(-G: Data) -> Data: Events.AssistantMessageEventStream(V.Value, G)

def push(-G: Data, +events: EventStream(G), event: Event(G)) -> IO(Unit):
  Events.push(Event(G), Message(G), events, event)

def converterOf(-G: Data, reading: Reading<G>) -> Converter<G>:
  match reading:
    case Reading{_, _, converter}: converter

def withConverter(-G: Data, reading: Reading<G>, converter: Converter<G>) -> Reading<G>:
  match reading:
    case Reading{decoder, buffer, _}: Reading{decoder, buffer, converter}

def blankBuffer(-G: Data, reading: Reading<G>) -> Bool:
  match reading:
    case Reading{_, buffer, _}: String.is_empty(Space.trim(buffer))

def withoutBuffer(-G: Data, reading: Reading<G>) -> Reading<G> & String:
  match reading:
    case Reading{decoder, buffer, converter}: (Reading{decoder, "", converter}, buffer)

def withTail(-G: Data, pair: Reading<G> & String) -> Loop<G>:
  match pair:
    case (reading, rest): Frames{reading, rest <> Nil{}, Ended{}}

def unterminated() -> Maybe<&2, Thrown>: Some{Unterminated{}}

# After the frames of a read: read more, parse the remaining buffer once the
# body ended, or report the missing terminal event.
def exhausted(-G: Data, +reading: Reading<G>, phase: Phase) -> Loop<G>:
  match phase:
    case Streaming{}: Pull{reading}
    case Ending{}: Bool.pick(Loop<G>, blankBuffer(G, reading), Stop{unterminated()}, withTail(G, withoutBuffer(G, reading)))
    case Ended{}: Stop{unterminated()}

def convertedStep(-G: Data, reading: Reading<G>, frames: List<&2, String>, phase: Phase, converted: Converted<G>) -> Event(G) & Loop<G>:
  match converted:
    case Converted{converter, +event}: (event, Bool.pick(Loop<G>, isTerminal(G, event), Stop{None{}}, Frames{withConverter(G, reading, converter), frames, phase}))

def framesAfter(~G: Data, ~details: J() -> G, +events: EventStream(G), +reading: Reading<G>, frames: List<&2, String>, phase: Phase, parsed: Result<&2, &2, String, Maybe<&2, PiMessagesEvent>>) -> IO(Loop<G>):
  match parsed:
    case Fail{message}: IO.pure(Loop<G>, Stop{Some{ThrownMessage{message}}})
    case Done{None{}}: IO.pure(Loop<G>, Frames{reading, frames, phase})
    case Done{Some{event}}:
      do IO<Loop<G>>:
        now : F64 <- Date.now()
        pair : Event(G) & Loop<G> <- IO.pure(Event(G) & Loop<G>, convertedStep(G, reading, frames, phase, convertEvent(~G, ~details, converterOf(G, reading), event, now)))
        publishStep(G, events, pair)

def publishStep(-G: Data, +events: EventStream(G), pair: Event(G) & Loop<G>) -> IO(Loop<G>):
  match pair:
    case (event, next):
      do IO<Loop<G>>:
        push(G, events, event)
        return next

@unsafe def drive(~Reason: Data, ~G: Data, ~details: J() -> G, +events: EventStream(G), +source: Http.Source(Reason), state: Loop<G>) -> IO(Maybe<&2, Thrown>):
  match state:
    case Stop{error}: IO.pure(Maybe<&2, Thrown>, error)
    case Pull{reading}:
      do IO<Maybe<&2, Thrown>>:
        result : Result<&2, &2, Http.ReadError(Reason), Maybe<&2, List<&2, U32>>> <- Http.read(~Reason, source)
        drive(~Reason, ~G, ~details, events, source, pulled(Reason, G, reading, result))
    case Frames{reading, Nil{}, phase}: drive(~Reason, ~G, ~details, events, source, exhausted(G, reading, phase))
    case Frames{reading, frame <> rest, phase}:
      do IO<Maybe<&2, Thrown>>:
        next : Loop<G> <- framesAfter(~G, ~details, events, reading, rest, phase, parsePiMessagesEvent(frame))
        drive(~Reason, ~G, ~details, events, source, next)

# Failures
# --------

def Diagnostic(-G: Data) -> Data: Diagnostics.AssistantMessageDiagnostic<G>

# upstream createErrorEvent: a fresh message carrying the error; the response
# diagnostic is kept unless the request was aborted.
def errorDiagnostics(-G: Data, diagnostic: Maybe<&2, Diagnostic(G)>, aborted: Bool) -> Maybe<&2, List<&2, Diagnostic(G)>>:
  match diagnostic aborted:
    case Some{value} False{}: Some{value <> Nil{}}
    case _ _: None{}

def withDiagnostics(-G: Data, message: Message(G), diagnostics: Maybe<&2, List<&2, Diagnostic(G)>>) -> Message(G):
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, _, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def createErrorEvent(-G: Data, model: T.Model<J()>, message: String, diagnostic: Maybe<&2, Diagnostic(G)>, +aborted: Bool, now: F64) -> Event(G):
  +reason = Bool.pick(T.ErrorReason, aborted, T.ErrorAborted{}, T.ErrorError{})
  T.StreamError{reason, withDiagnostics(G, emptyMessage(G, model, errorStop(reason), Some{message}, now), errorDiagnostics(G, diagnostic, aborted))}

def thrown(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, model: T.Model<J()>, message: String, diagnostic: Maybe<&2, Diagnostic(G)>) -> IO(Unit):
  do IO<Unit>:
    aborted : Bool <- Abort.aborted(Reason, parent)
    now : F64 <- Date.now()
    push(G, events, createErrorEvent(G, model, message, diagnostic, aborted, now))

def objectMember(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<V.Value>>:
  match value:
    case Some{V.ObjectValue{fields}}: Some{fields}
    case _: None{}

# upstream parsePiMessagesErrorBody: the body's `error` object, if the body is
# JSON whose `error` member is a non-array object.

# upstream PiMessagesResponseError and its diagnostic details.
def errorObject(value: V.Value) -> Maybe<&2, R.Record<V.Value>>:
  match value:
    case V.ObjectValue{+fields}: objectMember(R.get(V.Value, fields, "error"))
    case _: None{}

def parsedErrorBody(result: Result<&2, &2, Decode.ParseError, V.Value>) -> Maybe<&2, R.Record<V.Value>>:
  match result:
    case Fail{_}: None{}
    case Done{value}: errorObject(value)

def parsePiMessagesErrorBody(body: String) -> Maybe<&2, R.Record<V.Value>>: parsedErrorBody(Decode.parse(body))

def stringValue(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case _: None{}

def stringMember(error: Maybe<&2, R.Record<V.Value>>, name: String) -> Maybe<&2, String>:
  match error:
    case Some{fields}: stringValue(R.get(V.Value, fields, name))
    case None{}: None{}

def codeSuffix(code: Maybe<&2, String>) -> String:
  match code:
    case None{}: ""
    case Some{SNil{}}: ""
    case Some{value}: " (" ++ value ++ ")"

def formatPiMessagesResponseError(status: U32, statusText: String, +body: String, +error: Maybe<&2, R.Record<V.Value>>) -> String:
  U32.show(status) ++ " " ++ statusText ++ ": " ++ Maybe.default(&2, String, stringMember(error, "message"), body) ++ codeSuffix(stringMember(error, "code"))

def truncateDiagnosticString(+value: String) -> String:
  Bool.pick(String, Nat.is_gt(Utf16.length(value), 8192n), Utf16.take(value, 8192n) ++ "…", value)

def bodyFields(+body: String, error: Maybe<&2, R.Record<V.Value>>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match error:
    case Some{fields}: field("error", SchemaJson.toJson(V.ObjectValue{fields}), rest)
    case None{}: field("body", str(truncateDiagnosticString(body)), rest)

def errorDetails(model: T.Model<J()>, url: String, status: U32, statusText: String, +body: String, error: Maybe<&2, R.Record<V.Value>>, now: F64) -> J():
  match model:
    case T.Model{id, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}:
      obj(field("version", num(F.fromU32(1)), field("provider", str(provider), field("model", str(id), field("url", str(url), field("status", num(F.fromU32(status)), field("statusText", str(statusText), bodyFields(body, error, field("timestampMs", num(now), Nil{})))))))))

def responseFailure(~G: Data, ~details: J() -> G, model: T.Model<J()>, url: String, +status: U32, +statusText: String, +body: String, +now: F64) -> String & Diagnostic(G):
  +error = parsePiMessagesErrorBody(body)
  +message = formatPiMessagesResponseError(status, statusText, body, error)
  detail = details(errorDetails(model, url, status, statusText, body, error, now))
  (message, Diagnostics.AssistantMessageDiagnostic{"pi_messages_response_failure", now, Some{Diagnostics.DiagnosticErrorInfo{Some{"PiMessagesResponseError"}, message, None{}, Maybe.map(&2, String, Diagnostics.DiagnosticCode, code => Diagnostics.StringCode{code}, stringMember(error, "code"))}}, Some{detail}})

# Streaming
# ---------

# What the request needs once the payload is settled.
type Setup<-Reason: Data, -E: Data> is Data:
  Setup{model: T.Model<J()>, url: String, key: String, headers: Maybe<&2, T.ProviderHeaders()>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, fetch: Fetch.Fetch(Reason), urlContext: URL.Context, timestamp: F64}

def setupModel(-Reason: Data, -E: Data, setup: Setup<Reason, E>) -> T.Model<J()>:
  match setup:
    case Setup{model, _, _, _, _, _, _, _}: model

def modelProvider(model: T.Model<J()>) -> String: T.modelProvider(model)

# A transport failure is the fetch's rejection: an abort, or a network error.
def transportThrown(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, model: T.Model<J()>, message: String) -> IO(Unit):
  do IO<Unit>:
    aborted : Bool <- Abort.aborted(Reason, parent)
    thrown(~Reason, ~G, events, parent, model, Bool.pick(String, aborted, "This operation was aborted", message), None{})

def ending(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, outcome: Maybe<&2, Thrown>) -> IO(Unit):
  match outcome:
    case None{}: IO.pure(Unit, Unit{})
    case Some{Unterminated{}}: thrown(~Reason, ~G, events, parent, model, modelProvider(model) ++ " stream ended without a terminal event", None{})
    case Some{ThrownMessage{"terminated"}}: transportThrown(~Reason, ~G, events, parent, model, "terminated")
    case Some{ThrownMessage{message}}: thrown(~Reason, ~G, events, parent, model, message, None{})

def streamed(~Reason: Data, ~G: Data, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, timestamp: F64, pair: Http.Owner(Reason) & Http.Source(Reason)) -> IO(Unit):
  match pair:
    case (owner, source):
      do IO<Unit>:
        outcome : Maybe<&2, Thrown> <- drive(~Reason, ~G, ~details, events, source, Pull{Reading{Utf8.create(), "", createConverter(G, model, timestamp)}})
        Http.release(~Reason, owner)
        ending(~Reason, ~G, events, parent, model, outcome)

def releasedPair(~Reason: Data, pair: Http.Owner(Reason) & Http.Source(Reason)) -> IO(Unit):
  match pair:
    case (owner, _): Http.release(~Reason, owner)

def discarded(~Reason: Data, body: Http.Body(Reason)) -> IO(Unit):
  do IO<Unit>:
    pair : Http.Owner(Reason) & Http.Source(Reason) <- Http.reader(~Reason, body)
    releasedPair(~Reason, pair)

def thrownFailure(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, model: T.Model<J()>, failure: String & Diagnostic(G)) -> IO(Unit):
  match failure:
    case (message, diagnostic): thrown(~Reason, ~G, events, parent, model, message, Some{diagnostic})

def failedStatus(~Reason: Data, ~G: Data, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, url: String, +metadata: Response.Metadata, text: Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String>) -> IO(Unit):
  match text:
    case Fail{_}: transportThrown(~Reason, ~G, events, parent, model, "terminated")
    case Done{body}:
      do IO<Unit>:
        now : F64 <- Date.now()
        failure : String & Diagnostic(G) <- IO.pure(String & Diagnostic(G), responseFailure(~G, ~details, model, url, Response.metadataStatus(metadata), Response.statusText(metadata), body, now))
        thrownFailure(~Reason, ~G, events, parent, model, failure)

def okResponse(~Reason: Data, ~G: Data, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, timestamp: F64, present: Bool, body: Http.Body(Reason)) -> IO(Unit):
  match present:
    case True{}:
      do IO<Unit>:
        pair : Http.Owner(Reason) & Http.Source(Reason) <- Http.reader(~Reason, body)
        streamed(~Reason, ~G, ~details, events, parent, model, timestamp, pair)
    case False{}:
      do IO<Unit>:
        discarded(~Reason, body)
        thrown(~Reason, ~G, events, parent, model, modelProvider(model) ++ " response has no body", None{})

def statusChecked(~Reason: Data, ~G: Data, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, url: String, timestamp: F64, +metadata: Response.Metadata, body: Http.Body(Reason), ok: Bool) -> IO(Unit):
  match ok:
    case True{}: okResponse(~Reason, ~G, ~details, events, parent, model, timestamp, Response.bodyPresent(metadata), body)
    case False{}:
      do IO<Unit>:
        text : Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String> <- Http.responseText(~Reason, 1048576n, body)
        failedStatus(~Reason, ~G, ~details, events, parent, model, url, metadata, text)

def checkedStatus(~Reason: Data, ~G: Data, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, url: String, timestamp: F64, +metadata: Response.Metadata, body: Http.Body(Reason)) -> IO(Unit):
  statusChecked(~Reason, ~G, ~details, events, parent, model, url, timestamp, metadata, body, Response.ok(metadata))


def hookedResponse(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, url: String, timestamp: F64, +metadata: Response.Metadata, body: Http.Body(Reason), result: Result<&2, &2, E, Unit>) -> IO(Unit):
  match result:
    case Fail{cause}:
      do IO<Unit>:
        discarded(~Reason, body)
        thrown(~Reason, ~G, events, parent, model, render(cause), None{})
    case Done{_}: checkedStatus(~Reason, ~G, ~details, events, parent, model, url, timestamp, metadata, body)

# onResponse sees the status and headers before the body is read.
def withResponseHook(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, url: String, timestamp: F64, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, +metadata: Response.Metadata, body: Http.Body(Reason)) -> IO(Unit):
  match hook:
    case None{}: checkedStatus(~Reason, ~G, ~details, events, parent, model, url, timestamp, metadata, body)
    case Some{callback}:
      do IO<Unit>:
        result : Result<&2, &2, E, Unit> <- C.call(T.ResponseInput<T.Model<J()>>, Result<&2, &2, E, Unit>, callback, T.ResponseInput{Http.providerResponse(metadata), model})
        hookedResponse(~Reason, ~E, ~G, ~render, ~details, events, parent, model, url, timestamp, metadata, body, result)

def responded(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, setup: Setup<Reason, E>, response: Fetch.Result_(Reason)) -> IO(Unit):
  match setup response:
    case Setup{model, _, _, _, _, _, _, _} Fail{_}: transportThrown(~Reason, ~G, events, parent, model, "fetch failed")
    case Setup{model, url, _, _, hook, _, _, timestamp} Done{Response.Response{metadata, body}}: withResponseHook(~Reason, ~E, ~G, ~render, ~details, events, parent, model, url, timestamp, hook, metadata, body)

def setupFetch(-Reason: Data, -E: Data, setup: Setup<Reason, E>) -> Fetch.Fetch(Reason):
  match setup:
    case Setup{_, _, _, _, _, fetch, _, _}: fetch

def exchanged(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +setup: Setup<Reason, E>, request: Http.Request, pair: Deadline.Scope<Reason> & Fetch.Signal(Reason)) -> IO(Unit):
  match pair:
    case (scope, signal):
      do IO<Unit>:
        response : Fetch.Result_(Reason) <- Http.post(~Reason, setupFetch(Reason, E, setup), signal, request)
        responded(~Reason, ~E, ~G, ~render, ~details, events, parent, setup, response)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Unit{}

# Upstream passes only the caller's signal to fetch; the native fetch takes a
# deadline scope, which here never expires (the maximum U32 milliseconds).
def exchange(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +setup: Setup<Reason, E>, request: Http.Request) -> IO(Unit):
  do IO<Unit>:
    scope : Deadline.Scope<Reason> <- Deadline.create(Reason, 4294967295, parent)
    exchanged(~Reason, ~E, ~G, ~render, ~details, events, parent, setup, request, Deadline.borrow(Reason, scope))

def requestHeaders(key: String, overrides: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  Http.spread(Http.headerList([R.Property{"authorization", "Bearer " ++ key}, R.Property{"accept", "text/event-stream"}, R.Property{"content-type", "application/json"}]), overrides)

def prepared(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +setup: Setup<Reason, E>, body: Maybe<&2, String>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, url: Result<&2, &2, URL.Error, URL.URL>) -> IO(Unit):
  match body headers url:
    case None{} _ _: thrown(~Reason, ~G, events, parent, setupModel(Reason, E, setup), "Could not serialize the pi-messages payload", None{})
    case _ Fail{_} _: thrown(~Reason, ~G, events, parent, setupModel(Reason, E, setup), "Invalid header", None{})
    case _ _ Fail{_}: thrown(~Reason, ~G, events, parent, setupModel(Reason, E, setup), "Invalid URL", None{})
    case Some{text} Done{fields} Done{address}: exchange(~Reason, ~E, ~G, ~render, ~details, events, parent, setup, Http.Request{address, fields, text})

def send(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +setup: Setup<Reason, E>, payload: J()) -> IO(Unit):
  match setup:
    case Setup{_, +url, +key, +headers, _, _, +urlContext, _}: prepared(~Reason, ~E, ~G, ~render, ~details, events, parent, setup, JsonWire.stringify(payload), requestHeaders(key, headers), URL.parse(urlContext, url))

# `nextPayload !== undefined` replaces the payload.
def payloaded(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +setup: Setup<Reason, E>, original: J(), result: Result<&2, &2, E, Maybe<&2, J()>>) -> IO(Unit):
  match result:
    case Fail{cause}: thrown(~Reason, ~G, events, parent, setupModel(Reason, E, setup), render(cause), None{})
    case Done{replacement}: send(~Reason, ~E, ~G, ~render, ~details, events, parent, setup, Maybe.default(&2, J(), replacement, original))

def withPayloadHook(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +setup: Setup<Reason, E>, +payload: J(), hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>) -> IO(Unit):
  match hook:
    case None{}: send(~Reason, ~E, ~G, ~render, ~details, events, parent, setup, payload)
    case Some{callback}:
      do IO<Unit>:
        result : Result<&2, &2, E, Maybe<&2, J()>> <- C.call(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, E, Maybe<&2, J()>>, callback, T.PayloadInput{payload, setupModel(Reason, E, setup)})
        payloaded(~Reason, ~E, ~G, ~render, ~details, events, parent, setup, payload, result)

def trimTrailingSlashes(reversed: String) -> String:
  match reversed:
    case SCon{'/', rest}: trimTrailingSlashes(rest)
    case other: String.reverse(other)

def debugQuery(debug: Maybe<&2, Bool>) -> String:
  match debug:
    case Some{True{}}: "?debug=1"
    case _: ""

def requestUrl(model: T.Model<J()>, debug: Maybe<&2, Bool>) -> String:
  match model:
    case T.Model{_, _, _, _, base, _, _, _, _, _, _, _, _, _, _, _}: trimTrailingSlashes(String.reverse(base)) ++ "/messages" ++ debugQuery(debug)

def missingKey(model: T.Model<J()>) -> String:
  "No API key provided for provider \"" ++ modelProvider(model) ++ "\""

def keyed(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, ~details: J() -> G, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, key: Maybe<&2, String>, requestFetch: Fetch.Fetch(Reason), urlContext: URL.Context, context: J(), headers: Maybe<&2, T.ProviderHeaders()>, env: Maybe<&2, T.ProviderEnv()>, temperature: Maybe<&2, F64>, maxTokens: Maybe<&2, F64>, reasoning: Maybe<&2, T.ThinkingLevel>, retention: Maybe<&2, T.CacheRetention>, sessionId: Maybe<&2, String>, choice: Maybe<&2, PiMessagesToolChoice>, debug: Maybe<&2, Bool>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>) -> IO(Unit):
  match key:
    case None{}: thrown(~Reason, ~G, events, parent, model, missingKey(model), None{})
    case Some{SNil{}}: thrown(~Reason, ~G, events, parent, model, missingKey(model), None{})
    case Some{value}:
      do IO<Unit>:
        timestamp : F64 <- Date.now()
        resolved : Maybe<&2, T.CacheRetention> <- resolveCacheRetention(retention, env)
        withPayloadHook(~Reason, ~E, ~G, ~render, ~details, events, parent, Setup{model, requestUrl(model, debug), value, headers, onResponse, requestFetch, urlContext, timestamp}, payloadJson(T.modelId(model), context, optionsJson(temperature, maxTokens, reasoning, resolved, sessionId, choice)), onPayload)

# upstream stream. The caller supplies the default fetch (upstream
# globalThis.fetch) and the request's abort signal; events go to `events`,
# which the terminal done/error event completes.
def stream(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, ~details: J() -> G, ~diagnosticDetails: G -> V.Value, ~toolDetails: D -> V.Value, +events: EventStream(G), fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options(Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), E)) -> IO(Unit):
  match options:
    case PiMessagesOptions{T.StreamOptions{_, _, key, custom, env, onPayload, onResponse, headers, _, _, _, temperature, _, maxTokens, _, retention, sessionId, _, _}, reasoning, choice, debug}:
      serialized = contextJson(~G, ~D, ~diagnosticDetails, ~toolDetails, context)
      keyed(~Reason, ~E, ~G, ~render, ~details, events, parent, model, key, Maybe.default(&2, Fetch.Fetch(Reason), custom, fetch), urlContext, serialized, headers, env, temperature, maxTokens, reasoning, retention, sessionId, choice, debug, onPayload, onResponse)

# upstream streamSimple.
def streamSimple(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, ~details: J() -> G, ~diagnosticDetails: G -> V.Value, ~toolDetails: D -> V.Value, +events: EventStream(G), fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Maybe<&2, T.SimpleStreamOptions<J(), Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), E>>, debug: Maybe<&2, Bool>) -> IO(Unit):
  stream(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, ~details, ~diagnosticDetails, ~toolDetails, events, fetch, urlContext, parent, model, context, streamSimpleOptions(Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), E, options, debug))

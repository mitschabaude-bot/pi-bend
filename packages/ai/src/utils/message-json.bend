import Base
import ../types.bend as T
import ./diagnostics.bend as Diagnostics
import ./schema-json.bend as SchemaJson
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/json.bend as Decode

# The JSON shape of pi-ai messages and streaming events, as JSON.stringify
# renders the upstream objects: literal `type`/`role` discriminators, optional
# members omitted when absent. Generic details are rendered by the caller.

def field(key: String, value: V.Value, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  R.Property{key, value} <> rest

def optional(key: String, value: Maybe<&2, V.Value>, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match value:
    case None{}: rest
    case Some{value}: R.Property{key, value} <> rest

def text(value: String) -> V.Value: V.Text{value}
def number(value: F64) -> V.Value: V.Number{value}
def boolean(value: Bool) -> V.Value: V.Boolean{value}
def object(fields: List<&2, R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}

def optionalText(key: String, value: Maybe<&2, String>, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  optional(key, Maybe.map(&2, String, V.Value, text, value), rest)

def optionalNumber(key: String, value: Maybe<&2, F64>, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  optional(key, Maybe.map(&2, F64, V.Value, number, value), rest)

def optionalBoolean(key: String, value: Maybe<&2, Bool>, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  optional(key, Maybe.map(&2, Bool, V.Value, boolean, value), rest)

# Content
# -------

def textContent(value: T.TextContent) -> V.Value:
  match value:
    case T.TextContent{value, signature}: object(field("type", V.Text{"text"}, field("text", V.Text{value}, optionalText("textSignature", signature, Nil{}))))

def thinkingContent(value: T.ThinkingContent) -> V.Value:
  match value:
    case T.ThinkingContent{thinking, signature, redacted}: object(field("type", V.Text{"thinking"}, field("thinking", V.Text{thinking}, optionalText("thinkingSignature", signature, optionalBoolean("redacted", redacted, Nil{})))))

def imageContent(value: T.ImageContent) -> V.Value:
  match value:
    case T.ImageContent{data, mimeType}: object(field("type", V.Text{"image"}, field("data", V.Text{data}, field("mimeType", V.Text{mimeType}, Nil{}))))

def toolCall(value: T.ToolCall<V.Value>) -> V.Value:
  match value:
    case T.ToolCall{id, name, arguments, thoughtSignature, namespace}: object(field("type", V.Text{"toolCall"}, field("id", V.Text{id}, field("name", V.Text{name}, field("arguments", arguments, optionalText("thoughtSignature", thoughtSignature, optionalText("namespace", namespace, Nil{})))))))

def assistantContent(value: T.AssistantContent<V.Value>) -> V.Value:
  match value:
    case T.AssistantText{content}: textContent(content)
    case T.AssistantThinking{content}: thinkingContent(content)
    case T.AssistantToolCall{call}: toolCall(call)

def assistantContents(values: List<&2, T.AssistantContent<V.Value>>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: assistantContent(value) <> assistantContents(rest)

def textImageContent(value: T.TextImageContent) -> V.Value:
  match value:
    case T.TextImageText{content}: textContent(content)
    case T.TextImageImage{content}: imageContent(content)

def textImageContents(values: List<&2, T.TextImageContent>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: textImageContent(value) <> textImageContents(rest)

def userContent(value: T.UserContent) -> V.Value:
  match value:
    case T.UserText{value}: V.Text{value}
    case T.UserBlocks{blocks}: V.ArrayValue{textImageContents(blocks)}

def textContents(values: List<&2, T.TextContent>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: textContent(value) <> textContents(rest)

def systemContent(value: T.SystemContent) -> V.Value:
  match value:
    case T.SystemText{value}: V.Text{value}
    case T.SystemBlocks{blocks}: V.ArrayValue{textContents(blocks)}

# Usage
# -----

def usageCost(value: T.UsageCost) -> V.Value:
  match value:
    case T.UsageCost{input, output, cacheRead, cacheWrite, total}: object(field("input", number(input), field("output", number(output), field("cacheRead", number(cacheRead), field("cacheWrite", number(cacheWrite), field("total", number(total), Nil{}))))))

def usage(value: T.Usage) -> V.Value:
  match value:
    case T.Usage{input, output, cacheRead, cacheWrite, cacheWrite1h, reasoning, totalTokens, cost}: object(field("input", number(input), field("output", number(output), field("cacheRead", number(cacheRead), field("cacheWrite", number(cacheWrite), optionalNumber("cacheWrite1h", cacheWrite1h, optionalNumber("reasoning", reasoning, field("totalTokens", number(totalTokens), field("cost", usageCost(cost), Nil{})))))))))

# Assistant messages
# ------------------

def stopReason(value: T.StopReason) -> String:
  match value:
    case T.Pending{}: "pending"
    case T.Stop{}: "stop"
    case T.Length{}: "length"
    case T.ToolUse{}: "toolUse"
    case T.Error{}: "error"
    case T.Aborted{}: "aborted"
    case T.Deferred{}: "deferred"

# Provider JSON values convert to schema values through a finite work stack,
# mirroring schema-json.bend in the other direction.
type Task is Data:
  Value{value: T.JsonValue}
  ArrayItems{remaining: List<&2, T.JsonValue>, built: List<&2, V.Value>}
  ArrayResult{remaining: List<&2, T.JsonValue>, built: List<&2, V.Value>}
  ObjectItems{remaining: List<&2, R.Property<T.JsonValue>>, built: R.Record<V.Value>}
  ObjectResult{key: String, remaining: List<&2, R.Property<T.JsonValue>>, built: R.Record<V.Value>}

@unsafe
def convert(tasks: List<&2, Task>, completed: V.Value) -> V.Value:
  match tasks:
    case Nil{}: completed
    case Value{T.JsonNull{}} <> rest: convert(rest, V.Null{})
    case Value{T.JsonBoolean{value}} <> rest: convert(rest, V.Boolean{value})
    case Value{T.JsonNumber{value}} <> rest: convert(rest, V.Number{value})
    case Value{T.JsonString{value}} <> rest: convert(rest, V.Text{value})
    case Value{T.JsonArray{values}} <> rest: convert(ArrayItems{values, Nil{}} <> rest, completed)
    case Value{T.JsonObject{properties}} <> rest: convert(ObjectItems{R.entries(T.JsonValue, properties), R.new(V.Value)} <> rest, completed)
    case ArrayItems{Nil{}, built} <> rest: convert(rest, V.ArrayValue{List.reverse(&2, V.Value, built)})
    case ArrayItems{head <> tail, built} <> rest: convert(Value{head} <> ArrayResult{tail, built} <> rest, completed)
    case ArrayResult{remaining, built} <> rest: convert(ArrayItems{remaining, completed <> built} <> rest, V.Null{})
    case ObjectItems{Nil{}, built} <> rest: convert(rest, V.ObjectValue{built})
    case ObjectItems{R.Property{key, value} <> tail, built} <> rest: convert(Value{value} <> ObjectResult{key, tail, built} <> rest, completed)
    case ObjectResult{key, remaining, built} <> rest: convert(ObjectItems{remaining, R.set(V.Value, built, key, completed)} <> rest, V.Null{})

def jsonValue(value: T.JsonValue) -> V.Value:
  convert(Value{value} <> Nil{}, V.Null{})

def deferredHandle(value: T.DeferredHandle) -> V.Value:
  match value:
    case T.DeferredHandle{provider, modelId, api, id, expiresAt, pollAfterMs, data}: object(field("provider", text(provider), field("modelId", text(modelId), field("api", text(api), field("id", text(id), optionalNumber("expiresAt", expiresAt, optionalNumber("pollAfterMs", pollAfterMs, optional("data", Maybe.map(&2, T.JsonValue, V.Value, jsonValue, data), Nil{}))))))))

def diagnosticCode(value: Diagnostics.DiagnosticCode) -> V.Value:
  match value:
    case Diagnostics.StringCode{value}: V.Text{value}
    case Diagnostics.NumberCode{value}: V.Number{value}

def diagnosticError(value: Diagnostics.DiagnosticErrorInfo) -> V.Value:
  match value:
    case Diagnostics.DiagnosticErrorInfo{name, message, stack, code}: object(optionalText("name", name, field("message", text(message), optionalText("stack", stack, optional("code", Maybe.map(&2, Diagnostics.DiagnosticCode, V.Value, diagnosticCode, code), Nil{})))))

def diagnostic(~Details: Data, ~details: Details -> V.Value, value: Diagnostics.AssistantMessageDiagnostic<Details>) -> V.Value:
  match value:
    case Diagnostics.AssistantMessageDiagnostic{diagnosticType, timestamp, error, extra}: object(field("type", text(diagnosticType), field("timestamp", number(timestamp), optional("error", Maybe.map(&2, Diagnostics.DiagnosticErrorInfo, V.Value, diagnosticError, error), optional("details", Maybe.map(&2, Details, V.Value, details, extra), Nil{})))))

def diagnostics(~Details: Data, ~details: Details -> V.Value, values: List<&2, Diagnostics.AssistantMessageDiagnostic<Details>>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: diagnostic(~Details, ~details, value) <> diagnostics(~Details, ~details, rest)

def assistantMessage(~Details: Data, ~details: Details -> V.Value, value: T.AssistantMessage<V.Value, Details>) -> V.Value:
  match value:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, providerThinkingLevel, diagnosticList, usageValue, stop, deferred, errorMessage, rawStopReason, endTurn, timestamp}:
      object(field("role", text("assistant"), field("content", V.ArrayValue{assistantContents(content)}, field("api", text(api), field("provider", text(provider), field("model", text(model), optionalText("responseModel", responseModel, optionalText("responseId", responseId, optionalText("providerThinkingLevel", providerThinkingLevel, optional("diagnostics", Maybe.map(&2, List<&2, Diagnostics.AssistantMessageDiagnostic<Details>>, V.Value, values => V.ArrayValue{diagnostics(~Details, ~details, values)}, diagnosticList), field("usage", usage(usageValue), field("stopReason", text(stopReason(stop)), optional("deferred", Maybe.map(&2, T.DeferredHandle, V.Value, deferredHandle, deferred), optionalText("errorMessage", errorMessage, optionalText("rawStopReason", rawStopReason, optionalBoolean("endTurn", endTurn, field("timestamp", number(timestamp), Nil{})))))))))))))))))

# Other messages
# --------------

def userMessage(value: T.UserMessage) -> V.Value:
  match value:
    case T.UserMessage{content, timestamp}: object(field("role", text("user"), field("content", userContent(content), field("timestamp", number(timestamp), Nil{}))))

def toolResultMessage(~Details: Data, ~details: Details -> V.Value, value: T.ToolResultMessage<Details>) -> V.Value:
  match value:
    case T.ToolResultMessage{toolCallId, toolName, content, extra, usageValue, isError, timestamp}: object(field("role", text("toolResult"), field("toolCallId", text(toolCallId), field("toolName", text(toolName), field("content", V.ArrayValue{textImageContents(content)}, optional("details", Maybe.map(&2, Details, V.Value, details, extra), optional("usage", Maybe.map(&2, T.Usage, V.Value, usage, usageValue), field("isError", boolean(isError), field("timestamp", number(timestamp), Nil{})))))))))

def strictness(value: T.SamplingStrictness) -> String:
  match value:
    case T.Prefer{}: "prefer"
    case T.Require{}: "require"

def samplingConfig(value: T.ConstrainedSamplingConfig) -> V.Value:
  match value:
    case T.JsonSchemaSampling{strict}: object(field("type", text("json_schema"), field("strict", text(strictness(strict)), Nil{})))
    case T.GrammarSampling{T.GrammarVariants{lark, regex}}: object(field("type", text("grammar"), field("variants", object(optionalText("openaiLark", lark, optionalText("openaiRegex", regex, Nil{}))), Nil{})))

def constrainedSampling(value: T.ToolConstrainedSampling) -> V.Value:
  match value:
    case T.SamplingDisabled{}: V.Boolean{False{}}
    case T.SamplingConfigured{config}: samplingConfig(config)

def tool(value: T.Tool<V.Value>) -> V.Value:
  match value:
    case T.Tool{name, description, parameters, sampling}: object(field("name", text(name), field("description", text(description), field("parameters", parameters, optional("constrainedSampling", Maybe.map(&2, T.ToolConstrainedSampling, V.Value, constrainedSampling, sampling), Nil{})))))

def tools(values: List<&2, T.Tool<V.Value>>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: tool(value) <> tools(rest)

def toolReferences(values: List<&2, T.ToolReference>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case T.ToolReference{name} <> rest: object(field("name", text(name), Nil{})) <> toolReferences(rest)

def sectionEntries(entries: List<&2, R.Property<Maybe<&2, String>>>) -> List<&2, R.Property<V.Value>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, None{}} <> rest: R.Property{name, V.Null{}} <> sectionEntries(rest)
    case R.Property{name, Some{value}} <> rest: R.Property{name, V.Text{value}} <> sectionEntries(rest)

def sections(value: R.Record<Maybe<&2, String>>) -> V.Value:
  match value:
    case R.Record{entries}: V.ObjectValue{R.Record{sectionEntries(entries)}}

def systemMessage(value: T.SystemMessage<V.Value>) -> V.Value:
  match value:
    case T.SystemMessage{content, sectionValues, toolsAdded, toolsRemoved, timestamp}: object(field("role", text("system"), field("content", systemContent(content), optional("sections", Maybe.map(&2, R.Record<Maybe<&2, String>>, V.Value, sections, sectionValues), optional("toolsAdded", Maybe.map(&2, List<&2, T.Tool<V.Value>>, V.Value, values => V.ArrayValue{tools(values)}, toolsAdded), optional("toolsRemoved", Maybe.map(&2, List<&2, T.ToolReference>, V.Value, values => V.ArrayValue{toolReferences(values)}, toolsRemoved), field("timestamp", number(timestamp), Nil{})))))))

def message(~DiagnosticDetails: Data, ~ToolDetails: Data, ~diagnosticDetails: DiagnosticDetails -> V.Value, ~toolDetails: ToolDetails -> V.Value, value: T.Message<V.Value, V.Value, DiagnosticDetails, ToolDetails>) -> V.Value:
  match value:
    case T.System{value}: systemMessage(value)
    case T.User{value}: userMessage(value)
    case T.Assistant{value}: assistantMessage(~DiagnosticDetails, ~diagnosticDetails, value)
    case T.ToolResult{value}: toolResultMessage(~ToolDetails, ~toolDetails, value)

# Streaming events
# ----------------

def doneReason(value: T.DoneReason) -> String:
  match value:
    case T.DoneStop{}: "stop"
    case T.DoneLength{}: "length"
    case T.DoneToolUse{}: "toolUse"
    case T.DoneDeferred{}: "deferred"

def errorReason(value: T.ErrorReason) -> String:
  match value:
    case T.ErrorAborted{}: "aborted"
    case T.ErrorError{}: "error"

# The wire event including its cumulative `partial`; callers that stream
# deltas without snapshots use the json-event projection instead.
def assistantMessageEvent(~Details: Data, ~details: Details -> V.Value, value: T.AssistantMessageEvent<V.Value, Details>) -> V.Value:
  match value:
    case T.Start{partial}: object(field("type", text("start"), field("partial", assistantMessage(~Details, ~details, partial), Nil{})))
    case T.TextStart{index, partial}: object(field("type", text("text_start"), field("contentIndex", number(index), field("partial", assistantMessage(~Details, ~details, partial), Nil{}))))
    case T.TextDelta{index, delta, partial}: object(field("type", text("text_delta"), field("contentIndex", number(index), field("delta", text(delta), field("partial", assistantMessage(~Details, ~details, partial), Nil{})))))
    case T.TextEnd{index, content, partial}: object(field("type", text("text_end"), field("contentIndex", number(index), field("content", text(content), field("partial", assistantMessage(~Details, ~details, partial), Nil{})))))
    case T.ThinkingStart{index, partial}: object(field("type", text("thinking_start"), field("contentIndex", number(index), field("partial", assistantMessage(~Details, ~details, partial), Nil{}))))
    case T.ThinkingDelta{index, delta, partial}: object(field("type", text("thinking_delta"), field("contentIndex", number(index), field("delta", text(delta), field("partial", assistantMessage(~Details, ~details, partial), Nil{})))))
    case T.ThinkingEnd{index, content, partial}: object(field("type", text("thinking_end"), field("contentIndex", number(index), field("content", text(content), field("partial", assistantMessage(~Details, ~details, partial), Nil{})))))
    case T.ToolcallStart{index, partial}: object(field("type", text("toolcall_start"), field("contentIndex", number(index), field("partial", assistantMessage(~Details, ~details, partial), Nil{}))))
    case T.ToolcallDelta{index, delta, partial}: object(field("type", text("toolcall_delta"), field("contentIndex", number(index), field("delta", text(delta), field("partial", assistantMessage(~Details, ~details, partial), Nil{})))))
    case T.ToolcallEnd{index, call, partial}: object(field("type", text("toolcall_end"), field("contentIndex", number(index), field("toolCall", toolCall(call), field("partial", assistantMessage(~Details, ~details, partial), Nil{})))))
    case T.StreamDone{reason, final}: object(field("type", text("done"), field("reason", text(doneReason(reason)), field("message", assistantMessage(~Details, ~details, final), Nil{}))))
    case T.StreamError{reason, failed}: object(field("type", text("error"), field("reason", text(errorReason(reason)), field("error", assistantMessage(~Details, ~details, failed), Nil{}))))

# Decoding
# --------
# JSON.parse hands upstream the stored objects unchecked; the port reads the
# same shapes into the typed messages, reporting the first mismatch by path.
# Usage token/cost members absent from sessions written before they existed
# read as zero, as their absence is invisible to upstream's readers.

def Decoded(-A: Data) -> Data: Result<&2, &2, Decode.Error, A>

def decodeBoolean(value: V.Value) -> Decoded(Bool):
  match value:
    case V.Boolean{flag}: Done{flag}
    case _: Fail{Decode.WrongType{Nil{}, "boolean"}}

def tagged(fields: R.Record<V.Value>, +key: String) -> Decoded(String):
  Decode.required(String, fields, key, Decode.string)

def textContentFields(+fields: R.Record<V.Value>) -> Decoded(T.TextContent):
  do Result<&2, &2, Decode.Error, T.TextContent>:
    body : String <- Decode.required(String, fields, "text", Decode.string)
    signature : Maybe<&2, String> <- Decode.optional(String, fields, "textSignature", Decode.string)
    return T.TextContent{body, signature}

def decodeTextContent(value: V.Value) -> Decoded(T.TextContent):
  Result.bind(&2, &2, Decode.Error, R.Record<V.Value>, T.TextContent, Decode.object(value), fields => textContentFields(fields))

def thinkingContentFields(+fields: R.Record<V.Value>) -> Decoded(T.ThinkingContent):
  do Result<&2, &2, Decode.Error, T.ThinkingContent>:
    body : String <- Decode.required(String, fields, "thinking", Decode.string)
    signature : Maybe<&2, String> <- Decode.optional(String, fields, "thinkingSignature", Decode.string)
    redacted : Maybe<&2, Bool> <- Decode.optional(Bool, fields, "redacted", decodeBoolean)
    return T.ThinkingContent{body, signature, redacted}

def imageContentFields(+fields: R.Record<V.Value>) -> Decoded(T.ImageContent):
  do Result<&2, &2, Decode.Error, T.ImageContent>:
    data : String <- Decode.required(String, fields, "data", Decode.string)
    mimeType : String <- Decode.required(String, fields, "mimeType", Decode.string)
    return T.ImageContent{data, mimeType}

def toolCallFields(+fields: R.Record<V.Value>) -> Decoded(T.ToolCall<V.Value>):
  do Result<&2, &2, Decode.Error, T.ToolCall<V.Value>>:
    id : String <- Decode.required(String, fields, "id", Decode.string)
    name : String <- Decode.required(String, fields, "name", Decode.string)
    arguments : V.Value <- Decode.required(V.Value, fields, "arguments", item => Done{item})
    thoughtSignature : Maybe<&2, String> <- Decode.optional(String, fields, "thoughtSignature", Decode.string)
    namespace : Maybe<&2, String> <- Decode.optional(String, fields, "namespace", Decode.string)
    return T.ToolCall{id, name, arguments, thoughtSignature, namespace}

def assistantContentOf(+kind: String, fields: R.Record<V.Value>) -> Decoded(T.AssistantContent<V.Value>):
  match kind:
    case "text": Result.map(&2, &2, Decode.Error, T.TextContent, T.AssistantContent<V.Value>, item => T.AssistantText{item}, textContentFields(fields))
    case "thinking": Result.map(&2, &2, Decode.Error, T.ThinkingContent, T.AssistantContent<V.Value>, item => T.AssistantThinking{item}, thinkingContentFields(fields))
    case "toolCall": Result.map(&2, &2, Decode.Error, T.ToolCall<V.Value>, T.AssistantContent<V.Value>, item => T.AssistantToolCall{item}, toolCallFields(fields))
    case _: Fail{Decode.InvalidValue{Decode.Field{"type"} <> Nil{}, "text, thinking or toolCall"}}

def decodeAssistantContent(value: V.Value) -> Decoded(T.AssistantContent<V.Value>):
  do Result<&2, &2, Decode.Error, T.AssistantContent<V.Value>>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    kind : String <- tagged(fields, "type")
    assistantContentOf(kind, fields)

def textImageContentOf(+kind: String, fields: R.Record<V.Value>) -> Decoded(T.TextImageContent):
  match kind:
    case "text": Result.map(&2, &2, Decode.Error, T.TextContent, T.TextImageContent, item => T.TextImageText{item}, textContentFields(fields))
    case "image": Result.map(&2, &2, Decode.Error, T.ImageContent, T.TextImageContent, item => T.TextImageImage{item}, imageContentFields(fields))
    case _: Fail{Decode.InvalidValue{Decode.Field{"type"} <> Nil{}, "text or image"}}

def decodeTextImageContent(value: V.Value) -> Decoded(T.TextImageContent):
  do Result<&2, &2, Decode.Error, T.TextImageContent>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    kind : String <- tagged(fields, "type")
    textImageContentOf(kind, fields)

def decodeUserContent(value: V.Value) -> Decoded(T.UserContent):
  match value:
    case V.Text{body}: Done{T.UserText{body}}
    case V.ArrayValue{values}: Result.map(&2, &2, Decode.Error, List<&2, T.TextImageContent>, T.UserContent, blocks => T.UserBlocks{blocks}, Decode.items(~T.TextImageContent, ~decodeTextImageContent, values, 0n))
    case _: Fail{Decode.WrongType{Nil{}, "string or array"}}

def decodeSystemContent(value: V.Value) -> Decoded(T.SystemContent):
  match value:
    case V.Text{body}: Done{T.SystemText{body}}
    case V.ArrayValue{values}: Result.map(&2, &2, Decode.Error, List<&2, T.TextContent>, T.SystemContent, blocks => T.SystemBlocks{blocks}, Decode.items(~T.TextContent, ~decodeTextContent, values, 0n))
    case _: Fail{Decode.WrongType{Nil{}, "string or array"}}

# Usage

def numberOr(fields: R.Record<V.Value>, +key: String, fallback: F64) -> Decoded(F64):
  Result.map(&2, &2, Decode.Error, Maybe<&2, F64>, F64, found => Maybe.default(&2, F64, found, fallback), Decode.optional(F64, fields, key, Decode.number))

def zeroCost() -> T.UsageCost: T.UsageCost{U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0)}

def decodeUsageCost(value: V.Value) -> Decoded(T.UsageCost):
  do Result<&2, &2, Decode.Error, T.UsageCost>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    input : F64 <- numberOr(fields, "input", U32.to_f64(0))
    output : F64 <- numberOr(fields, "output", U32.to_f64(0))
    cacheRead : F64 <- numberOr(fields, "cacheRead", U32.to_f64(0))
    cacheWrite : F64 <- numberOr(fields, "cacheWrite", U32.to_f64(0))
    total : F64 <- numberOr(fields, "total", U32.to_f64(0))
    return T.UsageCost{input, output, cacheRead, cacheWrite, total}

def decodeUsage(value: V.Value) -> Decoded(T.Usage):
  do Result<&2, &2, Decode.Error, T.Usage>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    input : F64 <- Decode.required(F64, fields, "input", Decode.number)
    output : F64 <- Decode.required(F64, fields, "output", Decode.number)
    cacheRead : F64 <- Decode.required(F64, fields, "cacheRead", Decode.number)
    cacheWrite : F64 <- Decode.required(F64, fields, "cacheWrite", Decode.number)
    cacheWrite1h : Maybe<&2, F64> <- Decode.optional(F64, fields, "cacheWrite1h", Decode.number)
    reasoning : Maybe<&2, F64> <- Decode.optional(F64, fields, "reasoning", Decode.number)
    totalTokens : F64 <- numberOr(fields, "totalTokens", U32.to_f64(0))
    cost : Maybe<&2, T.UsageCost> <- Decode.optional(T.UsageCost, fields, "cost", decodeUsageCost)
    return T.Usage{input, output, cacheRead, cacheWrite, cacheWrite1h, reasoning, totalTokens, Maybe.default(&2, T.UsageCost, cost, zeroCost())}

# Assistant messages

def stopReasonOf(+value: String) -> Decoded(T.StopReason):
  match value:
    case "pending": Done{T.Pending{}}
    case "stop": Done{T.Stop{}}
    case "length": Done{T.Length{}}
    case "toolUse": Done{T.ToolUse{}}
    case "error": Done{T.Error{}}
    case "aborted": Done{T.Aborted{}}
    case "deferred": Done{T.Deferred{}}
    case _: Fail{Decode.InvalidValue{Nil{}, "stop reason"}}

def decodeStopReason(value: V.Value) -> Decoded(T.StopReason):
  Result.bind(&2, &2, Decode.Error, String, T.StopReason, Decode.string(value), reason => stopReasonOf(reason))

def decodeJsonValue(value: V.Value) -> Decoded(T.JsonValue): Done{SchemaJson.toJson(value)}

def decodeDeferredHandle(value: V.Value) -> Decoded(T.DeferredHandle):
  do Result<&2, &2, Decode.Error, T.DeferredHandle>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    provider : String <- Decode.required(String, fields, "provider", Decode.string)
    modelId : String <- Decode.required(String, fields, "modelId", Decode.string)
    api : String <- Decode.required(String, fields, "api", Decode.string)
    id : String <- Decode.required(String, fields, "id", Decode.string)
    expiresAt : Maybe<&2, F64> <- Decode.optional(F64, fields, "expiresAt", Decode.number)
    pollAfterMs : Maybe<&2, F64> <- Decode.optional(F64, fields, "pollAfterMs", Decode.number)
    data : Maybe<&2, T.JsonValue> <- Decode.optional(T.JsonValue, fields, "data", decodeJsonValue)
    return T.DeferredHandle{provider, modelId, api, id, expiresAt, pollAfterMs, data}

def decodeDiagnosticCode(value: V.Value) -> Decoded(Diagnostics.DiagnosticCode):
  match value:
    case V.Text{body}: Done{Diagnostics.StringCode{body}}
    case V.Number{scalar}: Done{Diagnostics.NumberCode{scalar}}
    case _: Fail{Decode.WrongType{Nil{}, "string or number"}}

def decodeDiagnosticError(value: V.Value) -> Decoded(Diagnostics.DiagnosticErrorInfo):
  do Result<&2, &2, Decode.Error, Diagnostics.DiagnosticErrorInfo>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    name : Maybe<&2, String> <- Decode.optional(String, fields, "name", Decode.string)
    description : String <- Decode.required(String, fields, "message", Decode.string)
    stack : Maybe<&2, String> <- Decode.optional(String, fields, "stack", Decode.string)
    code : Maybe<&2, Diagnostics.DiagnosticCode> <- Decode.optional(Diagnostics.DiagnosticCode, fields, "code", decodeDiagnosticCode)
    return Diagnostics.DiagnosticErrorInfo{name, description, stack, code}

def decodeDiagnostic(~Details: Data, ~details: V.Value -> Decoded(Details), value: V.Value) -> Decoded(Diagnostics.AssistantMessageDiagnostic<Details>):
  do Result<&2, &2, Decode.Error, Diagnostics.AssistantMessageDiagnostic<Details>>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    kind : String <- tagged(fields, "type")
    timestamp : F64 <- Decode.required(F64, fields, "timestamp", Decode.number)
    error : Maybe<&2, Diagnostics.DiagnosticErrorInfo> <- Decode.optional(Diagnostics.DiagnosticErrorInfo, fields, "error", decodeDiagnosticError)
    extra : Maybe<&2, Details> <- Decode.optional(Details, fields, "details", details)
    return Diagnostics.AssistantMessageDiagnostic{kind, timestamp, error, extra}

def decodeAssistantMessage(~Details: Data, ~details: V.Value -> Decoded(Details), value: V.Value) -> Decoded(T.AssistantMessage<V.Value, Details>):
  do Result<&2, &2, Decode.Error, T.AssistantMessage<V.Value, Details>>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    content : List<&2, T.AssistantContent<V.Value>> <- Decode.required(List<&2, T.AssistantContent<V.Value>>, fields, "content", item => Decode.list(~T.AssistantContent<V.Value>, ~decodeAssistantContent, item))
    api : String <- Decode.required(String, fields, "api", Decode.string)
    provider : String <- Decode.required(String, fields, "provider", Decode.string)
    model : String <- Decode.required(String, fields, "model", Decode.string)
    responseModel : Maybe<&2, String> <- Decode.optional(String, fields, "responseModel", Decode.string)
    responseId : Maybe<&2, String> <- Decode.optional(String, fields, "responseId", Decode.string)
    providerThinkingLevel : Maybe<&2, String> <- Decode.optional(String, fields, "providerThinkingLevel", Decode.string)
    diagnosticList : Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<Details>>> <- Decode.optional(List<&2, Diagnostics.AssistantMessageDiagnostic<Details>>, fields, "diagnostics", item => Decode.list(~Diagnostics.AssistantMessageDiagnostic<Details>, ~(entry => decodeDiagnostic(~Details, ~details, entry)), item))
    usageValue : T.Usage <- Decode.required(T.Usage, fields, "usage", decodeUsage)
    stop : T.StopReason <- Decode.required(T.StopReason, fields, "stopReason", decodeStopReason)
    deferred : Maybe<&2, T.DeferredHandle> <- Decode.optional(T.DeferredHandle, fields, "deferred", decodeDeferredHandle)
    errorMessage : Maybe<&2, String> <- Decode.optional(String, fields, "errorMessage", Decode.string)
    rawStopReason : Maybe<&2, String> <- Decode.optional(String, fields, "rawStopReason", Decode.string)
    endTurn : Maybe<&2, Bool> <- Decode.optional(Bool, fields, "endTurn", decodeBoolean)
    timestamp : F64 <- Decode.required(F64, fields, "timestamp", Decode.number)
    return T.AssistantMessage{content, api, provider, model, responseModel, responseId, providerThinkingLevel, diagnosticList, usageValue, stop, deferred, errorMessage, rawStopReason, endTurn, timestamp}

# Other messages

def decodeUserMessage(value: V.Value) -> Decoded(T.UserMessage):
  do Result<&2, &2, Decode.Error, T.UserMessage>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    content : T.UserContent <- Decode.required(T.UserContent, fields, "content", decodeUserContent)
    timestamp : F64 <- Decode.required(F64, fields, "timestamp", Decode.number)
    return T.UserMessage{content, timestamp}

def decodeToolResultMessage(~Details: Data, ~details: V.Value -> Decoded(Details), value: V.Value) -> Decoded(T.ToolResultMessage<Details>):
  do Result<&2, &2, Decode.Error, T.ToolResultMessage<Details>>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    toolCallId : String <- Decode.required(String, fields, "toolCallId", Decode.string)
    toolName : String <- Decode.required(String, fields, "toolName", Decode.string)
    content : List<&2, T.TextImageContent> <- Decode.required(List<&2, T.TextImageContent>, fields, "content", item => Decode.list(~T.TextImageContent, ~decodeTextImageContent, item))
    extra : Maybe<&2, Details> <- Decode.optional(Details, fields, "details", details)
    usageValue : Maybe<&2, T.Usage> <- Decode.optional(T.Usage, fields, "usage", decodeUsage)
    isError : Bool <- Decode.required(Bool, fields, "isError", decodeBoolean)
    timestamp : F64 <- Decode.required(F64, fields, "timestamp", Decode.number)
    return T.ToolResultMessage{toolCallId, toolName, content, extra, usageValue, isError, timestamp}

def strictnessOf(+value: String) -> Decoded(T.SamplingStrictness):
  match value:
    case "prefer": Done{T.Prefer{}}
    case "require": Done{T.Require{}}
    case _: Fail{Decode.InvalidValue{Nil{}, "prefer or require"}}

def samplingConfigOf(+kind: String, fields: R.Record<V.Value>) -> Decoded(T.ConstrainedSamplingConfig):
  match kind:
    case "json_schema":
      Result.map(&2, &2, Decode.Error, T.SamplingStrictness, T.ConstrainedSamplingConfig, strict => T.JsonSchemaSampling{strict}, Decode.required(T.SamplingStrictness, fields, "strict", item => Result.bind(&2, &2, Decode.Error, String, T.SamplingStrictness, Decode.string(item), strict => strictnessOf(strict))))
    case "grammar":
      do Result<&2, &2, Decode.Error, T.ConstrainedSamplingConfig>:
        +variants : R.Record<V.Value> <- Decode.required(R.Record<V.Value>, fields, "variants", Decode.object)
        lark : Maybe<&2, String> <- Decode.located(Maybe<&2, String>, Decode.optional(String, variants, "openaiLark", Decode.string), Decode.Field{"variants"})
        regex : Maybe<&2, String> <- Decode.located(Maybe<&2, String>, Decode.optional(String, variants, "openaiRegex", Decode.string), Decode.Field{"variants"})
        return T.GrammarSampling{T.GrammarVariants{lark, regex}}
    case _: Fail{Decode.InvalidValue{Decode.Field{"type"} <> Nil{}, "json_schema or grammar"}}

def decodeConstrainedSampling(value: V.Value) -> Decoded(T.ToolConstrainedSampling):
  match value:
    case V.Boolean{False{}}: Done{T.SamplingDisabled{}}
    case V.ObjectValue{+fields}: Result.map(&2, &2, Decode.Error, T.ConstrainedSamplingConfig, T.ToolConstrainedSampling, config => T.SamplingConfigured{config}, Result.bind(&2, &2, Decode.Error, String, T.ConstrainedSamplingConfig, tagged(fields, "type"), kind => samplingConfigOf(kind, fields)))
    case _: Fail{Decode.WrongType{Nil{}, "false or object"}}

def decodeTool(value: V.Value) -> Decoded(T.Tool<V.Value>):
  do Result<&2, &2, Decode.Error, T.Tool<V.Value>>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    name : String <- Decode.required(String, fields, "name", Decode.string)
    description : String <- Decode.required(String, fields, "description", Decode.string)
    parameters : V.Value <- Decode.required(V.Value, fields, "parameters", item => Done{item})
    sampling : Maybe<&2, T.ToolConstrainedSampling> <- Decode.optional(T.ToolConstrainedSampling, fields, "constrainedSampling", decodeConstrainedSampling)
    return T.Tool{name, description, parameters, sampling}

def decodeToolReference(value: V.Value) -> Decoded(T.ToolReference):
  do Result<&2, &2, Decode.Error, T.ToolReference>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    name : String <- Decode.required(String, fields, "name", Decode.string)
    return T.ToolReference{name}

def sectionValue(value: V.Value) -> Decoded(Maybe<&2, String>):
  match value:
    case V.Null{}: Done{None{}}
    case V.Text{body}: Done{Some{body}}
    case _: Fail{Decode.WrongType{Nil{}, "string or null"}}

def sectionProperties(entries: List<&2, R.Property<V.Value>>) -> Decoded(List<&2, R.Property<Maybe<&2, String>>>):
  match entries:
    case Nil{}: Done{Nil{}}
    case R.Property{+name, value} <> rest:
      do Result<&2, &2, Decode.Error, List<&2, R.Property<Maybe<&2, String>>>>:
        section : Maybe<&2, String> <- Decode.located(Maybe<&2, String>, sectionValue(value), Decode.Field{name})
        others : List<&2, R.Property<Maybe<&2, String>>> <- sectionProperties(rest)
        return R.Property{name, section} <> others

def decodeSections(value: V.Value) -> Decoded(R.Record<Maybe<&2, String>>):
  match value:
    case V.ObjectValue{R.Record{entries}}: Result.map(&2, &2, Decode.Error, List<&2, R.Property<Maybe<&2, String>>>, R.Record<Maybe<&2, String>>, properties => R.Record{properties}, sectionProperties(entries))
    case _: Fail{Decode.WrongType{Nil{}, "object"}}

def decodeSystemMessage(value: V.Value) -> Decoded(T.SystemMessage<V.Value>):
  do Result<&2, &2, Decode.Error, T.SystemMessage<V.Value>>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    content : T.SystemContent <- Decode.required(T.SystemContent, fields, "content", decodeSystemContent)
    sectionValues : Maybe<&2, R.Record<Maybe<&2, String>>> <- Decode.optional(R.Record<Maybe<&2, String>>, fields, "sections", decodeSections)
    toolsAdded : Maybe<&2, List<&2, T.Tool<V.Value>>> <- Decode.optional(List<&2, T.Tool<V.Value>>, fields, "toolsAdded", item => Decode.list(~T.Tool<V.Value>, ~decodeTool, item))
    toolsRemoved : Maybe<&2, List<&2, T.ToolReference>> <- Decode.optional(List<&2, T.ToolReference>, fields, "toolsRemoved", item => Decode.list(~T.ToolReference, ~decodeToolReference, item))
    timestamp : F64 <- Decode.required(F64, fields, "timestamp", Decode.number)
    return T.SystemMessage{content, sectionValues, toolsAdded, toolsRemoved, timestamp}

def messageOf(~DiagnosticDetails: Data, ~ToolDetails: Data, ~diagnosticDetails: V.Value -> Decoded(DiagnosticDetails), ~toolDetails: V.Value -> Decoded(ToolDetails), +role: String, value: V.Value) -> Decoded(T.Message<V.Value, V.Value, DiagnosticDetails, ToolDetails>):
  match role:
    case "system": Result.map(&2, &2, Decode.Error, T.SystemMessage<V.Value>, T.Message<V.Value, V.Value, DiagnosticDetails, ToolDetails>, item => T.System{item}, decodeSystemMessage(value))
    case "user": Result.map(&2, &2, Decode.Error, T.UserMessage, T.Message<V.Value, V.Value, DiagnosticDetails, ToolDetails>, item => T.User{item}, decodeUserMessage(value))
    case "assistant": Result.map(&2, &2, Decode.Error, T.AssistantMessage<V.Value, DiagnosticDetails>, T.Message<V.Value, V.Value, DiagnosticDetails, ToolDetails>, item => T.Assistant{item}, decodeAssistantMessage(~DiagnosticDetails, ~diagnosticDetails, value))
    case "toolResult": Result.map(&2, &2, Decode.Error, T.ToolResultMessage<ToolDetails>, T.Message<V.Value, V.Value, DiagnosticDetails, ToolDetails>, item => T.ToolResult{item}, decodeToolResultMessage(~ToolDetails, ~toolDetails, value))
    case _: Fail{Decode.InvalidValue{Decode.Field{"role"} <> Nil{}, "system, user, assistant or toolResult"}}

# The role of a message object, for callers that dispatch other roles first.
def messageRole(value: V.Value) -> Decoded(String):
  Result.bind(&2, &2, Decode.Error, R.Record<V.Value>, String, Decode.object(value), fields => tagged(fields, "role"))

def decodeMessage(~DiagnosticDetails: Data, ~ToolDetails: Data, ~diagnosticDetails: V.Value -> Decoded(DiagnosticDetails), ~toolDetails: V.Value -> Decoded(ToolDetails), +value: V.Value) -> Decoded(T.Message<V.Value, V.Value, DiagnosticDetails, ToolDetails>):
  Result.bind(&2, &2, Decode.Error, String, T.Message<V.Value, V.Value, DiagnosticDetails, ToolDetails>, messageRole(value), role => messageOf(~DiagnosticDetails, ~ToolDetails, ~diagnosticDetails, ~toolDetails, role, value))

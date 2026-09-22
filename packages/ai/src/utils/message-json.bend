import Base
import ../types.bend as T
import ./diagnostics.bend as Diagnostics
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V

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

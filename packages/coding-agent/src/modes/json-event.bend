import Base
import ../../../agent/src/types.bend as Agent
import ../../../agent/src/agent.bend as Runner
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/message-json.bend as Json
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/f64.bend as F
import ../core/tools/index.bend as Tools
import ../core/tools/read.bend as Read
import ../core/tools/bash.bend as Bash
import ../core/tools/edit.bend as Edit
import ../core/tools/find.bend as Find
import ../core/tools/truncate.bend as Truncate

# Session event shape emitted by the JSON stdout protocol. Cumulative assistant
# snapshots are removed from streaming wire events: `message_start` provides
# the initial message, deltas build it, and `message_end` provides the final
# authoritative message. Tool-call ids and names remain available because
# their size is constant.

def SessionEvent() -> Data: Runner.RunEvent(Unit, Tools.ToolDetails, Unit)
def Message() -> Data: Agent.AgentMessage<Unit, Tools.ToolDetails, Unit>
def ToolResult() -> Data: Agent.AgentToolResult<Tools.ToolDetails>

def field(key: String, value: V.Value, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  R.Property{key, value} <> rest

def object(fields: List<&2, R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def text(value: String) -> V.Value: V.Text{value}
def natural(value: Nat) -> V.Value: V.Number{F.fromU32(U32.from_nat(value))}

def unitDetails(value: Unit) -> V.Value: V.Null{}

# Tool details
# ------------

def limit(value: Maybe<&2, Truncate.Limit>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Truncate.Lines{}}: V.Text{"lines"}
    case Some{Truncate.Bytes{}}: V.Text{"bytes"}

def truncation(value: Truncate.TruncationResult) -> V.Value:
  match value:
    case Truncate.TruncationResult{content, truncated, truncatedBy, totalLines, totalBytes, outputLines, outputBytes, lastLinePartial, firstLineExceedsLimit, maxLines, maxBytes}:
      object(field("content", text(content), field("truncated", V.Boolean{truncated}, field("truncatedBy", limit(truncatedBy), field("totalLines", natural(totalLines), field("totalBytes", natural(totalBytes), field("outputLines", natural(outputLines), field("outputBytes", natural(outputBytes), field("lastLinePartial", V.Boolean{lastLinePartial}, field("firstLineExceedsLimit", V.Boolean{firstLineExceedsLimit}, field("maxLines", natural(maxLines), field("maxBytes", natural(maxBytes), Nil{}))))))))))))

def readDetails(value: Maybe<&2, Read.ReadToolDetails>) -> V.Value:
  match value:
    case None{}: object(Nil{})
    case Some{Read.ReadToolDetails{result}}: object(field("truncation", truncation(result), Nil{}))

def bashDetails(value: Maybe<&2, Bash.BashToolDetails>) -> V.Value:
  match value:
    case None{}: object(Nil{})
    case Some{Bash.BashToolDetails{result, fullOutputPath}}: object(Json.optional("truncation", Maybe.map(&2, Truncate.TruncationResult, V.Value, truncation, result), Json.optionalText("fullOutputPath", fullOutputPath, Nil{})))

def editDetails(value: Edit.EditToolDetails) -> V.Value:
  match value:
    case Edit.EditToolDetails{diff, patch, firstChangedLine}: object(field("diff", text(diff), field("patch", text(patch), Json.optional("firstChangedLine", Maybe.map(&2, Nat, V.Value, natural, firstChangedLine), Nil{}))))

def findDetails(value: Maybe<&2, Find.FindToolDetails>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Find.FindToolDetails{cut, resultLimit}}: object(Json.optional("truncation", Maybe.map(&2, Truncate.TruncationResult, V.Value, truncation, cut), Json.optional("resultLimitReached", Maybe.map(&2, Nat, V.Value, natural, resultLimit), Nil{})))

def toolDetails(value: Tools.ToolDetails) -> V.Value:
  match value:
    case Tools.ReadDetails{details}: readDetails(details)
    case Tools.BashDetails{details}: bashDetails(details)
    case Tools.EditDetails{details}: editDetails(details)
    case Tools.WriteDetails{}: object(Nil{})
    case Tools.FindDetails{details}: findDetails(details)

# Messages
# --------

def message(value: Message()) -> V.Value:
  match value:
    case Agent.LlmMessage{value}: Json.message(~Unit, ~Tools.ToolDetails, ~unitDetails, ~toolDetails, value)
    case Agent.CustomMessage{_}: V.Null{}

def messages(values: List<&2, Message()>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: message(value) <> messages(rest)

def toolResults(values: List<&2, Ai.ToolResultMessage<Tools.ToolDetails>>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: Json.toolResultMessage(~Tools.ToolDetails, ~toolDetails, value) <> toolResults(rest)

def toolResult(value: ToolResult()) -> V.Value:
  match value:
    case Agent.AgentToolResult{content, details, usage, terminate}: object(field("content", V.ArrayValue{Json.textImageContents(content)}, field("details", toolDetails(details), Json.optional("usage", Maybe.map(&2, Ai.Usage, V.Value, Json.usage, usage), Json.optionalBoolean("terminate", terminate, Nil{})))))

# Streaming events without snapshots
# ----------------------------------

def toolCallAt(content: List<&2, Ai.AssistantContent<V.Value>>, index: Nat) -> Maybe<&2, Ai.ToolCall<V.Value>>:
  match content index:
    case Nil{} _: None{}
    case Ai.AssistantToolCall{call} <> _ 0n: Some{call}
    case _ <> _ 0n: None{}
    case _ <> rest 1n+n: toolCallAt(rest, n)

def indexResult(result: Result<&2, &2, F.Error, Nat>) -> Nat:
  match result:
    case Done{index}: index
    case Fail{_}: 0n

def indexOf(value: F64) -> Nat: indexResult(F.convert(value))

def partialContent(partial: Ai.AssistantMessage<V.Value, Unit>) -> List<&2, Ai.AssistantContent<V.Value>>:
  match partial:
    case Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: content

# toolcall_start carries the call's id and name from the partial snapshot;
# a missing tool call at that index is a protocol error.
def toolcallStart(index: F64, call: Maybe<&2, Ai.ToolCall<V.Value>>) -> Result<&2, &2, String, V.Value>:
  match call:
    case None{}: Fail{"toolcall_start content at index " ++ Nat.show(indexOf(index)) ++ " is not a tool call"}
    case Some{Ai.ToolCall{id, name, _, _, _}}: Done{object(field("type", text("toolcall_start"), field("contentIndex", V.Number{index}, field("id", text(id), field("toolName", text(name), Nil{})))))}

def assistantMessageEvent(event: Ai.AssistantMessageEvent<V.Value, Unit>) -> Result<&2, &2, String, V.Value>:
  match event:
    case Ai.Start{_}: Done{object(field("type", text("start"), Nil{}))}
    case Ai.TextStart{index, _}: Done{object(field("type", text("text_start"), field("contentIndex", V.Number{index}, Nil{})))}
    case Ai.TextDelta{index, delta, _}: Done{object(field("type", text("text_delta"), field("contentIndex", V.Number{index}, field("delta", text(delta), Nil{}))))}
    case Ai.TextEnd{index, content, _}: Done{object(field("type", text("text_end"), field("contentIndex", V.Number{index}, field("content", text(content), Nil{}))))}
    case Ai.ThinkingStart{index, _}: Done{object(field("type", text("thinking_start"), field("contentIndex", V.Number{index}, Nil{})))}
    case Ai.ThinkingDelta{index, delta, _}: Done{object(field("type", text("thinking_delta"), field("contentIndex", V.Number{index}, field("delta", text(delta), Nil{}))))}
    case Ai.ThinkingEnd{index, content, _}: Done{object(field("type", text("thinking_end"), field("contentIndex", V.Number{index}, field("content", text(content), Nil{}))))}
    case Ai.ToolcallStart{+index, partial}: toolcallStart(index, toolCallAt(partialContent(partial), indexOf(index)))
    case Ai.ToolcallDelta{index, delta, _}: Done{object(field("type", text("toolcall_delta"), field("contentIndex", V.Number{index}, field("delta", text(delta), Nil{}))))}
    case Ai.ToolcallEnd{index, call, _}: Done{object(field("type", text("toolcall_end"), field("contentIndex", V.Number{index}, field("toolCall", Json.toolCall(call), Nil{}))))}
    case Ai.StreamDone{reason, final}: Done{object(field("type", text("done"), field("reason", text(Json.doneReason(reason)), field("message", Json.assistantMessage(~Unit, ~unitDetails, final), Nil{}))))}
    case Ai.StreamError{reason, failed}: Done{object(field("type", text("error"), field("reason", text(Json.errorReason(reason)), field("error", Json.assistantMessage(~Unit, ~unitDetails, failed), Nil{}))))}

def messageUpdate(message: Message(), event: Result<&2, &2, String, V.Value>) -> Result<&2, &2, String, V.Value>:
  match message event:
    case _ Fail{error}: Fail{error}
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, _, _, _, _, _, _, _, usage, _, _, _, _, _, _}}} Done{value}: Done{object(field("type", text("message_update"), field("usage", Json.usage(usage), field("assistantMessageEvent", value, Nil{}))))}
    case _ Done{_}: Fail{"message_update message is not an assistant message"}

# Events other than message_update pass through with their upstream shape.
def toJsonEvent(event: SessionEvent()) -> Result<&2, &2, String, V.Value>:
  match event:
    case Agent.AgentStart{}: Done{object(field("type", text("agent_start"), Nil{}))}
    case Agent.AgentEnd{values}: Done{object(field("type", text("agent_end"), field("messages", V.ArrayValue{messages(values)}, Nil{})))}
    case Agent.TurnStart{}: Done{object(field("type", text("turn_start"), Nil{}))}
    case Agent.TurnEnd{value, results}: Done{object(field("type", text("turn_end"), field("message", message(value), field("toolResults", V.ArrayValue{toolResults(results)}, Nil{}))))}
    case Agent.MessageStart{value}: Done{object(field("type", text("message_start"), field("message", message(value), Nil{})))}
    case Agent.MessageUpdate{value, assistantEvent}: messageUpdate(value, assistantMessageEvent(assistantEvent))
    case Agent.MessageEnd{value}: Done{object(field("type", text("message_end"), field("message", message(value), Nil{})))}
    case Agent.ToolExecutionStart{toolCallId, toolName, args}: Done{object(field("type", text("tool_execution_start"), field("toolCallId", text(toolCallId), field("toolName", text(toolName), field("args", args, Nil{})))))}
    case Agent.ToolExecutionUpdate{toolCallId, toolName, args, partialResult}: Done{object(field("type", text("tool_execution_update"), field("toolCallId", text(toolCallId), field("toolName", text(toolName), field("args", args, field("partialResult", toolResult(partialResult), Nil{}))))))}
    case Agent.ToolExecutionEnd{toolCallId, toolName, result, isError}: Done{object(field("type", text("tool_execution_end"), field("toolCallId", text(toolCallId), field("toolName", text(toolName), field("result", toolResult(result), field("isError", V.Boolean{isError}, Nil{}))))))}

import Base
import ../../../agent/src/types.bend as Agent
import ../../../agent/src/agent.bend as Runner
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/message-json.bend as Json
import ../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/f64.bend as F
import ../core/tools/index.bend as Tools
import ../core/messages.bend as Messages
import ../core/session-json.bend as SessionJson
import ../core/agent-session.bend as Session
import ../core/compaction/compaction.bend as Compaction

# Session event shape emitted by the JSON stdout protocol. Cumulative assistant
# snapshots are removed from streaming wire events: `message_start` provides
# the initial message, deltas build it, and `message_end` provides the final
# authoritative message. Tool-call ids and names remain available because
# their size is constant.

def Custom() -> Data: Messages.CodingMessage<V.Value>
def SessionEvent() -> Data: Runner.RunEvent(Unit, Tools.ToolDetails, Custom())
def Message() -> Data: Agent.AgentMessage<Unit, Tools.ToolDetails, Custom()>
def ToolResult() -> Data: Agent.AgentToolResult<Tools.ToolDetails>



def unitDetails(value: Unit) -> V.Value: V.Null{}
def rawValue(value: V.Value) -> V.Value: value

# Messages
# --------

def message(value: Message()) -> V.Value:
  match value:
    case Agent.LlmMessage{value}: Json.message(~Unit, ~Tools.ToolDetails, ~unitDetails, ~Tools.detailsValue, value)
    case Agent.CustomMessage{value}: SessionJson.codingMessage(~V.Value, ~rawValue, value)

def messages(values: List<&2, Message()>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: message(value) <> messages(rest)

def toolResults(values: List<&2, Ai.ToolResultMessage<Tools.ToolDetails>>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: Json.toolResultMessage(~Tools.ToolDetails, ~Tools.detailsValue, value) <> toolResults(rest)

def toolResult(value: ToolResult()) -> V.Value:
  match value:
    case Agent.AgentToolResult{content, details, usage, terminate}: Json.object(Json.field("content", V.ArrayValue{Json.textImageContents(content)}, Json.field("details", Tools.detailsValue(details), Json.optional("usage", Maybe.map(&2, Ai.Usage, V.Value, Json.usage, usage), Json.optionalBoolean("terminate", terminate, Nil{})))))

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

# toolcall_start carries the call's id and name from the partial snapshot;
# a missing tool call at that index is a protocol error.
def toolcallStart(index: F64, call: Maybe<&2, Ai.ToolCall<V.Value>>) -> Result<&2, &2, String, V.Value>:
  match call:
    case None{}: Fail{"toolcall_start content at index " ++ Nat.show(indexOf(index)) ++ " is not a tool call"}
    case Some{Ai.ToolCall{id, name, _, _, _}}: Done{Json.object(Json.field("type", Json.text("toolcall_start"), Json.field("contentIndex", V.Number{index}, Json.field("id", Json.text(id), Json.field("toolName", Json.text(name), Nil{})))))}

def assistantMessageEvent(event: Ai.AssistantMessageEvent<V.Value, Unit>) -> Result<&2, &2, String, V.Value>:
  match event:
    case Ai.Start{_}: Done{Json.object(Json.field("type", Json.text("start"), Nil{}))}
    case Ai.TextStart{index, _}: Done{Json.object(Json.field("type", Json.text("text_start"), Json.field("contentIndex", V.Number{index}, Nil{})))}
    case Ai.TextDelta{index, delta, _}: Done{Json.object(Json.field("type", Json.text("text_delta"), Json.field("contentIndex", V.Number{index}, Json.field("delta", Json.text(delta), Nil{}))))}
    case Ai.TextEnd{index, content, _}: Done{Json.object(Json.field("type", Json.text("text_end"), Json.field("contentIndex", V.Number{index}, Json.field("content", Json.text(content), Nil{}))))}
    case Ai.ThinkingStart{index, _}: Done{Json.object(Json.field("type", Json.text("thinking_start"), Json.field("contentIndex", V.Number{index}, Nil{})))}
    case Ai.ThinkingDelta{index, delta, _}: Done{Json.object(Json.field("type", Json.text("thinking_delta"), Json.field("contentIndex", V.Number{index}, Json.field("delta", Json.text(delta), Nil{}))))}
    case Ai.ThinkingEnd{index, content, _}: Done{Json.object(Json.field("type", Json.text("thinking_end"), Json.field("contentIndex", V.Number{index}, Json.field("content", Json.text(content), Nil{}))))}
    case Ai.ToolcallStart{+index, partial}: toolcallStart(index, toolCallAt(Ai.assistantContent(V.Value, Unit, partial), indexOf(index)))
    case Ai.ToolcallDelta{index, delta, _}: Done{Json.object(Json.field("type", Json.text("toolcall_delta"), Json.field("contentIndex", V.Number{index}, Json.field("delta", Json.text(delta), Nil{}))))}
    case Ai.ToolcallEnd{index, call, _}: Done{Json.object(Json.field("type", Json.text("toolcall_end"), Json.field("contentIndex", V.Number{index}, Json.field("toolCall", Json.toolCall(call), Nil{}))))}
    case Ai.StreamDone{reason, final}: Done{Json.object(Json.field("type", Json.text("done"), Json.field("reason", Json.text(Json.doneReason(reason)), Json.field("message", Json.assistantMessage(~Unit, ~unitDetails, final), Nil{}))))}
    case Ai.StreamError{reason, failed}: Done{Json.object(Json.field("type", Json.text("error"), Json.field("reason", Json.text(Json.errorReason(reason)), Json.field("error", Json.assistantMessage(~Unit, ~unitDetails, failed), Nil{}))))}

def messageUpdate(message: Message(), event: Result<&2, &2, String, V.Value>) -> Result<&2, &2, String, V.Value>:
  match message event:
    case _ Fail{error}: Fail{error}
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, _, _, _, _, _, _, _, usage, _, _, _, _, _, _}}} Done{value}: Done{Json.object(Json.field("type", Json.text("message_update"), Json.field("usage", Json.usage(usage), Json.field("assistantMessageEvent", value, Nil{}))))}
    case _ Done{_}: Fail{"message_update message is not an assistant message"}

# Events other than message_update pass through with their upstream shape.
def toJsonEvent(event: SessionEvent()) -> Result<&2, &2, String, V.Value>:
  match event:
    case Agent.AgentStart{}: Done{Json.object(Json.field("type", Json.text("agent_start"), Nil{}))}
    case Agent.AgentEnd{values}: Done{Json.object(Json.field("type", Json.text("agent_end"), Json.field("messages", V.ArrayValue{messages(values)}, Nil{})))}
    case Agent.TurnStart{}: Done{Json.object(Json.field("type", Json.text("turn_start"), Nil{}))}
    case Agent.TurnEnd{value, results}: Done{Json.object(Json.field("type", Json.text("turn_end"), Json.field("message", message(value), Json.field("toolResults", V.ArrayValue{toolResults(results)}, Nil{}))))}
    case Agent.MessageStart{value}: Done{Json.object(Json.field("type", Json.text("message_start"), Json.field("message", message(value), Nil{})))}
    case Agent.MessageUpdate{value, assistantEvent}: messageUpdate(value, assistantMessageEvent(assistantEvent))
    case Agent.MessageEnd{value}: Done{Json.object(Json.field("type", Json.text("message_end"), Json.field("message", message(value), Nil{})))}
    case Agent.ToolExecutionStart{toolCallId, toolName, args}: Done{Json.object(Json.field("type", Json.text("tool_execution_start"), Json.field("toolCallId", Json.text(toolCallId), Json.field("toolName", Json.text(toolName), Json.field("args", args, Nil{})))))}
    case Agent.ToolExecutionUpdate{toolCallId, toolName, args, partialResult}: Done{Json.object(Json.field("type", Json.text("tool_execution_update"), Json.field("toolCallId", Json.text(toolCallId), Json.field("toolName", Json.text(toolName), Json.field("args", args, Json.field("partialResult", toolResult(partialResult), Nil{}))))))}
    case Agent.ToolExecutionEnd{toolCallId, toolName, result, isError}: Done{Json.object(Json.field("type", Json.text("tool_execution_end"), Json.field("toolCallId", Json.text(toolCallId), Json.field("toolName", Json.text(toolName), Json.field("result", toolResult(result), Json.field("isError", V.Boolean{isError}, Nil{}))))))}

# Session events
# --------------
# upstream toJsonEvent passes every AgentSession event through except
# message_update; the session-level events keep their upstream shapes.

def texts(values: List<&2, String>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> texts(rest)

def reasonName(reason: Session.CompactionReason) -> String:
  match reason:
    case Session.Manual{}: "manual"
    case Session.Threshold{}: "threshold"
    case Session.Overflow{}: "overflow"

def retrySource(source: Session.RetrySource) -> List<&2, R.Property<V.Value>>:
  match source:
    case Session.BranchSummarySource{}: Json.field("source", Json.text("branchSummary"), Nil{})
    case Session.CompactionSource{reason}: Json.field("source", Json.text("compaction"), Json.field("reason", Json.text(reasonName(reason)), Nil{}))

def compactionDetails(details: Compaction.CompactionDetails) -> V.Value:
  match details:
    case Compaction.CompactionDetails{readFiles, modifiedFiles}: Json.object(Json.field("readFiles", V.ArrayValue{texts(readFiles)}, Json.field("modifiedFiles", V.ArrayValue{texts(modifiedFiles)}, Nil{})))

def compactionResult(result: Compaction.CompactionResult) -> V.Value:
  match result:
    case Compaction.CompactionResult{summary, firstKeptEntryId, tokensBefore, estimatedTokensAfter, usage, details}:
      Json.object(Json.field("summary", Json.text(summary), Json.field("firstKeptEntryId", Json.text(firstKeptEntryId), Json.field("tokensBefore", V.Number{tokensBefore}, Json.optional("estimatedTokensAfter", Maybe.map(&2, F64, V.Value, after => V.Number{after}, estimatedTokensAfter), Json.optional("usage", Maybe.map(&2, Ai.Usage, V.Value, Json.usage, usage), Json.optional("details", Maybe.map(&2, Compaction.CompactionDetails, V.Value, compactionDetails, details), Nil{})))))))

def toSessionJsonEvent(event: Session.AgentSessionEvent) -> Result<&2, &2, String, V.Value>:
  match event:
    case Session.AgentEvent{value}: toJsonEvent(value)
    case Session.AgentEnd{values, willRetry}: Done{Json.object(Json.field("type", Json.text("agent_end"), Json.field("messages", V.ArrayValue{messages(values)}, Json.field("willRetry", V.Boolean{willRetry}, Nil{}))))}
    case Session.AgentSettled{}: Done{Json.object(Json.field("type", Json.text("agent_settled"), Nil{}))}
    case Session.QueueUpdate{steering, followUp}: Done{Json.object(Json.field("type", Json.text("queue_update"), Json.field("steering", V.ArrayValue{texts(steering)}, Json.field("followUp", V.ArrayValue{texts(followUp)}, Nil{}))))}
    case Session.SessionInfoChanged{name}: Done{Json.object(Json.field("type", Json.text("session_info_changed"), Json.optionalText("name", name, Nil{})))}
    case Session.ThinkingLevelChanged{level}: Done{Json.object(Json.field("type", Json.text("thinking_level_changed"), Json.field("level", Json.text(Levels.name(level)), Nil{})))}
    case Session.AutoRetryStart{attempt, maxAttempts, delayMs, errorMessage}: Done{Json.object(Json.field("type", Json.text("auto_retry_start"), Json.field("attempt", Json.natural(attempt), Json.field("maxAttempts", Json.natural(maxAttempts), Json.field("delayMs", V.Number{delayMs}, Json.field("errorMessage", Json.text(errorMessage), Nil{}))))))}
    case Session.AutoRetryEnd{success, attempt, finalError}: Done{Json.object(Json.field("type", Json.text("auto_retry_end"), Json.field("success", V.Boolean{success}, Json.field("attempt", Json.natural(attempt), Json.optionalText("finalError", finalError, Nil{})))))}
    case Session.CompactionStart{reason}: Done{Json.object(Json.field("type", Json.text("compaction_start"), Json.field("reason", Json.text(reasonName(reason)), Nil{})))}
    case Session.CompactionEnd{reason, result, aborted, willRetry, errorMessage}: Done{Json.object(Json.field("type", Json.text("compaction_end"), Json.field("reason", Json.text(reasonName(reason)), Json.optional("result", Maybe.map(&2, Compaction.CompactionResult, V.Value, compactionResult, result), Json.field("aborted", V.Boolean{aborted}, Json.field("willRetry", V.Boolean{willRetry}, Json.optionalText("errorMessage", errorMessage, Nil{})))))))}
    case Session.SummarizationRetryScheduled{attempt, maxAttempts, delayMs, errorMessage}: Done{Json.object(Json.field("type", Json.text("summarization_retry_scheduled"), Json.field("attempt", Json.natural(attempt), Json.field("maxAttempts", Json.natural(maxAttempts), Json.field("delayMs", V.Number{delayMs}, Json.field("errorMessage", Json.text(errorMessage), Nil{}))))))}
    case Session.SummarizationRetryAttemptStart{source}: Done{Json.object(Json.field("type", Json.text("summarization_retry_attempt_start"), retrySource(source)))}
    case Session.SummarizationRetryFinished{}: Done{Json.object(Json.field("type", Json.text("summarization_retry_finished"), Nil{}))}


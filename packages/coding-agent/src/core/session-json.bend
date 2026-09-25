import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/message-json.bend as Json
import ../../../ai/src/utils/json.bend as Render
import ../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../agent/src/types.bend as Agent
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/f64.bend as F
import ./messages.bend as Messages
import ./session-manager.bend as S

# The JSONL session file format: one JSON object per line, the header first.
# Objects render as JSON.stringify renders upstream's entries (same member
# order, undefined members omitted), and read back through typed decoders.
# Migrations operate on the parsed JSON objects, as upstream mutates plain
# objects before the typed layer sees them.

def Decoded(-A: Data) -> Data: Result<&2, &2, Decode.Error, A>






def nullableText(+value: Maybe<&2, String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: V.Text{value}

# Rendering
# ---------

def header(value: S.SessionHeader) -> V.Value:
  match value:
    case S.SessionHeader{version, id, timestamp, cwd, parentSession}:
      Json.object(Json.field("type", Json.text("session"), Json.optional("version", Maybe.map(&2, Nat, V.Value, Json.natural, version), Json.field("id", Json.text(id), Json.field("timestamp", Json.text(timestamp), Json.field("cwd", Json.text(cwd), Json.optionalText("parentSession", parentSession, Nil{})))))))

# Entry members shared by every entry type, in upstream's order.
def based(kind: String, base: S.SessionEntryBase, rest: List<&2, R.Property<V.Value>>) -> V.Value:
  match base:
    case S.SessionEntryBase{id, parentId, timestamp}:
      Json.object(Json.field("type", Json.text(kind), Json.field("id", Json.text(id), Json.field("parentId", nullableText(parentId), Json.field("timestamp", Json.text(timestamp), rest)))))

# Upstream places custom entries' own members before the shared ones.
def customBased(kind: String, own: List<&2, R.Property<V.Value>>, base: S.SessionEntryBase) -> V.Value:
  match base:
    case S.SessionEntryBase{id, parentId, timestamp}:
      Json.object(Json.field("type", Json.text(kind), List.append(&2, R.Property<V.Value>, own, Json.field("id", Json.text(id), Json.field("parentId", nullableText(parentId), Json.field("timestamp", Json.text(timestamp), Nil{}))))))

def bashExecution(value: Messages.BashExecutionMessage) -> V.Value:
  match value:
    case Messages.BashExecutionMessage{command, output, exitCode, cancelled, truncated, fullOutputPath, timestamp, excludeFromContext}:
      Json.object(Json.field("role", Json.text("bashExecution"), Json.field("command", Json.text(command), Json.field("output", Json.text(output), Json.optional("exitCode", Maybe.map(&2, U32, V.Value, code => V.Number{F.fromU32(code)}, exitCode), Json.field("cancelled", V.Boolean{cancelled}, Json.field("truncated", V.Boolean{truncated}, Json.optionalText("fullOutputPath", fullOutputPath, Json.field("timestamp", V.Number{timestamp}, Json.optionalBoolean("excludeFromContext", excludeFromContext, Nil{}))))))))))

def codingMessage(~C: Data, ~custom: C -> V.Value, +value: Messages.CodingMessage<C>) -> V.Value:
  match value:
    case Messages.BashExecution{value}: bashExecution(value)
    case Messages.Custom{Messages.CustomMessage{customType, content, display, details, timestamp}}:
      Json.object(Json.field("role", Json.text("custom"), Json.field("customType", Json.text(customType), Json.field("content", Json.userContent(content), Json.field("display", V.Boolean{display}, Json.optional("details", Maybe.map(&2, C, V.Value, custom, details), Json.field("timestamp", V.Number{timestamp}, Nil{})))))))
    case Messages.BranchSummary{Messages.BranchSummaryMessage{summary, fromId, timestamp}}:
      Json.object(Json.field("role", Json.text("branchSummary"), Json.field("summary", Json.text(summary), Json.field("fromId", nullableText(fromId), Json.field("timestamp", V.Number{timestamp}, Nil{})))))
    case Messages.CompactionSummary{Messages.CompactionSummaryMessage{summary, tokensBefore, timestamp}}:
      Json.object(Json.field("role", Json.text("compactionSummary"), Json.field("summary", Json.text(summary), Json.field("tokensBefore", Json.natural(tokensBefore), Json.field("timestamp", V.Number{timestamp}, Nil{})))))

def agentMessage(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +value: Agent.AgentMessage<D, T, Messages.CodingMessage<C>>) -> V.Value:
  match value:
    case Agent.LlmMessage{value}: Json.message(~D, ~T, ~diagnostic, ~tool, value)
    case Agent.CustomMessage{value}: codingMessage(~C, ~custom, value)

def usage(value: Maybe<&2, Ai.Usage>) -> Maybe<&2, V.Value>:
  Maybe.map(&2, Ai.Usage, V.Value, Json.usage, value)

def compaction(~C: Data, ~custom: C -> V.Value, value: S.CompactionEntry<C>) -> V.Value:
  match value:
    case S.CompactionEntry{base, summary, firstKeptEntryId, tokensBefore, details, usageValue, fromHook, systemMessage}:
      based("compaction", base, Json.field("summary", Json.text(summary), Json.field("firstKeptEntryId", Json.text(firstKeptEntryId), Json.field("tokensBefore", Json.natural(tokensBefore), Json.optional("details", Maybe.map(&2, C, V.Value, custom, details), Json.optional("usage", usage(usageValue), Json.optionalBoolean("fromHook", fromHook, Json.optional("systemMessage", Maybe.map(&2, Ai.SystemMessage<V.Value>, V.Value, Json.systemMessage, systemMessage), Nil{}))))))))

def editableBlock(value: S.EditableBlock) -> V.Value:
  match value:
    case S.EditableText{item}: Json.textContent(item)
    case S.EditableImage{item}: Json.imageContent(item)
    case S.EditableThinking{item}: Json.thinkingContent(item)
    case S.EditableToolCall{item}: Json.toolCall(item)

def editableBlocks(values: List<&2, S.EditableBlock>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case item <> rest: editableBlock(item) <> editableBlocks(rest)

def editableContent(value: S.ContextEditableContent) -> V.Value:
  match value:
    case S.ContentText{text}: V.Text{text}
    case S.ContentBlocks{blocks}: V.ArrayValue{editableBlocks(blocks)}

# A null replacement is written, as upstream writes it.
def replacementValue(value: Maybe<&2, S.ContextEditableContent>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{content}: Json.object(Json.field("content", editableContent(content), Nil{}))

def entry(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +value: S.SessionEntry<D, T, C>) -> V.Value:
  match value:
    case S.SessionMessageEntry{base, message}: based("message", base, Json.field("message", agentMessage(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, message), Nil{}))
    case S.ThinkingLevelChangeEntry{base, thinkingLevel}: based("thinking_level_change", base, Json.field("thinkingLevel", Json.text(thinkingLevel), Nil{}))
    case S.ModelChangeEntry{base, provider, modelId}: based("model_change", base, Json.field("provider", Json.text(provider), Json.field("modelId", Json.text(modelId), Nil{})))
    case S.UsageEntry{base, kind, provider, model, usageValue, note}: based("usage", base, Json.field("kind", Json.text(kind), Json.field("provider", Json.text(provider), Json.field("model", Json.text(model), Json.field("usage", Json.usage(usageValue), Json.optionalText("note", note, Nil{}))))))
    case S.Compaction{value}: compaction(~C, ~custom, value)
    case S.BranchSummaryEntry{base, fromId, summary, details, usageValue, fromHook}:
      based("branch_summary", base, Json.field("fromId", Json.text(fromId), Json.field("summary", Json.text(summary), Json.optional("details", Maybe.map(&2, C, V.Value, custom, details), Json.optional("usage", usage(usageValue), Json.optionalBoolean("fromHook", fromHook, Nil{}))))))
    case S.CustomEntry{base, customType, data}: customBased("custom", Json.field("customType", Json.text(customType), Json.optional("data", Maybe.map(&2, C, V.Value, custom, data), Nil{})), base)
    case S.CustomMessageEntry{base, customType, content, details, display}:
      customBased("custom_message", Json.field("customType", Json.text(customType), Json.field("content", Json.userContent(content), Json.field("display", V.Boolean{display}, Json.optional("details", Maybe.map(&2, C, V.Value, custom, details), Nil{})))), base)
    case S.LabelEntry{base, targetId, label}: based("label", base, Json.field("targetId", Json.text(targetId), Json.optionalText("label", label, Nil{})))
    case S.SessionInfoEntry{base, name}: based("session_info", base, Json.optionalText("name", name, Nil{}))
    case S.ContextEditEntry{base, targetId, replacement}: based("context_edit", base, Json.field("targetId", Json.text(targetId), Json.field("replacement", replacementValue(replacement), Nil{})))

def fileEntry(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +value: S.FileEntry<D, T, C>) -> V.Value:
  match value:
    case S.Header{value}: header(value)
    case S.Entry{value}: entry(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, value)

# One file line, newline terminated. Non-finite numbers render as null, as JSON.stringify does.
def line(value: V.Value) -> String:
  Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(value)), "null") ++ "\n"

def entryLine(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, value: S.FileEntry<D, T, C>) -> String:
  line(fileEntry(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, value))

# Decoding
# --------

def decodeBoolean(value: V.Value) -> Decoded(Bool):
  match value:
    case V.Boolean{flag}: Done{flag}
    case _: Fail{Decode.WrongType{Nil{}, "boolean"}}

def naturalResult(result: Result<&2, &2, F.Error, Nat>) -> Decoded(Nat):
  match result:
    case Done{count}: Done{count}
    case Fail{_}: Fail{Decode.InvalidValue{Nil{}, "non-negative integer"}}

def naturalOf(value: F64) -> Decoded(Nat): naturalResult(F.convert(value))

def decodeNatural(value: V.Value) -> Decoded(Nat):
  Result.bind(&2, &2, Decode.Error, F64, Nat, Decode.number(value), scalar => naturalOf(scalar))

def decodeNullableText(value: V.Value) -> Decoded(Maybe<&2, String>):
  match value:
    case V.Null{}: Done{None{}}
    case V.Text{body}: Done{Some{body}}
    case _: Fail{Decode.WrongType{Nil{}, "string or null"}}

def tagged(fields: R.Record<V.Value>, +key: String) -> Decoded(String):
  Decode.required(String, fields, key, Decode.string)

# A header's cwd is read leniently, as upstream's discovery does.
def headerCwd(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{cwd}}: cwd
    case _: ""

def headerFields(+fields: R.Record<V.Value>) -> Decoded(S.SessionHeader):
  do Result<&2, &2, Decode.Error, S.SessionHeader>:
    version : Maybe<&2, Nat> <- Decode.optional(Nat, fields, "version", decodeNatural)
    id : String <- tagged(fields, "id")
    timestamp : String <- tagged(fields, "timestamp")
    parentSession : Maybe<&2, String> <- Decode.optional(String, fields, "parentSession", Decode.string)
    return S.SessionHeader{version, id, timestamp, headerCwd(R.get(V.Value, fields, "cwd")), parentSession}

def baseFields(+fields: R.Record<V.Value>) -> Decoded(S.SessionEntryBase):
  do Result<&2, &2, Decode.Error, S.SessionEntryBase>:
    id : String <- tagged(fields, "id")
    parentId : Maybe<&2, String> <- Result.map(&2, &2, Decode.Error, Maybe<&2, Maybe<&2, String>>, Maybe<&2, String>, found => Maybe.default(&2, Maybe<&2, String>, found, None{}), Decode.optional(Maybe<&2, String>, fields, "parentId", decodeNullableText))
    timestamp : String <- tagged(fields, "timestamp")
    return S.SessionEntryBase{id, parentId, timestamp}

def exitCodeOf(value: V.Value) -> Decoded(U32):
  Result.map(&2, &2, Decode.Error, Nat, U32, count => U32.from_nat(count), decodeNatural(value))

def bashExecutionFields(+fields: R.Record<V.Value>) -> Decoded(Messages.BashExecutionMessage):
  do Result<&2, &2, Decode.Error, Messages.BashExecutionMessage>:
    command : String <- tagged(fields, "command")
    output : String <- tagged(fields, "output")
    exitCode : Maybe<&2, U32> <- Decode.optional(U32, fields, "exitCode", exitCodeOf)
    cancelled : Bool <- Decode.required(Bool, fields, "cancelled", decodeBoolean)
    truncated : Bool <- Decode.required(Bool, fields, "truncated", decodeBoolean)
    fullOutputPath : Maybe<&2, String> <- Decode.optional(String, fields, "fullOutputPath", Decode.string)
    timestamp : F64 <- Decode.required(F64, fields, "timestamp", Decode.number)
    excludeFromContext : Maybe<&2, Bool> <- Decode.optional(Bool, fields, "excludeFromContext", decodeBoolean)
    return Messages.BashExecutionMessage{command, output, exitCode, cancelled, truncated, fullOutputPath, timestamp, excludeFromContext}

def customMessageFields(~C: Data, ~custom: V.Value -> Decoded(C), +fields: R.Record<V.Value>) -> Decoded(Messages.CustomMessage<C>):
  do Result<&2, &2, Decode.Error, Messages.CustomMessage<C>>:
    customType : String <- tagged(fields, "customType")
    content : Ai.UserContent <- Decode.required(Ai.UserContent, fields, "content", Json.decodeUserContent)
    display : Bool <- Decode.required(Bool, fields, "display", decodeBoolean)
    details : Maybe<&2, C> <- Decode.optional(C, fields, "details", custom)
    timestamp : F64 <- Decode.required(F64, fields, "timestamp", Decode.number)
    return Messages.CustomMessage{customType, content, display, details, timestamp}

def branchSummaryFields(+fields: R.Record<V.Value>) -> Decoded(Messages.BranchSummaryMessage):
  do Result<&2, &2, Decode.Error, Messages.BranchSummaryMessage>:
    summary : String <- tagged(fields, "summary")
    fromId : Maybe<&2, String> <- Result.map(&2, &2, Decode.Error, Maybe<&2, Maybe<&2, String>>, Maybe<&2, String>, found => Maybe.default(&2, Maybe<&2, String>, found, None{}), Decode.optional(Maybe<&2, String>, fields, "fromId", decodeNullableText))
    timestamp : F64 <- Decode.required(F64, fields, "timestamp", Decode.number)
    return Messages.BranchSummaryMessage{summary, fromId, timestamp}

def compactionSummaryFields(+fields: R.Record<V.Value>) -> Decoded(Messages.CompactionSummaryMessage):
  do Result<&2, &2, Decode.Error, Messages.CompactionSummaryMessage>:
    summary : String <- tagged(fields, "summary")
    tokensBefore : Nat <- Decode.required(Nat, fields, "tokensBefore", decodeNatural)
    timestamp : F64 <- Decode.required(F64, fields, "timestamp", Decode.number)
    return Messages.CompactionSummaryMessage{summary, tokensBefore, timestamp}

def messageOf(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), +role: String, +fields: R.Record<V.Value>) -> Decoded(Agent.AgentMessage<D, T, Messages.CodingMessage<C>>):
  match role:
    case "bashExecution": Result.map(&2, &2, Decode.Error, Messages.BashExecutionMessage, Agent.AgentMessage<D, T, Messages.CodingMessage<C>>, item => Agent.CustomMessage{Messages.BashExecution{item}}, bashExecutionFields(fields))
    case "custom": Result.map(&2, &2, Decode.Error, Messages.CustomMessage<C>, Agent.AgentMessage<D, T, Messages.CodingMessage<C>>, item => Agent.CustomMessage{Messages.Custom{item}}, customMessageFields(~C, ~custom, fields))
    case "branchSummary": Result.map(&2, &2, Decode.Error, Messages.BranchSummaryMessage, Agent.AgentMessage<D, T, Messages.CodingMessage<C>>, item => Agent.CustomMessage{Messages.BranchSummary{item}}, branchSummaryFields(fields))
    case "compactionSummary": Result.map(&2, &2, Decode.Error, Messages.CompactionSummaryMessage, Agent.AgentMessage<D, T, Messages.CodingMessage<C>>, item => Agent.CustomMessage{Messages.CompactionSummary{item}}, compactionSummaryFields(fields))
    case other: Result.map(&2, &2, Decode.Error, Ai.Message<V.Value, V.Value, D, T>, Agent.AgentMessage<D, T, Messages.CodingMessage<C>>, item => Agent.LlmMessage{item}, Json.messageOf(~D, ~T, ~diagnostic, ~tool, other, V.ObjectValue{fields}))

def decodeAgentMessage(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), value: V.Value) -> Decoded(Agent.AgentMessage<D, T, Messages.CodingMessage<C>>):
  do Result<&2, &2, Decode.Error, Agent.AgentMessage<D, T, Messages.CodingMessage<C>>>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    role : String <- tagged(fields, "role")
    messageOf(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, role, fields)

def compactionFields(~C: Data, ~custom: V.Value -> Decoded(C), +fields: R.Record<V.Value>) -> Decoded(S.CompactionEntry<C>):
  do Result<&2, &2, Decode.Error, S.CompactionEntry<C>>:
    base : S.SessionEntryBase <- baseFields(fields)
    summary : String <- tagged(fields, "summary")
    firstKeptEntryId : String <- tagged(fields, "firstKeptEntryId")
    tokensBefore : Nat <- Decode.required(Nat, fields, "tokensBefore", decodeNatural)
    details : Maybe<&2, C> <- Decode.optional(C, fields, "details", custom)
    usageValue : Maybe<&2, Ai.Usage> <- Decode.optional(Ai.Usage, fields, "usage", Json.decodeUsage)
    fromHook : Maybe<&2, Bool> <- Decode.optional(Bool, fields, "fromHook", decodeBoolean)
    systemMessage : Maybe<&2, Ai.SystemMessage<V.Value>> <- Decode.optional(Ai.SystemMessage<V.Value>, fields, "systemMessage", Json.decodeSystemMessage)
    return S.CompactionEntry{base, summary, firstKeptEntryId, tokensBefore, details, usageValue, fromHook, systemMessage}

def editableBlockOf(+kind: String, fields: R.Record<V.Value>) -> Decoded(S.EditableBlock):
  match kind:
    case "text": Result.map(&2, &2, Decode.Error, Ai.TextContent, S.EditableBlock, item => S.EditableText{item}, Json.textContentFields(fields))
    case "image": Result.map(&2, &2, Decode.Error, Ai.ImageContent, S.EditableBlock, item => S.EditableImage{item}, Json.imageContentFields(fields))
    case "thinking": Result.map(&2, &2, Decode.Error, Ai.ThinkingContent, S.EditableBlock, item => S.EditableThinking{item}, Json.thinkingContentFields(fields))
    case "toolCall": Result.map(&2, &2, Decode.Error, Ai.ToolCall<V.Value>, S.EditableBlock, item => S.EditableToolCall{item}, Json.toolCallFields(fields))
    case _: Fail{Decode.InvalidValue{Decode.Field{"type"} <> Nil{}, "text, image, thinking or toolCall"}}

def decodeEditableBlock(value: V.Value) -> Decoded(S.EditableBlock):
  do Result<&2, &2, Decode.Error, S.EditableBlock>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    kind : String <- tagged(fields, "type")
    editableBlockOf(kind, fields)

def decodeEditableContent(value: V.Value) -> Decoded(S.ContextEditableContent):
  match value:
    case V.Text{body}: Done{S.ContentText{body}}
    case V.ArrayValue{values}: Result.map(&2, &2, Decode.Error, List<&2, S.EditableBlock>, S.ContextEditableContent, blocks => S.ContentBlocks{blocks}, Decode.items(~S.EditableBlock, ~decodeEditableBlock, values, 0n))
    case _: Fail{Decode.WrongType{Nil{}, "string or array"}}

def decodeReplacement(value: V.Value) -> Decoded(Maybe<&2, S.ContextEditableContent>):
  match value:
    case V.Null{}: Done{None{}}
    case other:
      do Result<&2, &2, Decode.Error, Maybe<&2, S.ContextEditableContent>>:
        +fields : R.Record<V.Value> <- Decode.object(other)
        content : S.ContextEditableContent <- Decode.required(S.ContextEditableContent, fields, "content", decodeEditableContent)
        return Some{content}

def entryOf(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), +kind: String, +fields: R.Record<V.Value>) -> Decoded(S.SessionEntry<D, T, C>):
  match kind:
    case "message":
      do Result<&2, &2, Decode.Error, S.SessionEntry<D, T, C>>:
        base : S.SessionEntryBase <- baseFields(fields)
        message : Agent.AgentMessage<D, T, Messages.CodingMessage<C>> <- Decode.required(Agent.AgentMessage<D, T, Messages.CodingMessage<C>>, fields, "message", item => decodeAgentMessage(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, item))
        return S.SessionMessageEntry{base, message}
    case "thinking_level_change":
      do Result<&2, &2, Decode.Error, S.SessionEntry<D, T, C>>:
        base : S.SessionEntryBase <- baseFields(fields)
        thinkingLevel : String <- tagged(fields, "thinkingLevel")
        return S.ThinkingLevelChangeEntry{base, thinkingLevel}
    case "model_change":
      do Result<&2, &2, Decode.Error, S.SessionEntry<D, T, C>>:
        base : S.SessionEntryBase <- baseFields(fields)
        provider : String <- tagged(fields, "provider")
        modelId : String <- tagged(fields, "modelId")
        return S.ModelChangeEntry{base, provider, modelId}
    case "usage":
      do Result<&2, &2, Decode.Error, S.SessionEntry<D, T, C>>:
        base : S.SessionEntryBase <- baseFields(fields)
        category : String <- tagged(fields, "kind")
        provider : String <- tagged(fields, "provider")
        model : String <- tagged(fields, "model")
        usageValue : Ai.Usage <- Decode.required(Ai.Usage, fields, "usage", Json.decodeUsage)
        note : Maybe<&2, String> <- Decode.optional(String, fields, "note", Decode.string)
        return S.UsageEntry{base, category, provider, model, usageValue, note}
    case "compaction": Result.map(&2, &2, Decode.Error, S.CompactionEntry<C>, S.SessionEntry<D, T, C>, item => S.Compaction{item}, compactionFields(~C, ~custom, fields))
    case "branch_summary":
      do Result<&2, &2, Decode.Error, S.SessionEntry<D, T, C>>:
        base : S.SessionEntryBase <- baseFields(fields)
        fromId : String <- tagged(fields, "fromId")
        summary : String <- tagged(fields, "summary")
        details : Maybe<&2, C> <- Decode.optional(C, fields, "details", custom)
        usageValue : Maybe<&2, Ai.Usage> <- Decode.optional(Ai.Usage, fields, "usage", Json.decodeUsage)
        fromHook : Maybe<&2, Bool> <- Decode.optional(Bool, fields, "fromHook", decodeBoolean)
        return S.BranchSummaryEntry{base, fromId, summary, details, usageValue, fromHook}
    case "custom":
      do Result<&2, &2, Decode.Error, S.SessionEntry<D, T, C>>:
        base : S.SessionEntryBase <- baseFields(fields)
        customType : String <- tagged(fields, "customType")
        data : Maybe<&2, C> <- Decode.optional(C, fields, "data", custom)
        return S.CustomEntry{base, customType, data}
    case "custom_message":
      do Result<&2, &2, Decode.Error, S.SessionEntry<D, T, C>>:
        base : S.SessionEntryBase <- baseFields(fields)
        customType : String <- tagged(fields, "customType")
        content : Ai.UserContent <- Decode.required(Ai.UserContent, fields, "content", Json.decodeUserContent)
        display : Bool <- Decode.required(Bool, fields, "display", decodeBoolean)
        details : Maybe<&2, C> <- Decode.optional(C, fields, "details", custom)
        return S.CustomMessageEntry{base, customType, content, details, display}
    case "label":
      do Result<&2, &2, Decode.Error, S.SessionEntry<D, T, C>>:
        base : S.SessionEntryBase <- baseFields(fields)
        targetId : String <- tagged(fields, "targetId")
        label : Maybe<&2, String> <- Decode.optional(String, fields, "label", Decode.string)
        return S.LabelEntry{base, targetId, label}
    case "session_info":
      do Result<&2, &2, Decode.Error, S.SessionEntry<D, T, C>>:
        base : S.SessionEntryBase <- baseFields(fields)
        name : Maybe<&2, String> <- Decode.optional(String, fields, "name", Decode.string)
        return S.SessionInfoEntry{base, name}
    case "context_edit":
      do Result<&2, &2, Decode.Error, S.SessionEntry<D, T, C>>:
        base : S.SessionEntryBase <- baseFields(fields)
        targetId : String <- tagged(fields, "targetId")
        replacement : Maybe<&2, S.ContextEditableContent> <- Decode.required(Maybe<&2, S.ContextEditableContent>, fields, "replacement", decodeReplacement)
        return S.ContextEditEntry{base, targetId, replacement}
    case _: Fail{Decode.InvalidValue{Decode.Field{"type"} <> Nil{}, "session entry type"}}

def fileEntryOf(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), +kind: String, +fields: R.Record<V.Value>) -> Decoded(S.FileEntry<D, T, C>):
  match kind:
    case "session": Result.map(&2, &2, Decode.Error, S.SessionHeader, S.FileEntry<D, T, C>, item => S.Header{item}, headerFields(fields))
    case other: Result.map(&2, &2, Decode.Error, S.SessionEntry<D, T, C>, S.FileEntry<D, T, C>, item => S.Entry{item}, entryOf(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, other, fields))

def decodeFileEntry(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), value: V.Value) -> Decoded(S.FileEntry<D, T, C>):
  do Result<&2, &2, Decode.Error, S.FileEntry<D, T, C>>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    kind : String <- tagged(fields, "type")
    fileEntryOf(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, kind, fields)

# Lines
# -----
# Blank and malformed lines are skipped, as upstream's readers do. An object
# that parses but does not decode as a session entry is treated the same way;
# upstream would carry such an object along untyped.

def maybeOf(-E: Data, -A: Data, result: Result<&2, &2, E, A>) -> Maybe<&2, A>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

def blank(line: String) -> Bool: String.is_empty(String.trim(line))

def parsedUnlessBlank(isBlank: Bool, line: String) -> Maybe<&2, V.Value>:
  match isBlank:
    case True{}: None{}
    case False{}: maybeOf(Decode.ParseError, V.Value, Decode.parse(line))

def parsedLine(+line: String) -> Maybe<&2, V.Value>: parsedUnlessBlank(blank(line), line)

def parseSessionEntryLine(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), line: String) -> Maybe<&2, S.FileEntry<D, T, C>>:
  Maybe.bind(&2, V.Value, S.FileEntry<D, T, C>, parsedLine(line), value => maybeOf(Decode.Error, S.FileEntry<D, T, C>, decodeFileEntry(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, value)))

def consValue(parsed: Maybe<&2, V.Value>, +reversed: List<&2, V.Value>) -> List<&2, V.Value>:
  match parsed:
    case None{}: reversed
    case Some{value}: value <> reversed

# The JSON objects of a file's lines, in order; blank and malformed lines dropped.
def parsedLines(lines: List<&2, String>, +reversed: List<&2, V.Value>) -> List<&2, V.Value>:
  match lines:
    case Nil{}: List.reverse(&2, V.Value, reversed)
    case row <> rest: parsedLines(rest, consValue(parsedLine(row), reversed))

def consEntry(-D: Data, -T: Data, -C: Data, decoded: Decoded(S.FileEntry<D, T, C>), +reversed: List<&2, S.FileEntry<D, T, C>>) -> List<&2, S.FileEntry<D, T, C>>:
  match decoded:
    case Fail{_}: reversed
    case Done{item}: item <> reversed

def decodedValues(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), values: List<&2, V.Value>, +reversed: List<&2, S.FileEntry<D, T, C>>) -> List<&2, S.FileEntry<D, T, C>>:
  match values:
    case Nil{}: List.reverse(&2, S.FileEntry<D, T, C>, reversed)
    case value <> rest: decodedValues(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, rest, consEntry(D, T, C, decodeFileEntry(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, value), reversed))

def decodeValues(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), values: List<&2, V.Value>) -> List<&2, S.FileEntry<D, T, C>>:
  decodedValues(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, values, Nil{})

def parseSessionEntries(~D: Data, ~T: Data, ~C: Data, ~diagnostic: V.Value -> Decoded(D), ~tool: V.Value -> Decoded(T), ~custom: V.Value -> Decoded(C), content: String) -> List<&2, S.FileEntry<D, T, C>>:
  decodeValues(~D, ~T, ~C, ~diagnostic, ~tool, ~custom, parsedLines(String.split(String.trim(content), '\n'), Nil{}))

# Migration
# ---------
# Older files are brought to the current version on their parsed JSON objects:
# v1 → v2 adds id/parentId chains (and resolves compaction indices to ids),
# v2 → v3 renames the hookMessage role to custom. Fresh ids come from the
# caller, one per non-header Json.object, as upstream draws them from randomUUID.

def textField(found: Maybe<&2, V.Value>) -> String:
  match found:
    case Some{V.Text{value}}: value
    case _: ""

def fieldsOf(value: V.Value) -> R.Record<V.Value>:
  match value:
    case V.ObjectValue{fields}: fields
    case _: R.new(V.Value)

def kindOf(value: V.Value) -> String: textField(R.get(V.Value, fieldsOf(value), "type"))

def isHeader(value: V.Value) -> Bool: String.eq(kindOf(value), "session")

def versionField(found: Maybe<&2, V.Value>) -> Nat:
  match found:
    case Some{V.Number{scalar}}: Result.default(&2, &2, Decode.Error, Nat, naturalOf(scalar), 1n)
    case _: 1n

def headerRecord(+value: V.Value) -> Maybe<&2, R.Record<V.Value>>:
  Bool.pick(Maybe<&2, R.Record<V.Value>>, isHeader(value), Some{fieldsOf(value)}, None{})

def headerSearch(values: List<&2, V.Value>) -> Maybe<&2, R.Record<V.Value>>:
  match values:
    case Nil{}: None{}
    case value <> rest: Maybe.or(&2, R.Record<V.Value>, headerRecord(value), headerSearch(rest))

# A file without a header, or a header without a version, is version 1.
def headerVersion(values: List<&2, V.Value>) -> Nat:
  versionField(Maybe.bind(&2, R.Record<V.Value>, V.Value, headerSearch(values), fields => R.get(V.Value, fields, "version")))

def setField(value: V.Value, key: String, item: V.Value) -> V.Value:
  match value:
    case V.ObjectValue{fields}: V.ObjectValue{R.set(V.Value, fields, key, item)}
    case other: other

def versioned(heading: Bool, +value: V.Value, +version: Nat) -> V.Value:
  match heading:
    case True{}: setField(value, "version", Json.natural(version))
    case False{}: value

def withVersion(+value: V.Value, version: Nat) -> V.Value: versioned(isHeader(value), value, version)

# Ids are assigned by position first (None for the header), so compaction
# indices can be resolved against the same positions afterwards.
def assignIds(values: List<&2, V.Value>, fresh: List<&2, String>, +reversed: List<&2, Maybe<&2, String>>) -> List<&2, Maybe<&2, String>>:
  match values fresh:
    case Nil{} _: List.reverse(&2, Maybe<&2, String>, reversed)
    case _ <> rest Nil{}: assignIds(rest, Nil{}, None{} <> reversed)
    case +value <> rest +id <> +more: assignIds(rest, Bool.pick(List<&2, String>, isHeader(value), id <> more, more), Bool.pick(Maybe<&2, String>, isHeader(value), None{}, Some{id}) <> reversed)

def applyIds(values: List<&2, V.Value>, assigned: List<&2, Maybe<&2, String>>, +previous: Maybe<&2, String>, +reversed: List<&2, V.Value>) -> List<&2, V.Value>:
  match values assigned:
    case Nil{} _: List.reverse(&2, V.Value, reversed)
    case value <> rest Nil{}: applyIds(rest, Nil{}, previous, withVersion(value, 2n) <> reversed)
    case value <> rest None{} <> more: applyIds(rest, more, previous, withVersion(value, 2n) <> reversed)
    case value <> rest Some{+id} <> more: applyIds(rest, more, Some{id}, setField(setField(value, "id", Json.text(id)), "parentId", nullableText(previous)) <> reversed)

def assignedAt(assigned: List<&2, Maybe<&2, String>>, index: Nat) -> Maybe<&2, String>:
  match assigned index:
    case Nil{} _: None{}
    case found <> _ 0n: found
    case _ <> rest 1n+remaining: assignedAt(rest, remaining)

def keptIndexField(found: Maybe<&2, V.Value>) -> Maybe<&2, Nat>:
  match found:
    case Some{V.Number{scalar}}: maybeOf(Decode.Error, Nat, naturalOf(scalar))
    case _: None{}

def keptEntryId(+fields: R.Record<V.Value>, found: Maybe<&2, String>) -> V.Value:
  match found:
    case None{}: V.ObjectValue{fields}
    case Some{id}: V.ObjectValue{R.set(V.Value, fields, "firstKeptEntryId", Json.text(id))}

def resolvedIndex(+fields: R.Record<V.Value>, index: Maybe<&2, Nat>, assigned: List<&2, Maybe<&2, String>>) -> V.Value:
  match index:
    case None{}: V.ObjectValue{fields}
    case Some{position}: keptEntryId(R.remove(V.Value, fields, "firstKeptEntryIndex"), assignedAt(assigned, position))

def resolvedCompaction(isCompaction: Bool, +fields: R.Record<V.Value>, assigned: List<&2, Maybe<&2, String>>) -> V.Value:
  match isCompaction:
    case False{}: V.ObjectValue{fields}
    case True{}: resolvedIndex(fields, keptIndexField(R.get(V.Value, fields, "firstKeptEntryIndex")), assigned)

def resolvedCompactions(values: List<&2, V.Value>, +assigned: List<&2, Maybe<&2, String>>, +reversed: List<&2, V.Value>) -> List<&2, V.Value>:
  match values:
    case Nil{}: List.reverse(&2, V.Value, reversed)
    case +value <> rest: resolvedCompactions(rest, assigned, resolvedCompaction(String.eq(kindOf(value), "compaction"), fieldsOf(value), assigned) <> reversed)

def migrateV1ToV2(+values: List<&2, V.Value>, fresh: List<&2, String>) -> List<&2, V.Value>:
  +assigned = assignIds(values, fresh, Nil{})
  resolvedCompactions(applyIds(values, assigned, None{}, Nil{}), assigned, Nil{})

def messageRole(fields: R.Record<V.Value>) -> String:
  textField(R.get(V.Value, fieldsOf(Maybe.default(&2, V.Value, R.get(V.Value, fields, "message"), V.Null{})), "role"))

def renamed(rename: Bool, +fields: R.Record<V.Value>) -> V.Value:
  match rename:
    case False{}: V.ObjectValue{fields}
    case True{}: V.ObjectValue{R.set(V.Value, fields, "message", setField(Maybe.default(&2, V.Value, R.get(V.Value, fields, "message"), V.Null{}), "role", Json.text("custom")))}

def renamedRole(+value: V.Value) -> V.Value:
  renamed(String.eq(kindOf(value), "message") && String.eq(messageRole(fieldsOf(value)), "hookMessage"), fieldsOf(value))

def migrateV2ToV3(values: List<&2, V.Value>, +reversed: List<&2, V.Value>) -> List<&2, V.Value>:
  match values:
    case Nil{}: List.reverse(&2, V.Value, reversed)
    case value <> rest: migrateV2ToV3(rest, withVersion(renamedRole(value), 3n) <> reversed)

type Migration is Data:
  Migration{migrated: Bool, values: List<&2, V.Value>}

def fromVersion(needsIds: Bool, needsRename: Bool, +values: List<&2, V.Value>, fresh: List<&2, String>) -> Migration:
  match needsIds needsRename:
    case True{} _: Migration{True{}, migrateV2ToV3(migrateV1ToV2(values, fresh), Nil{})}
    case False{} True{}: Migration{True{}, migrateV2ToV3(values, Nil{})}
    case False{} False{}: Migration{False{}, values}

# Returns whether a migration was applied, with the current-version objects.
def migrateToCurrentVersion(+values: List<&2, V.Value>, fresh: List<&2, String>) -> Migration:
  +version = headerVersion(values)
  fromVersion(Nat.is_lt(version, 2n), Nat.is_lt(version, 3n), values, fresh)

# Fresh short ids: eight hex digits, as the first bytes of a random UUID.
def hexDigit(+value: U32) -> Char:
  Char.from_u32(Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32)))

def hexBytes(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case +byte <> rest: SCon{hexDigit(U32.shrn(byte, 4n)), SCon{hexDigit(U32.and(byte, 15)), hexBytes(rest)}}

def freshIds(count: Nat, +reversed: List<&2, String>) -> IO(List<&2, String>):
  match count:
    case 0n: IO.pure(List<&2, String>, List.reverse(&2, String, reversed))
    case 1n+remaining:
      do IO<List<&2, String>>:
        random : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(4)
        freshIds(remaining, Result.default(&1, &1, U32 & String, String, Result.map(&1, &1, U32 & String, List<&2, U32>, String, hexBytes, random), "00000000") <> reversed)

def nonHeaderCount(values: List<&2, V.Value>, +count: Nat) -> Nat:
  match values:
    case Nil{}: count
    case value <> rest: nonHeaderCount(rest, Bool.pick(Nat, isHeader(value), count, 1n + count))

def migratedWith(needsIds: Bool, +values: List<&2, V.Value>) -> IO(Migration):
  match needsIds:
    case False{}: IO.pure(Migration, migrateToCurrentVersion(values, Nil{}))
    case True{}:
      do IO<Migration>:
        fresh : List<&2, String> <- freshIds(nonHeaderCount(values, 0n), Nil{})
        return migrateToCurrentVersion(values, fresh)

# Migrate parsed objects, drawing fresh ids only when a v1 file needs them.
def migrated(+values: List<&2, V.Value>) -> IO(Migration):
  migratedWith(Nat.is_lt(headerVersion(values), 2n), values)

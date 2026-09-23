import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/estimate.bend as Estimate
import ../packages/coding-agent/src/core/compaction/compaction.bend as Compaction
import ../packages/coding-agent/src/core/compaction/utils.bend as Utils
import ../packages/coding-agent/src/core/messages.bend as Messages
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R

# Pure compaction scenarios from upstream compaction.test.ts and
# compaction-serialization.test.ts; tests/compaction_check.py pins their
# expectations. Entries are chained like the upstream fixtures.

def Msg() -> Data: Compaction.Msg(Unit, Unit, V.Value)
def Entry() -> Data: Compaction.Entry(Unit, Unit, V.Value)

def n(value: U32) -> F64: U32.to_f64(value)

def mockUsage(+input: U32, +output: U32, +cacheRead: U32, +cacheWrite: U32) -> Ai.Usage:
  Ai.Usage{n(input), n(output), n(cacheRead), n(cacheWrite), None{}, None{}, n((input + output + cacheRead + cacheWrite : U32)), Ai.UsageCost{n(0), n(0), n(0), n(0), n(0)}}

def user(text: String) -> Msg(): Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, n(1000)}}}

def assistantWith(text: String, usage: Ai.Usage, stopReason: Ai.StopReason) -> Msg():
  Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text, None{}}} <> Nil{}, "anthropic-messages", "anthropic", "claude-sonnet-4-5", None{}, None{}, None{}, None{}, usage, stopReason, None{}, None{}, None{}, None{}, n(1000)}}}

def assistant(text: String, usage: Ai.Usage) -> Msg(): assistantWith(text, usage, Ai.Stop{})
def plain(text: String) -> Msg(): assistant(text, mockUsage(100, 50, 0, 0))

def system() -> Msg(): Agent.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{""}, None{}, None{}, None{}, n(1000)}}}

# Entry kinds the fixtures build; ids are assigned in order and chained.
type Fixture is Data:
  MessageOf{message: Msg()}
  CompactionOf{summary: String, keptIndex: Nat}
  ModelChangeOf{provider: String, modelId: String}
  ThinkingOf{level: String}
  CustomOf{content: String}

def idOf(index: Nat) -> String: "test-id-" ++ Nat.show(index)

def parentOf(index: Nat) -> Maybe<&2, String>:
  match index:
    case 0n: None{}
    case 1n+previous: Some{idOf(previous)}

def base(+index: Nat) -> S.SessionEntryBase: S.SessionEntryBase{idOf(index), parentOf(index), "2026-01-01T00:00:00.000Z"}

def entryOf(fixture: Fixture, index: Nat) -> Entry():
  match fixture:
    case MessageOf{message}: S.SessionMessageEntry{base(index), message}
    case CompactionOf{summary, keptIndex}: S.Compaction{S.CompactionEntry{base(index), summary, idOf(keptIndex), 10000n, None{}, None{}, None{}, None{}}}
    case ModelChangeOf{provider, modelId}: S.ModelChangeEntry{base(index), provider, modelId}
    case ThinkingOf{level}: S.ThinkingLevelChangeEntry{base(index), level}
    case CustomOf{content}: S.CustomMessageEntry{base(index), "test", Ai.UserText{content}, None{}, True{}}

def entriesFrom(fixtures: List<&2, Fixture>, +index: Nat) -> List<&2, Entry()>:
  match fixtures:
    case Nil{}: Nil{}
    case fixture <> rest: entryOf(fixture, index) <> entriesFrom(rest, Nat.add(index, 1n))

def entries(fixtures: List<&2, Fixture>) -> List<&2, Entry()>: entriesFrom(fixtures, 0n)

def m(message: Msg()) -> Fixture: MessageOf{message}

def pairs(count: Nat, +index: U32) -> List<&2, Fixture>:
  match count:
    case 0n: Nil{}
    case 1n+rest: m(user("User " ++ U32.show(index))) <> m(assistant("Assistant " ++ U32.show(index), mockUsage(0, 100, ((index + 1) * 1000 : U32), 0))) <> pairs(rest, (index + 1 : U32))

def noDetails(value: V.Value) -> Maybe<&2, Compaction.CompactionDetails>: None{}

def number(value: F64) -> String: Maybe.default(&2, String, F.toJsonNumber(value), "null")
def natural(value: Nat) -> String: Nat.show(value)
def flag(value: Bool) -> String: Bool.pick(String, value, "true", "false")
def optionalNat(value: Maybe<&2, Nat>) -> String: Maybe.default(&2, String, Maybe.map(&2, Nat, String, natural, value), "null")
def optionalText(value: Maybe<&2, String>) -> String: Maybe.default(&2, String, Maybe.map(&2, String, String, Decode.quote, value), "null")

def usageInput(usage: Maybe<&2, Ai.Usage>) -> String:
  match usage:
    case None{}: "null"
    case Some{Ai.Usage{input, _, _, _, _, _, _, _}}: number(input)

def roleOf(message: Msg()) -> String:
  match message:
    case Agent.LlmMessage{Ai.User{_}}: "user"
    case Agent.LlmMessage{Ai.Assistant{_}}: "assistant"
    case Agent.LlmMessage{Ai.System{_}}: "system"
    case Agent.LlmMessage{Ai.ToolResult{_}}: "toolResult"
    case Agent.CustomMessage{Messages.Custom{_}}: "custom"
    case Agent.CustomMessage{Messages.CompactionSummary{_}}: "compactionSummary"
    case Agent.CustomMessage{Messages.BranchSummary{_}}: "branchSummary"
    case Agent.CustomMessage{Messages.BashExecution{_}}: "bashExecution"

def entryRole(entry: Maybe<&2, Entry()>) -> String:
  match entry:
    case Some{S.SessionMessageEntry{_, message}}: roleOf(message)
    case Some{S.Compaction{_}}: "compaction"
    case Some{_}: "other"
    case None{}: "missing"

# extractText of the upstream test: text blocks joined by spaces, messages by newlines.
def blockTexts(blocks: List<&2, Ai.TextImageContent>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case Ai.TextImageText{Ai.TextContent{text, _}} <> rest: text <> blockTexts(rest)
    case _ <> rest: blockTexts(rest)

def assistantTexts(blocks: List<&2, Ai.AssistantContent<V.Value>>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case Ai.AssistantText{Ai.TextContent{text, _}} <> rest: text <> assistantTexts(rest)
    case _ <> rest: assistantTexts(rest)

def userTextOf(content: Ai.UserContent) -> String:
  match content:
    case Ai.UserText{text}: text
    case Ai.UserBlocks{blocks}: String.join(blockTexts(blocks), " ")

def messageText(message: Msg()) -> String:
  match message:
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{content, _}}}: userTextOf(content)
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}}: String.join(assistantTexts(content), " ")
    case Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{_, _, content, _, _, _, _}}}: String.join(blockTexts(content), " ")
    case Agent.CustomMessage{Messages.Custom{Messages.CustomMessage{_, content, _, _, _}}}: userTextOf(content)
    case Agent.CustomMessage{Messages.CompactionSummary{Messages.CompactionSummaryMessage{summary, _, _}}}: summary
    case Agent.CustomMessage{Messages.BranchSummary{Messages.BranchSummaryMessage{summary, _, _}}}: summary
    case Agent.CustomMessage{Messages.BashExecution{Messages.BashExecutionMessage{command, output, _, _, _, _, _, _}}}: command ++ "\n" ++ output
    case _: ""

def texts(messages: List<&2, Msg()>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: messageText(message) <> texts(rest)

def extractText(messages: List<&2, Msg()>) -> String: String.join(texts(messages), "\n")

def cutJson(result: Compaction.CutPointResult, entryList: List<&2, Entry()>) -> String:
  match result:
    case Compaction.CutPointResult{+firstKept, turnStart, isSplitTurn}:
      "{\"firstKeptEntryIndex\":" ++ natural(firstKept) ++ ",\"turnStartIndex\":" ++ optionalNat(turnStart) ++ ",\"isSplitTurn\":" ++ flag(isSplitTurn) ++ ",\"role\":" ++ Decode.quote(entryRole(List.get(&2, Entry(), entryList, firstKept))) ++ "}"

def cut(+entryList: List<&2, Entry()>, keep: U32) -> String:
  cutJson(Compaction.findCutPoint(Unit, Unit, V.Value, entryList, 0n, List.length(&2, Entry(), entryList), n(keep)), entryList)

def modelJson(model: Maybe<&2, S.SessionModel>) -> String:
  match model:
    case None{}: "null"
    case Some{S.SessionModel{provider, modelId}}: "{\"provider\":" ++ Decode.quote(provider) ++ ",\"modelId\":" ++ Decode.quote(modelId) ++ "}"


def contextJson(context: Result<&2, &2, S.Error, S.SessionContext<Unit, Unit, V.Value>>) -> String:
  match context:
    case Fail{_}: "{\"error\":\"context\"}"
    case Done{S.SessionContext{+messages, thinkingLevel, model}}:
      "{\"count\":" ++ natural(List.length(&2, Msg(), messages)) ++ ",\"first\":" ++ Decode.quote(Maybe.default(&2, String, Maybe.map(&2, Msg(), String, roleOf, List.get(&2, Msg(), messages, 0n)), "")) ++ ",\"firstText\":" ++ Decode.quote(Maybe.default(&2, String, Maybe.map(&2, Msg(), String, messageText, List.get(&2, Msg(), messages, 0n)), "")) ++ ",\"thinkingLevel\":" ++ Decode.quote(thinkingLevel) ++ ",\"model\":" ++ modelJson(model) ++ "}"

def context(entryList: List<&2, Entry()>) -> String: contextJson(S.contextFromPath(Unit, Unit, V.Value, entryList))

def preparationJson(value: Maybe<&2, Compaction.CompactionPreparation<Unit, Unit, V.Value>>) -> String:
  match value:
    case None{}: "null"
    case Some{Compaction.CompactionPreparation{firstKeptEntryId, messagesToSummarize, turnPrefixMessages, isSplitTurn, tokensBefore, previousSummary, _, _}}:
      "{\"firstKeptEntryId\":" ++ Decode.quote(firstKeptEntryId) ++ ",\"summarized\":" ++ Decode.quote(extractText(messagesToSummarize)) ++ ",\"prefix\":" ++ Decode.quote(extractText(turnPrefixMessages)) ++ ",\"isSplitTurn\":" ++ flag(isSplitTurn) ++ ",\"tokensBefore\":" ++ number(tokensBefore) ++ ",\"previousSummary\":" ++ optionalText(previousSummary) ++ "}"

def prepare(entryList: List<&2, Entry()>, keep: U32) -> String:
  preparationJson(Compaction.prepareCompaction(~Unit, ~Unit, ~V.Value, ~noDetails, entryList, Compaction.CompactionSettings{True{}, n(16384), n(keep)}))

def estimateJson(estimate: Estimate.ContextUsageEstimate) -> String:
  match estimate:
    case Estimate.ContextUsageEstimate{tokens, usageTokens, trailingTokens, lastUsageIndex}:
      "{\"tokens\":" ++ number(tokens) ++ ",\"usageTokens\":" ++ number(usageTokens) ++ ",\"trailingTokens\":" ++ number(trailingTokens) ++ ",\"lastUsageIndex\":" ++ optionalNat(lastUsageIndex) ++ "}"

def toolResult(text: String) -> Ai.Message<V.Value, V.Value, Unit, Unit>:
  Ai.ToolResult{Ai.ToolResultMessage{"tc1", "read", Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}, None{}, None{}, False{}, n(1000)}}

def llmUser(text: String) -> Ai.Message<V.Value, V.Value, Unit, Unit>: Ai.User{Ai.UserMessage{Ai.UserText{text}, n(1000)}}

def llmAssistant(text: String) -> Ai.Message<V.Value, V.Value, Unit, Unit>:
  Ai.Assistant{Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text, None{}}} <> Nil{}, "anthropic-messages", "anthropic", "claude-sonnet-4-5", None{}, None{}, None{}, None{}, mockUsage(1, 1, 0, 0), Ai.Stop{}, None{}, None{}, None{}, None{}, n(1000)}}

def serialize(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, Unit>>) -> String:
  Decode.quote(Utils.serializeConversation(Unit, Unit, messages))

def toolCallMessage(name: String, path: String) -> Msg():
  Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantToolCall{Ai.ToolCall{"tc", name, V.ObjectValue{R.Record{R.Property{"path", V.Text{path}} <> Nil{}}}, None{}, None{}}} <> Nil{}, "anthropic-messages", "anthropic", "claude-sonnet-4-5", None{}, None{}, None{}, None{}, mockUsage(1, 1, 0, 0), Ai.Stop{}, None{}, None{}, None{}, None{}, n(1000)}}}


def quotedAll(values: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: Decode.quote(value) <> quotedAll(rest)

def quoted(values: List<&2, String>) -> String: String.join(quotedAll(values), ",")


def fileListsJson(lists: Utils.FileLists) -> String:
  match lists:
    case Utils.FileLists{+readFiles, +modifiedFiles}: "{\"read\":[" ++ quoted(readFiles) ++ "],\"modified\":[" ++ quoted(modifiedFiles) ++ "],\"formatted\":" ++ Decode.quote(Utils.formatFileOperations(readFiles, modifiedFiles)) ++ "}"


def fileOps() -> String:
  fileListsJson(Utils.computeFileLists(Utils.extractFileOpsFromMessages(Unit, Unit, Messages.CodingMessage<V.Value>, toolCallMessage("read", "b.txt") <> toolCallMessage("read", "a.txt") <> toolCallMessage("edit", "a.txt") <> toolCallMessage("write", "c.txt") <> toolCallMessage("bash", "z.txt") <> Nil{}, Utils.createFileOps())))


def scenario(name: String) -> String:
  match name:
    case "tokens": "{\"full\":" ++ number(Compaction.calculateContextTokens(mockUsage(1000, 500, 200, 100))) ++ ",\"zero\":" ++ number(Compaction.calculateContextTokens(mockUsage(0, 0, 0, 0))) ++ "}"
    case "last-usage":
      "{\"last\":" ++ usageInput(Compaction.getLastAssistantUsage(Unit, Unit, V.Value, entries(m(user("Hello")) <> m(assistant("Hi", mockUsage(100, 50, 0, 0))) <> m(user("How are you?")) <> m(assistant("Good", mockUsage(200, 100, 0, 0))) <> Nil{}))) ++ ",\"aborted\":" ++ usageInput(Compaction.getLastAssistantUsage(Unit, Unit, V.Value, entries(m(user("Hello")) <> m(assistant("Hi", mockUsage(100, 50, 0, 0))) <> m(user("How are you?")) <> m(assistantWith("Aborted", mockUsage(300, 150, 0, 0), Ai.Aborted{})) <> Nil{}))) ++ ",\"zero\":" ++ usageInput(Compaction.getLastAssistantUsage(Unit, Unit, V.Value, entries(m(user("Hello")) <> m(assistant("Hi", mockUsage(100, 50, 0, 0))) <> m(user("continue")) <> m(assistant("Partial", mockUsage(0, 0, 0, 0))) <> Nil{}))) ++ ",\"none\":" ++ usageInput(Compaction.getLastAssistantUsage(Unit, Unit, V.Value, entries(m(user("Hello")) <> Nil{}))) ++ "}"
    case "estimate": estimateJson(Compaction.estimateContextTokens(Unit, Unit, V.Value, user("Hello") <> assistant("Hi", mockUsage(100, 50, 0, 0)) <> user("continue") <> assistant("Partial thinking", mockUsage(0, 0, 0, 0)) <> Nil{}))
    case "should-compact": "{\"above\":" ++ flag(Compaction.shouldCompact(n(95000), n(100000), Compaction.CompactionSettings{True{}, n(10000), n(20000)})) ++ ",\"below\":" ++ flag(Compaction.shouldCompact(n(89000), n(100000), Compaction.CompactionSettings{True{}, n(10000), n(20000)})) ++ ",\"disabled\":" ++ flag(Compaction.shouldCompact(n(95000), n(100000), Compaction.CompactionSettings{False{}, n(10000), n(20000)})) ++ "}"
    case "cut-tokens": cut(entries(pairs(10n, 0)), 2500)
    case "cut-none": cut(entries(m(plain("a")) <> Nil{}), 1000)
    case "cut-fits": cut(entries(m(user("1")) <> m(assistant("a", mockUsage(0, 50, 500, 0))) <> m(user("2")) <> m(assistant("b", mockUsage(0, 50, 1000, 0))) <> Nil{}), 50000)
    case "cut-split": cut(entries(m(user("Turn 1")) <> m(assistant("A1", mockUsage(0, 100, 1000, 0))) <> m(user("Turn 2")) <> m(assistant("A2-1", mockUsage(0, 100, 5000, 0))) <> m(assistant("A2-2", mockUsage(0, 100, 8000, 0))) <> m(assistant("A2-3", mockUsage(0, 100, 10000, 0))) <> Nil{}), 3000)
    case "cut-custom-tiny": cut(entries(m(user("hi")) <> m(plain("hello")) <> CustomOf{String.repeat("x", 4000n)} <> m(plain("ok")) <> Nil{}), 1)
    case "cut-custom-fits": cut(entries(m(user("hi")) <> m(plain("hello")) <> CustomOf{String.repeat("x", 4000n)} <> m(plain("ok")) <> Nil{}), 2)
    case "context-plain": context(entries(m(user("1")) <> m(plain("a")) <> m(user("2")) <> m(plain("b")) <> Nil{}))
    case "context-single": context(entries(m(user("1")) <> m(plain("a")) <> m(user("2")) <> m(plain("b")) <> CompactionOf{"Summary of 1,a,2,b", 2n} <> m(user("3")) <> m(plain("c")) <> Nil{}))
    case "context-multiple": context(entries(m(user("1")) <> m(plain("a")) <> CompactionOf{"First summary", 0n} <> m(user("2")) <> m(plain("b")) <> m(user("3")) <> m(plain("c")) <> CompactionOf{"Second summary", 5n} <> m(user("4")) <> m(plain("d")) <> Nil{}))
    case "context-first": context(entries(m(user("1")) <> m(plain("a")) <> CompactionOf{"First summary", 0n} <> m(user("2")) <> m(plain("b")) <> Nil{}))
    case "context-changes": context(entries(m(user("1")) <> ModelChangeOf{"openai", "gpt-4"} <> m(plain("a")) <> ThinkingOf{"high"} <> Nil{}))
    case "prepare-system": prepare(entries(m(system()) <> m(user("one long turn")) <> m(plain("assistant suffix")) <> Nil{}), 1)
    case "prepare-skip": prepare(entries(m(user("user msg 1 (summarized by compaction1)")) <> m(plain("assistant msg 1")) <> m(user("user msg 2 - kept by compaction1")) <> m(plain("assistant msg 2")) <> m(user("user msg 3 - kept by compaction1")) <> m(assistant("assistant msg 3", mockUsage(5000, 1000, 0, 0))) <> CompactionOf{"First summary", 2n} <> m(user("user msg 4 (new after compaction1)")) <> m(assistant("assistant msg 4", mockUsage(8000, 2000, 0, 0))) <> Nil{}), 20000)
    case "prepare-move": prepare(entries(m(user(String.repeat("user msg 1 (summarized by compaction1)", 4n))) <> m(plain(String.repeat("assistant msg 1", 4n))) <> m(user(String.repeat("user msg 2 - kept by compaction1 ", 12n))) <> m(plain(String.repeat("assistant msg 2 ", 12n))) <> m(user(String.repeat("user msg 3 - kept by compaction1 ", 12n))) <> m(assistant(String.repeat("assistant msg 3 ", 12n), mockUsage(5000, 1000, 0, 0))) <> CompactionOf{"First summary", 2n} <> m(user(String.repeat("user msg 4 (new after compaction1) ", 12n))) <> m(assistant(String.repeat("assistant msg 4 ", 12n), mockUsage(8000, 2000, 0, 0))) <> Nil{}), 100)
    case "serialize-long": serialize(toolResult(String.repeat("x", 5000n)) <> Nil{})
    case "serialize-short": serialize(toolResult(String.repeat("x", 1500n)) <> Nil{})
    case "serialize-plain": serialize(llmUser(String.repeat("u", 3000n)) <> llmAssistant(String.repeat("a", 3000n)) <> Nil{})
    case "serialize-mixed": serialize(llmUser("hi") <> Ai.Assistant{Ai.AssistantMessage{Ai.AssistantThinking{Ai.ThinkingContent{"why", None{}, None{}}} <> Ai.AssistantText{Ai.TextContent{"hello", None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"tc1", "read", V.ObjectValue{R.Record{R.Property{"path", V.Text{"a.txt"}} <> R.Property{"limit", V.Number{n(3)}} <> Nil{}}}, None{}, None{}}} <> Nil{}, "anthropic-messages", "anthropic", "claude-sonnet-4-5", None{}, None{}, None{}, None{}, mockUsage(1, 1, 0, 0), Ai.Stop{}, None{}, None{}, None{}, None{}, n(1000)}} <> toolResult("done") <> Nil{})
    case "file-ops": fileOps()
    case _: "{\"error\":\"unknown scenario\"}"

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case name <> rest:
      do IO<Unit>:
        IO.print(scenario(name))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

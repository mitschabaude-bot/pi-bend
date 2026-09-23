import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/estimate.bend as Estimate
import ../packages/coding-agent/src/core/compaction/compaction.bend as Compaction
import ../packages/coding-agent/src/core/messages.bend as Messages
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V

# Upstream session-context-edit.test.ts over the pure session state. Entry ids
# are supplied stamps; each case returns its assertions as one result.

def SM() -> Data: S.SessionManager<Unit, Unit, V.Value>
def Step() -> Data: Result<&2, &2, S.Error, SM()>
def Msg() -> Data: Compaction.Msg(Unit, Unit, V.Value)
def Entry() -> Data: S.SessionEntry<Unit, Unit, V.Value>
def Projection() -> Data: S.SessionProjection<Unit, Unit, V.Value>
def Checked() -> Data: Result<&2, &2, S.Error, Bool>

def n(value: U32) -> F64: U32.to_f64(value)
def time() -> String: "2026-09-23T00:00:00.000Z"
def stamp(id: String) -> S.EntryStamp: S.EntryStamp{id, time()}

def fresh() -> Step(): S.inMemory(Unit, Unit, V.Value, S.SessionHeader{Some{3n}, "session", time(), "/tmp", None{}})

def user(text: String) -> Msg(): Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, n(1)}}}

def usage(+input: U32, +output: U32, +total: U32) -> Ai.Usage:
  Ai.Usage{n(input), n(output), n(0), n(0), None{}, None{}, n(total), Ai.UsageCost{n(0), n(0), n(0), n(0), n(0)}}

def assistantWith(text: String, used: Ai.Usage) -> Msg():
  Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text, None{}}} <> Nil{}, "faux", "faux", "faux", None{}, None{}, None{}, None{}, used, Ai.Stop{}, None{}, None{}, None{}, None{}, n(1)}}}

def assistant(text: String) -> Msg(): assistantWith(text, usage(10, 1, 11))

def toolResult(text: String, isError: Bool) -> Msg():
  Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{"call-1", "read", Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}, None{}, None{}, isError, n(1)}}}

def say(state: SM(), id: String, message: Msg()) -> Step(): S.appendMessage(Unit, Unit, V.Value, state, stamp(id), message)
def edit(state: SM(), id: String, target: String, replacement: Maybe<&2, S.ContextEditableContent>) -> Step(): S.appendContextEdit(Unit, Unit, V.Value, state, stamp(id), target, replacement)
def compact(state: SM(), id: String, summary: String, keep: Maybe<&2, String>, tokens: Nat) -> Step(): S.appendCompaction(Unit, Unit, V.Value, state, stamp(id), summary, keep, tokens, None{}, None{}, None{})
def bookkeeping(state: SM(), id: String) -> Step(): S.appendCustomEntry(Unit, Unit, V.Value, state, stamp(id), "bookkeeping", Some{V.ObjectValue{R.Record{R.Property{"source", V.Text{"test"}} <> Nil{}}}})
def customMessage(state: SM(), id: String, kind: String, content: String) -> Step(): S.appendCustomMessageEntry(Unit, Unit, V.Value, state, stamp(id), kind, Ai.UserText{content}, False{}, None{})

def text(value: String) -> Maybe<&2, S.ContextEditableContent>: Some{S.ContentText{value}}
def textBlock(value: String) -> Maybe<&2, S.ContextEditableContent>: Some{S.ContentBlocks{S.EditableText{Ai.TextContent{value, None{}}} <> Nil{}}}

def projection(state: SM()) -> Result<&2, &2, S.Error, Projection()>: S.sessionProjection(Unit, Unit, V.Value, state)
def branch(state: SM()) -> Result<&2, &2, S.Error, List<&2, Entry()>>: S.getBranch(Unit, Unit, V.Value, state, S.Latest{})

def messagesOf(value: Projection()) -> List<&2, Msg()>:
  match value:
    case S.SessionProjection{_, messages, _, _}: messages

def blocksText(blocks: List<&2, Ai.TextImageContent>) -> String:
  match blocks:
    case Nil{}: ""
    case Ai.TextImageText{Ai.TextContent{value, _}} <> rest: value ++ blocksText(rest)
    case _ <> rest: blocksText(rest)

def assistantText(blocks: List<&2, Ai.AssistantContent<V.Value>>) -> String:
  match blocks:
    case Nil{}: ""
    case Ai.AssistantText{Ai.TextContent{value, _}} <> rest: value ++ assistantText(rest)
    case _ <> rest: assistantText(rest)

def contentText(content: Ai.UserContent) -> String:
  match content:
    case Ai.UserText{value}: value
    case Ai.UserBlocks{blocks}: blocksText(blocks)

# role:text, with summaries for summary messages, as the upstream helpers read them.
def describe(message: Msg()) -> String:
  match message:
    case Agent.LlmMessage{Ai.System{_}}: "system:"
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{content, _}}}: "user:" ++ contentText(content)
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}}: "assistant:" ++ assistantText(content)
    case Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{_, _, content, _, _, _, _}}}: "toolResult:" ++ blocksText(content)
    case Agent.CustomMessage{Messages.Custom{Messages.CustomMessage{_, content, _, _, _}}}: "custom:" ++ contentText(content)
    case Agent.CustomMessage{Messages.CompactionSummary{Messages.CompactionSummaryMessage{summary, _, _}}}: "compactionSummary:" ++ summary
    case Agent.CustomMessage{Messages.BranchSummary{Messages.BranchSummaryMessage{summary, _, _}}}: "branchSummary:" ++ summary
    case Agent.CustomMessage{Messages.BashExecution{_}}: "bashExecution:"

def described(messages: List<&2, Msg()>) -> String:
  match messages:
    case Nil{}: ""
    case message <> rest: describe(message) ++ "|" ++ described(rest)

def roleOf(message: Msg()) -> String:
  match message:
    case Agent.LlmMessage{Ai.System{_}}: "system"
    case Agent.LlmMessage{Ai.User{_}}: "user"
    case Agent.LlmMessage{Ai.Assistant{_}}: "assistant"
    case Agent.LlmMessage{Ai.ToolResult{_}}: "toolResult"
    case Agent.CustomMessage{_}: "custom"

def roles(messages: List<&2, Msg()>) -> String:
  match messages:
    case Nil{}: ""
    case message <> rest: roleOf(message) ++ "|" ++ roles(rest)

def projected(state: SM()) -> Result<&2, &2, S.Error, String>:
  Result.map(&2, &2, S.Error, Projection(), String, value => described(messagesOf(value)), projection(state))

def usageTotal(message: Msg()) -> F64:
  match message:
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, _, _, _, _, _, _, _, Ai.Usage{_, _, _, _, _, _, total, _}, _, _, _, _, _, _}}}: total
    case _: n(0)

def isMessageEntry(entry: Entry()) -> Bool:
  match entry:
    case S.SessionMessageEntry{_, _}: True{}
    case _: False{}

def messageEntries(entries: List<&2, Entry()>) -> Nat:
  match entries:
    case Nil{}: 0n
    case entry <> rest: Bool.pick(Nat, isMessageEntry(entry), 1n, 0n) + messageEntries(rest)

def entryMessage(entry: Maybe<&2, Entry()>) -> String:
  match entry:
    case Some{S.SessionMessageEntry{_, message}}: describe(message)
    case _: "missing"

def settings() -> Compaction.CompactionSettings: Compaction.CompactionSettings{True{}, n(16384), n(1)}

def noDetails(value: V.Value) -> Maybe<&2, Compaction.CompactionDetails>: None{}

def prepare(entries: List<&2, Entry()>) -> Maybe<&2, Compaction.CompactionPreparation<Unit, Unit, V.Value>>:
  Compaction.prepareCompaction(~Unit, ~Unit, ~V.Value, ~noDetails, entries, settings())

def estimate(+state: SM()) -> Result<&2, &2, S.Error, Estimate.ContextUsageEstimate>:
  do Result<&2, &2, S.Error, Estimate.ContextUsageEstimate>:
    value : Projection() <- projection(state)
    path : List<&2, Entry()> <- branch(state)
    return Compaction.estimateProjectedContextTokens(Unit, Unit, V.Value, value, path)

def tokensOf(value: Estimate.ContextUsageEstimate) -> F64:
  match value:
    case Estimate.ContextUsageEstimate{tokens, _, _, _}: tokens

def usageTokensOf(value: Estimate.ContextUsageEstimate) -> F64:
  match value:
    case Estimate.ContextUsageEstimate{_, used, _, _}: used

def trailingOf(value: Estimate.ContextUsageEstimate) -> F64:
  match value:
    case Estimate.ContextUsageEstimate{_, _, trailing, _}: trailing

def equals(a: F64, b: U32) -> Bool: F.isEqual(F.compare(a, n(b)))
def below(a: F64, b: U32) -> Bool: F.isGreater(F.compare(n(b), a))
def above(a: F64, b: U32) -> Bool: F.isGreater(F.compare(a, n(b)))

def omitsTarget() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user("request"))
    s2 : SM() <- say(s1, "a1", assistant("partial"))
    s3 : SM() <- say(s2, "t1", toolResult("raw output", True{}))
    s4 : SM() <- edit(s3, "e1", "a1", None{})
    +s5 : SM() <- edit(s4, "e2", "t1", None{})
    path : List<&2, Entry()> <- branch(s5)
    value : Projection() <- projection(s5)
    return Nat.is_eq(messageEntries(path), 3n) && String.eq(roles(messagesOf(value)), "user|") && String.eq(entryMessage(S.getEntry(Unit, Unit, V.Value, s5, "t1")), "toolResult:raw output")

def firstMessage(value: Projection()) -> Maybe<&2, Msg()>: List.get(&2, Msg(), messagesOf(value), 0n)

# The edited content with the original usage metadata.
def restored(+first: Maybe<&2, Msg()>) -> Bool:
  String.eq(Maybe.default(&2, String, Maybe.map(&2, Msg(), String, describe, first), ""), "assistant:restored") && equals(Maybe.default(&2, F64, Maybe.map(&2, Msg(), F64, usageTotal, first), n(0)), 11)

def latestEditWins() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "a1", assistant("original"))
    s2 : SM() <- edit(s1, "e1", "a1", textBlock("first"))
    s3 : SM() <- edit(s2, "e2", "a1", None{})
    +s4 : SM() <- edit(s3, "e3", "a1", textBlock("restored"))
    value : Projection() <- projection(s4)
    return restored(firstMessage(value)) && String.eq(entryMessage(S.getEntry(Unit, Unit, V.Value, s4, "a1")), "assistant:original")

def isTextBlocks(entry: Maybe<&2, Entry()>, expected: String) -> Bool:
  match entry:
    case Some{S.ContextEditEntry{_, _, Some{S.ContentBlocks{S.EditableText{Ai.TextContent{value, None{}}} <> Nil{}}}}}: String.eq(value, expected)
    case _: False{}

def normalizesStrings() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "a1", assistant("original"))
    s2 : SM() <- say(s1, "t1", toolResult("original result", False{}))
    s3 : SM() <- edit(s2, "e1", "a1", text("assistant replacement"))
    +s4 : SM() <- edit(s3, "e2", "t1", text("result replacement"))
    value : Projection() <- projection(s4)
    return isTextBlocks(S.getEntry(Unit, Unit, V.Value, s4, "e1"), "assistant replacement") && isTextBlocks(S.getEntry(Unit, Unit, V.Value, s4, "e2"), "result replacement") && String.eq(described(messagesOf(value)), "assistant:assistant replacement|toolResult:result replacement|")

def base(id: String, parent: Maybe<&2, String>) -> S.SessionEntryBase: S.SessionEntryBase{id, parent, time()}

# An edit read from a file keeps string content for an array-only role.
def normalizesImported() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    value : Projection() <- S.buildSessionProjection(Unit, Unit, V.Value, S.SessionMessageEntry{base("a1", None{}), assistant("original")} <> S.ContextEditEntry{base("e1", Some{"a1"}), "a1", text("imported replacement")} <> Nil{}, S.Latest{})
    return String.eq(described(messagesOf(value)), "assistant:imported replacement|")

def branchRelative() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user("original"))
    +s2 : SM() <- edit(s1, "e1", "u1", text("edited"))
    edited : String <- projected(s2)
    s3 : SM() <- S.branch(Unit, Unit, V.Value, s2, "u1")
    original : String <- projected(s3)
    return String.eq(edited, "user:edited|") && String.eq(original, "user:original|")

def firstKeptOf(entry: Maybe<&2, Entry()>) -> String:
  match entry:
    case Some{S.Compaction{S.CompactionEntry{_, _, firstKept, _, _, _, _, _}}}: firstKept
    case _: "missing"

def selfReferencing() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user("discarded"))
    s2 : SM() <- compact(s1, "c1", "exact handoff", None{}, 100n)
    +s3 : SM() <- say(s2, "u2", user("after"))
    context : String <- projected(s3)
    return String.eq(firstKeptOf(S.getEntry(Unit, Unit, V.Value, s3, "c1")), "c1") && String.eq(context, "compactionSummary:exact handoff|user:after|")

def postCompactionEdits() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user("summarized"))
    s2 : SM() <- say(s1, "u2", user("original retained"))
    s3 : SM() <- compact(s2, "c1", "summary", Some{"u2"}, 100n)
    s4 : SM() <- edit(s3, "e1", "u2", text("edited retained"))
    context : String <- projected(s4)
    return String.eq(context, "compactionSummary:summary|user:edited retained|")

def summaries(messages: List<&2, Msg()>) -> String:
  match messages:
    case Nil{}: ""
    case Agent.CustomMessage{Messages.CompactionSummary{Messages.CompactionSummaryMessage{summary, _, _}}} <> rest: summary ++ "|" ++ summaries(rest)
    case _ <> rest: summaries(rest)

def previousSummaryOf(value: Maybe<&2, Compaction.CompactionPreparation<Unit, Unit, V.Value>>) -> String:
  match value:
    case Some{Compaction.CompactionPreparation{_, _, _, _, _, Some{summary}, _, _}}: summary
    case _: "missing"

def newestSummary() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user("summarized first"))
    s2 : SM() <- say(s1, "u2", user("retained"))
    s3 : SM() <- compact(s2, "c1", "first summary", Some{"u2"}, 100n)
    s4 : SM() <- say(s3, "a1", assistant("after first compaction"))
    s5 : SM() <- compact(s4, "c2", "second summary", Some{"u2"}, 80n)
    +s6 : SM() <- say(s5, "u3", user(String.repeat("new tail ", 100n)))
    value : Projection() <- projection(s6)
    path : List<&2, Entry()> <- branch(s6)
    return String.eq(summaries(messagesOf(value)), "second summary|") && String.eq(previousSummaryOf(prepare(path)), "second summary")

def repeatedRetainNone() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user("discarded"))
    s2 : SM() <- compact(s1, "c1", "first handoff", None{}, 100n)
    s3 : SM() <- say(s2, "u2", user("also discarded"))
    +s4 : SM() <- compact(s3, "c2", "second handoff", None{}, 50n)
    context : String <- projected(s4)
    return String.eq(firstKeptOf(S.getEntry(Unit, Unit, V.Value, s4, "c2")), "c2") && String.eq(context, "compactionSummary:second handoff|")

def preEditUsage() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user(String.repeat("discarded input ", 2000n)))
    s2 : SM() <- say(s1, "a1", assistantWith("small answer", usage(10000, 1, 10001)))
    +s3 : SM() <- edit(s2, "e1", "u1", None{})
    +edited : Estimate.ContextUsageEstimate <- estimate(s3)
    s4 : SM() <- edit(s3, "e2", "a1", None{})
    omitted : Estimate.ContextUsageEstimate <- estimate(s4)
    return equals(usageTokensOf(edited), 0) && below(tokensOf(edited), 100) && equals(tokensOf(omitted), 0)

def postEditUsage() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user("original"))
    s2 : SM() <- edit(s1, "e1", "u1", text("edited"))
    s3 : SM() <- say(s2, "a1", assistantWith("answer", usage(4000, 100, 4100)))
    s4 : SM() <- say(s3, "u2", user("next"))
    +value : Estimate.ContextUsageEstimate <- estimate(s4)
    return equals(usageTokensOf(value), 4100) && equals(trailingOf(value), 1) && equals(tokensOf(value), 4101)

def usageAfterCompaction() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user("small input"))
    s2 : SM() <- edit(s1, "e1", "u1", text("edited input"))
    s3 : SM() <- say(s2, "a1", assistantWith("answer", usage(50000, 1, 50001)))
    s4 : SM() <- compact(s3, "c1", "small summary", Some{"u1"}, 50001n)
    +value : Estimate.ContextUsageEstimate <- estimate(s4)
    return equals(usageTokensOf(value), 0) && below(tokensOf(value), 100)

def exampleTool() -> Ai.Tool<V.Value>:
  Ai.Tool{"example", String.repeat("tool declaration ", 100n), V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{Nil{}}}} <> Nil{}}}, None{}}

def systemWithTools() -> Msg():
  Agent.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{String.repeat("system prompt ", 3000n)}, None{}, Some{exampleTool() <> Nil{}}, None{}, n(1)}}}

def systemContext() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "s1", systemWithTools())
    s2 : SM() <- say(s1, "u1", user("ask"))
    s3 : SM() <- say(s2, "a1", assistant("done"))
    s4 : SM() <- edit(s3, "e1", "u1", text("ask"))
    value : Estimate.ContextUsageEstimate <- estimate(s4)
    return above(tokensOf(value), 10000)

def keptAt(value: Maybe<&2, Compaction.CompactionPreparation<Unit, Unit, V.Value>>) -> String:
  match value:
    case Some{Compaction.CompactionPreparation{firstKept, _, _, _, _, _, _, _}}: firstKept
    case None{}: "none"

def mentions(value: Maybe<&2, Compaction.CompactionPreparation<Unit, Unit, V.Value>>, +needle: String) -> Bool:
  match value:
    case Some{Compaction.CompactionPreparation{_, summarized, prefix, _, _, _, _, _}}: String.contains(described(summarized), needle) || String.contains(described(prefix), needle)
    case None{}: False{}

def keptWithout(+prepared: Maybe<&2, Compaction.CompactionPreparation<Unit, Unit, V.Value>>, kept: String, needle: String) -> Bool:
  String.eq(keptAt(prepared), kept) && Bool.not(mentions(prepared, needle))

def preparedWithout(+prepared: Maybe<&2, Compaction.CompactionPreparation<Unit, Unit, V.Value>>, needle: String) -> Bool:
  Maybe.is_some(&2, Compaction.CompactionPreparation<Unit, Unit, V.Value>, prepared) && Bool.not(mentions(prepared, needle))

def boundaryReplacement() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user("old request"))
    s2 : SM() <- say(s1, "a1", assistant("old answer"))
    s3 : SM() <- say(s2, "u2", user("original input"))
    s4 : SM() <- say(s3, "a2", assistant("answered original input"))
    s5 : SM() <- edit(s4, "e1", "u2", text(String.repeat("NEW-INSTRUCTION ", 100n)))
    s6 : SM() <- edit(s5, "e2", "a2", None{})
    s7 : SM() <- bookkeeping(s6, "x1")
    path : List<&2, Entry()> <- branch(s7)
    return keptWithout(prepare(path), "u2", "NEW-INSTRUCTION")

def unsentInput() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user("old request"))
    s2 : SM() <- say(s1, "a1", assistant("old answer"))
    s3 : SM() <- customMessage(s2, "m1", "next-work", String.repeat("UNSENT-INSTRUCTION ", 100n))
    s4 : SM() <- bookkeeping(s3, "x1")
    path : List<&2, Entry()> <- branch(s4)
    return keptWithout(prepare(path), "m1", "UNSENT-INSTRUCTION")

def omittedCustom() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user(String.repeat("unanswered input ", 100n)))
    s2 : SM() <- customMessage(s1, "m1", "temporary", "temporary context")
    s3 : SM() <- edit(s2, "e1", "m1", None{})
    path : List<&2, Entry()> <- branch(s3)
    return Maybe.is_none(&2, Compaction.CompactionPreparation<Unit, Unit, V.Value>, prepare(path))

def prefixIsRecoveryInput(value: Maybe<&2, Compaction.CompactionPreparation<Unit, Unit, V.Value>>) -> Bool:
  match value:
    case Some{Compaction.CompactionPreparation{_, summarized, Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{input}, _}}} <> Nil{}, _, _, _, _, _}}: String.contains(input, "recovery input") && Bool.not(String.contains(described(summarized), "recovery input"))
    case _: False{}

def recoveredAt(+prepared: Maybe<&2, Compaction.CompactionPreparation<Unit, Unit, V.Value>>) -> Bool:
  String.eq(keptAt(prepared), "a1") && prefixIsRecoveryInput(prepared)

def recoverySuffix() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user(String.repeat("recovery input ", 100n)))
    s2 : SM() <- say(s1, "a1", assistant("failed attempt"))
    s3 : SM() <- edit(s2, "e1", "a1", None{})
    s4 : SM() <- bookkeeping(s3, "x1")
    path : List<&2, Entry()> <- branch(s4)
    return recoveredAt(prepare(path))

def editedContent() -> Checked():
  do Result<&2, &2, S.Error, Bool>:
    s0 : SM() <- fresh()
    s1 : SM() <- say(s0, "u1", user(String.repeat("OMIT-ME ", 100n)))
    s2 : SM() <- say(s1, "a1", assistant(String.repeat("old answer ", 100n)))
    s3 : SM() <- edit(s2, "e1", "u1", None{})
    s4 : SM() <- say(s3, "u2", user("keep"))
    s5 : SM() <- say(s4, "a2", assistant("suffix"))
    path : List<&2, Entry()> <- branch(s5)
    return preparedWithout(prepare(path), "OMIT-ME")

def check(result: Checked(), name: String) -> IO(Unit):
  match result:
    case Done{True{}}: IO.print("PASS " ++ name)
    case Done{False{}}: IO.die(Unit, 1, "FAIL " ++ name)
    case Fail{_}: IO.die(Unit, 1, "FAIL " ++ name ++ ": session error")

def main() -> IO(Unit):
  do IO<Unit>:
    check(omitsTarget(), "omits a target only from model projection")
    check(latestEditWins(), "replaces only content and lets the latest edit win")
    check(normalizesStrings(), "normalizes string replacements for array-only assistant and tool-result roles")
    check(normalizesImported(), "normalizes imported string replacements while projecting array-only roles")
    check(branchRelative(), "keeps edits branch-relative")
    check(selfReferencing(), "uses a self-referencing compaction to retain no preceding entries")
    check(postCompactionEdits(), "applies post-compaction edits to retained pre-compaction entries")
    check(newestSummary(), "uses only the newest summary when a repeated compaction retains entries before the older compaction")
    check(repeatedRetainNone(), "supports repeated retain-none compactions")
    check(preEditUsage(), "does not trust pre-edit assistant usage for projected context estimates")
    check(postEditUsage(), "uses assistant usage captured after the latest context edit")
    check(usageAfterCompaction(), "does not reuse post-edit assistant usage after a later compaction")
    check(systemContext(), "includes effective system and tool context in edited estimates")
    check(boundaryReplacement(), "does not advance past a boundary replacement of the candidate input")
    check(unsentInput(), "does not let metadata move the cut past unsent boundary input")
    check(omittedCustom(), "does not treat an omitted custom message as a recovery attempt")
    check(recoverySuffix(), "advances past input for an omitted assistant recovery suffix with metadata")
    check(editedContent(), "prepares compaction from edited model content")

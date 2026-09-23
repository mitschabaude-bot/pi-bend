import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/utils/estimate.bend as Estimate
import ../../../../ai/src/utils/retry.bend as Retry
import ../../../../ai/src/utils/text.bend as Text
import ../../../../ai/src/utils/transcript.bend as Transcript
import ../../../../runtime/src/abort.bend as A
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/string.bend as Set
import ../messages.bend as Messages
import ../session-manager.bend as S
import ./utils.bend as Utils

# pi `compaction/compaction.ts`: context accounting, the cut point that
# keeps recent turns, preparation of what to summarize, and the summary
# generation. The summarizer is injected: the caller supplies a callback
# that turns a summarization request (transcript context and token cap)
# into an assistant message, as upstream injects `streamFn`.

def Msg(-D: Data, -T: Data, -C: Data) -> Data: Agent.AgentMessage<D, T, Messages.CodingMessage<C>>
def Entry(-D: Data, -T: Data, -C: Data) -> Data: S.SessionEntry<D, T, C>
def Assistant(-D: Data) -> Data: Ai.AssistantMessage<V.Value, D>

type CompactionDetails is Data:
  CompactionDetails{readFiles: List<&2, String>, modifiedFiles: List<&2, String>}

type CompactionResult is Data:
  CompactionResult{summary: String, firstKeptEntryId: String, tokensBefore: F64, estimatedTokensAfter: Maybe<&2, F64>, usage: Maybe<&2, Ai.Usage>, details: Maybe<&2, CompactionDetails>}

type CompactionSettings is Data:
  CompactionSettings{enabled: Bool, reserveTokens: F64, keepRecentTokens: F64}

def DEFAULT_COMPACTION_SETTINGS() -> CompactionSettings: CompactionSettings{True{}, F.fromU32(16384), F.fromU32(20000)}

def zero() -> F64: F.fromU32(0)

# Context accounting
# ------------------

def calculateContextTokens(usage: Ai.Usage) -> F64: Estimate.calculateContextTokens(usage)

def countedUsage(stopReason: Ai.StopReason, +usage: Ai.Usage) -> Maybe<&2, Ai.Usage>:
  match stopReason:
    case Ai.Aborted{}: None{}
    case Ai.Error{}: None{}
    case _: Bool.pick(Maybe<&2, Ai.Usage>, F.isGreater(F.compare(calculateContextTokens(usage), zero())), Some{usage}, None{})

def getAssistantUsage(-D: Data, -T: Data, -C: Data, message: Msg(D, T, C)) -> Maybe<&2, Ai.Usage>:
  match message:
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, _, _, _, _, _, _, _, usage, stopReason, _, _, _, _, _}}}: countedUsage(stopReason, usage)
    case _: None{}

def lastUsageIn(-D: Data, -T: Data, -C: Data, entries: List<&2, Entry(D, T, C)>, found: Maybe<&2, Ai.Usage>) -> Maybe<&2, Ai.Usage>:
  match entries:
    case Nil{}: found
    case S.SessionMessageEntry{_, message} <> rest: lastUsageIn(D, T, C, rest, Maybe.default(&2, Maybe<&2, Ai.Usage>, Maybe.map(&2, Ai.Usage, Maybe<&2, Ai.Usage>, usage => Some{usage}, getAssistantUsage(D, T, C, message)), found))
    case _ <> rest: lastUsageIn(D, T, C, rest, found)

# The usage of the last assistant message that finished with tokens.
def getLastAssistantUsage(-D: Data, -T: Data, -C: Data, entries: List<&2, Entry(D, T, C)>) -> Maybe<&2, Ai.Usage>:
  lastUsageIn(D, T, C, entries, None{})

def ESTIMATED_IMAGE_CHARS() -> F64: F.fromU32(4800)

def contentChars(content: Ai.UserContent) -> F64:
  match content:
    case Ai.UserText{text}: Estimate.textChars(text)
    case Ai.UserBlocks{blocks}: Estimate.blockChars(blocks, zero())

def assistantChars(blocks: List<&2, Ai.AssistantContent<V.Value>>, chars: F64) -> F64:
  match blocks:
    case Nil{}: chars
    case Ai.AssistantText{Ai.TextContent{text, _}} <> rest: assistantChars(rest, F.add(chars, Estimate.textChars(text)))
    case Ai.AssistantThinking{Ai.ThinkingContent{thinking, _, _}} <> rest: assistantChars(rest, F.add(chars, Estimate.textChars(thinking)))
    case Ai.AssistantToolCall{Ai.ToolCall{_, name, arguments, _, _}} <> rest: assistantChars(rest, F.add(chars, F.add(Estimate.textChars(name), Estimate.textChars(Utils.jsonText(arguments)))))

# Rough token count of one context message: characters over four, rounded up.
def estimateTokens(-D: Data, -T: Data, -C: Data, message: Msg(D, T, C)) -> F64:
  match message:
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{content, _}}}: Estimate.tokensForChars(contentChars(content))
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}}: Estimate.tokensForChars(assistantChars(content, zero()))
    case Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{_, _, content, _, _, _, _}}}: Estimate.tokensForChars(Estimate.blockChars(content, zero()))
    case Agent.LlmMessage{Ai.System{_}}: zero()
    case Agent.CustomMessage{Messages.Custom{Messages.CustomMessage{_, content, _, _, _}}}: Estimate.tokensForChars(contentChars(content))
    case Agent.CustomMessage{Messages.BashExecution{Messages.BashExecutionMessage{command, output, _, _, _, _, _, _}}}: Estimate.tokensForChars(F.add(Estimate.textChars(command), Estimate.textChars(output)))
    case Agent.CustomMessage{Messages.BranchSummary{Messages.BranchSummaryMessage{summary, _, _}}}: Estimate.tokensForChars(Estimate.textChars(summary))
    case Agent.CustomMessage{Messages.CompactionSummary{Messages.CompactionSummaryMessage{summary, _, _}}}: Estimate.tokensForChars(Estimate.textChars(summary))

def estimateMessagesTokens(-D: Data, -T: Data, -C: Data, messages: List<&2, Msg(D, T, C)>, total: F64) -> F64:
  match messages:
    case Nil{}: total
    case message <> rest: estimateMessagesTokens(D, T, C, rest, F.add(total, estimateTokens(D, T, C, message)))

type EstimateState is Data:
  EstimateState{index: Nat, usageTokens: F64, trailing: F64, lastUsageIndex: Maybe<&2, Nat>, estimated: F64}

def anchored(state: EstimateState, usage: Maybe<&2, Ai.Usage>, +tokens: F64) -> EstimateState:
  match state usage:
    case EstimateState{+index, _, _, _, estimated} Some{value}: EstimateState{Nat.add(index, 1n), calculateContextTokens(value), zero(), Some{index}, F.add(estimated, tokens)}
    case EstimateState{index, usageTokens, trailing, last, estimated} None{}: EstimateState{Nat.add(index, 1n), usageTokens, F.add(trailing, tokens), last, F.add(estimated, tokens)}

def estimateResult(state: EstimateState) -> Estimate.ContextUsageEstimate:
  match state:
    case EstimateState{_, _, _, None{}, +estimated}: Estimate.ContextUsageEstimate{estimated, zero(), estimated, None{}}
    case EstimateState{_, +usageTokens, +trailing, Some{index}, _}: Estimate.ContextUsageEstimate{F.add(usageTokens, trailing), usageTokens, trailing, Some{index}}

# The last counted assistant usage anchors the estimate; later messages add
# their estimated tokens. Without usage, every message is estimated.

def estimateFrom(-D: Data, -T: Data, -C: Data, messages: List<&2, Msg(D, T, C)>, state: EstimateState) -> Estimate.ContextUsageEstimate:
  match messages:
    case Nil{}: estimateResult(state)
    case +message <> rest: estimateFrom(D, T, C, rest, anchored(state, getAssistantUsage(D, T, C, message), estimateTokens(D, T, C, message)))

def estimateContextTokens(-D: Data, -T: Data, -C: Data, messages: List<&2, Msg(D, T, C)>) -> Estimate.ContextUsageEstimate:
  estimateFrom(D, T, C, messages, EstimateState{0n, zero(), zero(), None{}, zero()})

def shouldCompact(contextTokens: F64, contextWindow: F64, settings: CompactionSettings) -> Bool:
  match settings:
    case CompactionSettings{enabled, reserveTokens, _}: Bool.and(enabled, F.isGreater(F.compare(contextTokens, F.subtract(contextWindow, reserveTokens))))

# Cut points
# ----------

def isCutPointMessage(-D: Data, -T: Data, -C: Data, message: Msg(D, T, C)) -> Bool:
  match message:
    case Agent.LlmMessage{Ai.ToolResult{_}}: False{}
    case Agent.LlmMessage{Ai.System{_}}: False{}
    case _: True{}

def isTurnStartMessage(-D: Data, -T: Data, -C: Data, message: Msg(D, T, C)) -> Bool:
  match message:
    case Agent.LlmMessage{Ai.User{_}}: True{}
    case Agent.CustomMessage{_}: True{}
    case _: False{}

# Entries never fail to convert here; a failure counts as no messages.
def contextMessages(-D: Data, -T: Data, -C: Data, entry: Entry(D, T, C)) -> List<&2, Msg(D, T, C)>:
  Result.default(&2, &2, S.Error, List<&2, Msg(D, T, C)>, S.sessionEntryToContextMessages(D, T, C, entry), Nil{})

def anyTurnStart(-D: Data, -T: Data, -C: Data, messages: List<&2, Msg(D, T, C)>) -> Bool:
  match messages:
    case Nil{}: False{}
    case message <> rest: Bool.pick(Unit -> Bool, isTurnStartMessage(D, T, C, message), _ => True{}, _ => anyTurnStart(D, T, C, rest))(Unit{})

def anyCutPoint(-D: Data, -T: Data, -C: Data, messages: List<&2, Msg(D, T, C)>) -> Bool:
  match messages:
    case Nil{}: False{}
    case message <> rest: Bool.pick(Unit -> Bool, isCutPointMessage(D, T, C, message), _ => True{}, _ => anyCutPoint(D, T, C, rest))(Unit{})

def isCompactionEntry(-D: Data, -T: Data, -C: Data, entry: Entry(D, T, C)) -> Bool:
  match entry:
    case S.Compaction{_}: True{}
    case _: False{}

def isTurnStartEntry(-D: Data, -T: Data, -C: Data, entry: Entry(D, T, C)) -> Bool:
  match entry:
    case S.Compaction{_}: False{}
    case other: anyTurnStart(D, T, C, contextMessages(D, T, C, other))

def isCutPointEntry(-D: Data, -T: Data, -C: Data, entry: Entry(D, T, C)) -> Bool:
  match entry:
    case S.Compaction{_}: False{}
    case other: anyCutPoint(D, T, C, contextMessages(D, T, C, other))

type Indexed<-D: Data, -T: Data, -C: Data> is Data:
  Indexed{index: Nat, entry: Entry(D, T, C)}

def indexedFrom(-D: Data, -T: Data, -C: Data, entries: List<&2, Entry(D, T, C)>, +index: Nat) -> List<&2, Indexed<D, T, C>>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: Indexed{index, entry} <> indexedFrom(D, T, C, rest, Nat.add(index, 1n))

def within(+startIndex: Nat, +endIndex: Nat, +index: Nat) -> Bool:
  Bool.and(Bool.not(Nat.is_lt(index, startIndex)), Nat.is_lt(index, endIndex))

def findValidCutPoints(-D: Data, -T: Data, -C: Data, indexed: List<&2, Indexed<D, T, C>>, +startIndex: Nat, +endIndex: Nat) -> List<&2, Nat>:
  match indexed:
    case Nil{}: Nil{}
    case Indexed{+index, entry} <> rest:
      +tail = findValidCutPoints(D, T, C, rest, startIndex, endIndex)
      Bool.pick(List<&2, Nat>, Bool.and(within(startIndex, endIndex, index), isCutPointEntry(D, T, C, entry)), index <> tail, tail)

# The latest turn start at or before entryIndex, no earlier than startIndex.
def findTurnStartIndex(-D: Data, -T: Data, -C: Data, indexed: List<&2, Indexed<D, T, C>>, +entryIndex: Nat, +startIndex: Nat, found: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match indexed:
    case Nil{}: found
    case Indexed{+index, entry} <> rest: findTurnStartIndex(D, T, C, rest, entryIndex, startIndex, Bool.pick(Maybe<&2, Nat>, Bool.and(within(startIndex, Nat.add(entryIndex, 1n), index), isTurnStartEntry(D, T, C, entry)), Some{index}, found))

type CutPointResult is Data:
  CutPointResult{firstKeptEntryIndex: Nat, turnStartIndex: Maybe<&2, Nat>, isSplitTurn: Bool}

def entryTokens(-D: Data, -T: Data, -C: Data, entry: Entry(D, T, C)) -> F64:
  estimateMessagesTokens(D, T, C, contextMessages(D, T, C, entry), zero())

def firstCutAtOrAfter(cutPoints: List<&2, Nat>, +index: Nat, fallback: Nat) -> Nat:
  match cutPoints:
    case Nil{}: fallback
    case +point <> rest: Bool.pick(Nat, Nat.is_lt(point, index), firstCutAtOrAfter(rest, index, fallback), point)

# Walk the range backwards accumulating estimated tokens; the cut is the
# first cut point at or after the entry that crosses the recent budget.
def accumulateCut(-D: Data, -T: Data, -C: Data, reversed: List<&2, Indexed<D, T, C>>, +accumulated: F64, +keepRecentTokens: F64, +cutPoints: List<&2, Nat>, +fallback: Nat) -> Nat:
  match reversed:
    case Nil{}: fallback
    case Indexed{index, entry} <> +rest:
      +tokens = entryTokens(D, T, C, entry)
      +next = F.add(accumulated, tokens)
      Bool.pick(Unit -> Nat, F.isEqual(F.compare(tokens, zero())), _ => accumulateCut(D, T, C, rest, accumulated, keepRecentTokens, cutPoints, fallback), _ => Bool.pick(Unit -> Nat, F.isAtLeast(F.compare(next, keepRecentTokens)), _ => firstCutAtOrAfter(cutPoints, index, fallback), _ => accumulateCut(D, T, C, rest, next, keepRecentTokens, cutPoints, fallback))(Unit{}))(Unit{})

def rangeReversed(-D: Data, -T: Data, -C: Data, indexed: List<&2, Indexed<D, T, C>>, +startIndex: Nat, +endIndex: Nat, +reversed: List<&2, Indexed<D, T, C>>) -> List<&2, Indexed<D, T, C>>:
  match indexed:
    case Nil{}: reversed
    case Indexed{+index, entry} <> rest: rangeReversed(D, T, C, rest, startIndex, endIndex, Bool.pick(List<&2, Indexed<D, T, C>>, within(startIndex, endIndex, index), Indexed{index, entry} <> reversed, reversed))

def entryAt(-D: Data, -T: Data, -C: Data, entries: List<&2, Entry(D, T, C)>, index: Nat) -> Maybe<&2, Entry(D, T, C)>:
  List.get(&2, Entry(D, T, C), entries, index)

def keepsContext(-D: Data, -T: Data, -C: Data, previous: Maybe<&2, Entry(D, T, C)>) -> Bool:
  match previous:
    case None{}: True{}
    case Some{S.Compaction{_}}: True{}
    case Some{entry}: Bool.not(List.is_empty(&2, Msg(D, T, C), contextMessages(D, T, C, entry)))

# Entries without context messages before the cut are kept too.
def slideBack(-D: Data, -T: Data, -C: Data, fuel: Nat, +entries: List<&2, Entry(D, T, C)>, +cutIndex: Nat, +startIndex: Nat) -> Nat:
  match fuel:
    case 0n: cutIndex
    case 1n+rest: Bool.pick(Unit -> Nat, Bool.or(Bool.not(Nat.is_gt(cutIndex, startIndex)), keepsContext(D, T, C, entryAt(D, T, C, entries, Nat.sub(cutIndex, 1n)))), _ => cutIndex, _ => slideBack(D, T, C, rest, entries, Nat.sub(cutIndex, 1n), startIndex))(Unit{})

def cutResult(-D: Data, -T: Data, -C: Data, indexed: List<&2, Indexed<D, T, C>>, cutEntry: Maybe<&2, Entry(D, T, C)>, +cutIndex: Nat, startIndex: Nat) -> CutPointResult:
  match cutEntry:
    case None{}: CutPointResult{cutIndex, None{}, False{}}
    case Some{entry}:
      +startsTurn = isTurnStartEntry(D, T, C, entry)
      +turnStart = Bool.pick(Maybe<&2, Nat>, startsTurn, None{}, findTurnStartIndex(D, T, C, indexed, cutIndex, startIndex, None{}))
      CutPointResult{cutIndex, turnStart, Bool.and(Bool.not(startsTurn), Bool.not(Maybe.is_none(&2, Nat, turnStart)))}

def cutFrom(-D: Data, -T: Data, -C: Data, +entries: List<&2, Entry(D, T, C)>, +indexed: List<&2, Indexed<D, T, C>>, +startIndex: Nat, +endIndex: Nat, keepRecentTokens: F64, cutPoints: List<&2, Nat>) -> CutPointResult:
  match cutPoints:
    case Nil{}: CutPointResult{startIndex, None{}, False{}}
    case +first <> rest:
      +cutIndex = slideBack(D, T, C, endIndex, entries, accumulateCut(D, T, C, rangeReversed(D, T, C, indexed, startIndex, endIndex, Nil{}), zero(), keepRecentTokens, first <> rest, first), startIndex)
      cutResult(D, T, C, indexed, entryAt(D, T, C, entries, cutIndex), cutIndex, startIndex)

def findCutPoint(-D: Data, -T: Data, -C: Data, +entries: List<&2, Entry(D, T, C)>, +startIndex: Nat, +endIndex: Nat, keepRecentTokens: F64) -> CutPointResult:
  +indexed = indexedFrom(D, T, C, entries, 0n)
  cutFrom(D, T, C, entries, indexed, startIndex, endIndex, keepRecentTokens, findValidCutPoints(D, T, C, indexed, startIndex, endIndex))

# Preparation
# -----------

type CompactionPreparation<-D: Data, -T: Data, -C: Data> is Data:
  CompactionPreparation{firstKeptEntryId: String, messagesToSummarize: List<&2, Msg(D, T, C)>, turnPrefixMessages: List<&2, Msg(D, T, C)>, isSplitTurn: Bool, tokensBefore: F64, previousSummary: Maybe<&2, String>, fileOps: Utils.FileOperations, settings: CompactionSettings}

def lastCompactionIndex(-D: Data, -T: Data, -C: Data, indexed: List<&2, Indexed<D, T, C>>, found: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match indexed:
    case Nil{}: found
    case Indexed{index, S.Compaction{_}} <> rest: lastCompactionIndex(D, T, C, rest, Some{index})
    case _ <> rest: lastCompactionIndex(D, T, C, rest, found)

def indexOfId(-D: Data, -T: Data, -C: Data, indexed: List<&2, Indexed<D, T, C>>, +id: String) -> Maybe<&2, Nat>:
  match indexed:
    case Nil{}: None{}
    case Indexed{index, entry} <> rest: Bool.pick(Unit -> Maybe<&2, Nat>, String.eq(S.entryId(D, T, C, entry), id), _ => Some{index}, _ => indexOfId(D, T, C, rest, id))(Unit{})

def compactionOf(-D: Data, -T: Data, -C: Data, entry: Maybe<&2, Entry(D, T, C)>) -> Maybe<&2, S.CompactionEntry<C>>:
  match entry:
    case Some{S.Compaction{value}}: Some{value}
    case _: None{}

def firstConversation(-D: Data, -T: Data, -C: Data, messages: List<&2, Msg(D, T, C)>) -> Maybe<&2, Msg(D, T, C)>:
  match messages:
    case Agent.LlmMessage{Ai.System{_}} <> _: None{}
    case message <> _: Some{message}
    case Nil{}: None{}


# The first context message of an entry, unless it is a system message.
def messageForCompaction(-D: Data, -T: Data, -C: Data, entry: Entry(D, T, C)) -> Maybe<&2, Msg(D, T, C)>:
  match entry:
    case S.Compaction{_}: None{}
    case other: firstConversation(D, T, C, contextMessages(D, T, C, other))

def prependMaybe(-D: Data, -T: Data, -C: Data, message: Maybe<&2, Msg(D, T, C)>, rest: List<&2, Msg(D, T, C)>) -> List<&2, Msg(D, T, C)>:
  match message:
    case None{}: rest
    case Some{value}: value <> rest

def messagesInRange(-D: Data, -T: Data, -C: Data, indexed: List<&2, Indexed<D, T, C>>, +startIndex: Nat, +endIndex: Nat) -> List<&2, Msg(D, T, C)>:
  match indexed:
    case Nil{}: Nil{}
    case Indexed{+index, entry} <> rest:
      +tail = messagesInRange(D, T, C, rest, startIndex, endIndex)
      Bool.pick(List<&2, Msg(D, T, C)>, within(startIndex, endIndex, index), prependMaybe(D, T, C, messageForCompaction(D, T, C, entry), tail), tail)

def seededOps(details: Maybe<&2, CompactionDetails>) -> Utils.FileOperations:
  match details:
    case None{}: Utils.createFileOps()
    case Some{CompactionDetails{readFiles, modifiedFiles}}: Utils.FileOperations{Utils.insertAll(readFiles, Set.empty()), Set.empty(), Utils.insertAll(modifiedFiles, Set.empty())}

def previousDetails(~C: Data, ~compactionDetails: C -> Maybe<&2, CompactionDetails>, previous: Maybe<&2, S.CompactionEntry<C>>) -> Maybe<&2, CompactionDetails>:
  match previous:
    case Some{S.CompactionEntry{_, _, _, _, Some{details}, _, fromHook, _}}: Bool.pick(Maybe<&2, CompactionDetails>, Maybe.default(&2, Bool, fromHook, False{}), None{}, compactionDetails(details))
    case _: None{}

def previousSummaryOf(-C: Data, previous: Maybe<&2, S.CompactionEntry<C>>) -> Maybe<&2, String>:
  match previous:
    case Some{S.CompactionEntry{_, summary, _, _, _, _, _, _}}: Some{summary}
    case None{}: None{}

def previousKept(-C: Data, previous: Maybe<&2, S.CompactionEntry<C>>) -> Maybe<&2, String>:
  match previous:
    case Some{S.CompactionEntry{_, _, firstKeptEntryId, _, _, _, _, _}}: Some{firstKeptEntryId}
    case None{}: None{}

def boundaryStartOf(previousIndex: Maybe<&2, Nat>, keptIndex: Maybe<&2, Nat>) -> Nat:
  match previousIndex keptIndex:
    case None{} _: 0n
    case Some{_} Some{index}: index
    case Some{index} None{}: Nat.add(index, 1n)

def estimateTokensOf(estimate: Estimate.ContextUsageEstimate) -> F64:
  match estimate:
    case Estimate.ContextUsageEstimate{tokens, _, _, _}: tokens


def contextTokensOf(-D: Data, -T: Data, -C: Data, context: Result<&2, &2, S.Error, S.SessionContext<D, T, C>>) -> F64:
  match context:
    case Done{S.SessionContext{messages, _, _}}: estimateTokensOf(estimateContextTokens(D, T, C, messages))
    case Fail{_}: zero()

def historyEndOf(cut: CutPointResult) -> Nat:
  match cut:
    case CutPointResult{firstKept, Some{turnStart}, True{}}: turnStart
    case CutPointResult{firstKept, _, _}: firstKept

# The split turn's prefix: from its turn start up to the first kept entry.
type Range is Data:
  Range{start: Nat, end: Nat}

def prefixRange(cut: CutPointResult) -> Maybe<&2, Range>:
  match cut:
    case CutPointResult{firstKept, Some{turnStart}, True{}}: Some{Range{turnStart, firstKept}}
    case _: None{}

def prefixMessages(-D: Data, -T: Data, -C: Data, indexed: List<&2, Indexed<D, T, C>>, range: Maybe<&2, Range>) -> List<&2, Msg(D, T, C)>:
  match range:
    case None{}: Nil{}
    case Some{Range{turnStart, firstKept}}: messagesInRange(D, T, C, indexed, turnStart, firstKept)

def isCompactionLast(-D: Data, -T: Data, -C: Data, last: Maybe<&2, Entry(D, T, C)>) -> Bool:
  match last:
    case Some{S.Compaction{_}}: True{}
    case _: False{}

def lastIsCompaction(-D: Data, -T: Data, -C: Data, entries: List<&2, Entry(D, T, C)>) -> Bool:
  isCompactionLast(D, T, C, List.last(&2, Entry(D, T, C), entries))

def preparation(-D: Data, -T: Data, -C: Data, firstKeptEntryId: Maybe<&2, String>, +messagesToSummarize: List<&2, Msg(D, T, C)>, +turnPrefixMessages: List<&2, Msg(D, T, C)>, isSplitTurn: Bool, tokensBefore: F64, previousSummary: Maybe<&2, String>, seeded: Utils.FileOperations, settings: CompactionSettings) -> Maybe<&2, CompactionPreparation<D, T, C>>:
  match firstKeptEntryId:
    case None{}: None{}
    case Some{id}:
      Bool.pick(Unit -> Maybe<&2, CompactionPreparation<D, T, C>>, Bool.and(List.is_empty(&2, Msg(D, T, C), messagesToSummarize), List.is_empty(&2, Msg(D, T, C), turnPrefixMessages)), _ => None{}, _ => Some{CompactionPreparation{id, messagesToSummarize, turnPrefixMessages, isSplitTurn, tokensBefore, previousSummary, Utils.extractFileOpsFromMessages(D, T, Messages.CodingMessage<C>, turnPrefixMessages, Utils.extractFileOpsFromMessages(D, T, Messages.CodingMessage<C>, messagesToSummarize, seeded)), settings}})(Unit{})

def keepRecentTokensOf(settings: CompactionSettings) -> F64:
  match settings:
    case CompactionSettings{_, _, keepRecentTokens}: keepRecentTokens


def reserveTokensOf(settings: CompactionSettings) -> F64:
  match settings:
    case CompactionSettings{_, reserveTokens, _}: reserveTokens


def firstKeptIndexOf(cut: CutPointResult) -> Nat:
  match cut:
    case CutPointResult{index, _, _}: index


def isSplitOf(cut: CutPointResult) -> Bool:
  match cut:
    case CutPointResult{_, _, split}: split

# upstream prepareCompaction: nothing to do right after a compaction or when
# the recent window covers everything; the previous compaction's summary and
# file lists seed the next one.

def prepareFrom(~D: Data, ~T: Data, ~C: Data, ~compactionDetails: C -> Maybe<&2, CompactionDetails>, +entries: List<&2, Entry(D, T, C)>, +settings: CompactionSettings, +previous: Maybe<&2, S.CompactionEntry<C>>, previousIndex: Maybe<&2, Nat>) -> Maybe<&2, CompactionPreparation<D, T, C>>:
  +indexed = indexedFrom(D, T, C, entries, 0n)
  +boundaryStart = boundaryStartOf(previousIndex, Maybe.bind(&2, String, Nat, previousKept(C, previous), id => indexOfId(D, T, C, indexed, id)))
  +boundaryEnd = List.length(&2, Entry(D, T, C), entries)
  +cut = findCutPoint(D, T, C, entries, boundaryStart, boundaryEnd, keepRecentTokensOf(settings))
  preparation(D, T, C, Maybe.map(&2, Entry(D, T, C), String, entry => S.entryId(D, T, C, entry), entryAt(D, T, C, entries, firstKeptIndexOf(cut))), messagesInRange(D, T, C, indexed, boundaryStart, historyEndOf(cut)), prefixMessages(D, T, C, indexed, prefixRange(cut)), isSplitOf(cut), contextTokensOf(D, T, C, S.contextFromPath(D, T, C, entries)), previousSummaryOf(C, previous), seededOps(previousDetails(~C, ~compactionDetails, previous)), settings)

def prepareCompaction(~D: Data, ~T: Data, ~C: Data, ~compactionDetails: C -> Maybe<&2, CompactionDetails>, +pathEntries: List<&2, Entry(D, T, C)>, settings: CompactionSettings) -> Maybe<&2, CompactionPreparation<D, T, C>>:
  +previousIndex = lastCompactionIndex(D, T, C, indexedFrom(D, T, C, pathEntries, 0n), None{})
  Bool.pick(Unit -> Maybe<&2, CompactionPreparation<D, T, C>>, lastIsCompaction(D, T, C, pathEntries), _ => None{}, _ => prepareFrom(~D, ~T, ~C, ~compactionDetails, pathEntries, settings, compactionOf(D, T, C, Maybe.bind(&2, Nat, Entry(D, T, C), previousIndex, index => entryAt(D, T, C, pathEntries, index))), previousIndex))(Unit{})

# Summarization
# -------------

def SUMMARIZATION_PROMPT() -> String:
  "The messages above are a conversation to summarize. Create a structured context checkpoint summary that another LLM will use to continue the work.\n\nUse this EXACT format:\n\n## Goal\n[What is the user trying to accomplish? Can be multiple items if the session covers different tasks.]\n\n## Constraints & Preferences\n- [Any constraints, preferences, or requirements mentioned by user]\n- [Or \"(none)\" if none were mentioned]\n\n## Progress\n### Done\n- [x] [Completed tasks/changes]\n\n### In Progress\n- [ ] [Current work]\n\n### Blocked\n- [Issues preventing progress, if any]\n\n## Key Decisions\n- **[Decision]**: [Brief rationale]\n\n## Next Steps\n1. [Ordered list of what should happen next]\n\n## Critical Context\n- [Any data, examples, or references needed to continue]\n- [Or \"(none)\" if not applicable]\n\nKeep each section concise. Preserve exact file paths, function names, and error messages."

def UPDATE_SUMMARIZATION_INSTRUCTIONS() -> String:
  "Update the existing structured summary with new information. RULES:\n- PRESERVE all existing information from the previous summary\n- ADD new progress, decisions, and context from the new messages\n- UPDATE the Progress section: move items from \"In Progress\" to \"Done\" when completed\n- UPDATE \"Next Steps\" based on what was accomplished\n- PRESERVE exact file paths, function names, and error messages\n- If something is no longer relevant, you may remove it\n\nUse this EXACT format:\n\n## Goal\n[Preserve existing goals, add new ones if the task expanded]\n\n## Constraints & Preferences\n- [Preserve existing, add new ones discovered]\n\n## Progress\n### Done\n- [x] [Include previously done items AND newly completed items]\n\n### In Progress\n- [ ] [Current work - update based on progress]\n\n### Blocked\n- [Current blockers - remove if resolved]\n\n## Key Decisions\n- **[Decision]**: [Brief rationale] (preserve all previous, add new)\n\n## Next Steps\n1. [Update based on current state]\n\n## Critical Context\n- [Preserve important context, add new if needed]\n\nKeep each section concise. Preserve exact file paths, function names, and error messages."

def UPDATE_SUMMARIZATION_PROMPT() -> String:
  "The messages above are NEW conversation messages to incorporate into the existing summary provided in <previous-summary> tags.\n\n" ++ UPDATE_SUMMARIZATION_INSTRUCTIONS()

def TURN_PREFIX_SUMMARIZATION_PROMPT() -> String:
  "This is the PREFIX of a turn that was too large to keep. The SUFFIX (recent work) is retained.\n\nSummarize the prefix to provide context for the retained suffix:\n\n## Original Request\n[What did the user ask for in this turn?]\n\n## Early Progress\n- [Key decisions and work done in the prefix]\n\n## Context for Suffix\n- [Information needed to understand the retained recent work]\n\nBe concise. Focus on what's needed to understand the kept suffix."

def getSummarizationFailure(-D: Data, response: Assistant(D), label: String) -> Maybe<&2, String>:
  match response:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Error{}, _, errorMessage, _, _, _}: Some{label ++ " failed: " ++ Retry.errorTextOf(errorMessage)}
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Length{}, _, _, _, _, _}: Some{label ++ " failed: generation hit the token cap and the summary is incomplete"}
    case _: None{}

# A summarization request: the transcript to complete and its output cap.
# The caller's summarizer adds model, auth, thinking, signal and session id.
type SummaryRequest<-D: Data, -T: Data> is Data:
  SummaryRequest{context: Ai.TranscriptContext<V.Value, V.Value, D, T>, maxTokens: F64}

def Summarizer(-D: Data, -T: Data) -> Data: C.Callback<SummaryRequest<D, T>, Assistant(D)>

type Produce<-D: Data, -T: Data> is Data:
  Produce{summarizer: Summarizer(D, T), request: SummaryRequest<D, T>}

def produceSummary(-D: Data, -T: Data, env: Produce<D, T>) -> IO(Assistant(D)):
  match env:
    case Produce{summarizer, request}: C.call(SummaryRequest<D, T>, Assistant(D), summarizer, request)

def completeSummarization(~D: Data, ~T: Data, summarizer: Summarizer(D, T), request: SummaryRequest<D, T>, retry: Maybe<&2, Retry.RetryPolicy>, signal: Maybe<&2, A.AbortSignal<Unit>>, callbacks: Maybe<&2, Retry.RetryCallbacks()>) -> IO(Assistant(D)):
  Retry.retryAssistantCall(~V.Value, ~D, ~Produce<D, T>, ~(env => produceSummary(D, T, env)), Produce{summarizer, request}, retry, signal, callbacks)

def summarizationContext(-D: Data, -T: Data, promptText: String, now: F64) -> Ai.TranscriptContext<V.Value, V.Value, D, T>:
  Transcript.normalizeContext(V.Value, V.Value, D, T, Ai.Context{Some{Utils.SUMMARIZATION_SYSTEM_PROMPT()}, Ai.User{Ai.UserMessage{Ai.UserBlocks{Ai.TextImageText{Ai.TextContent{promptText, None{}}} <> Nil{}}, now}} <> Nil{}, None{}})

# min(floor(factor * reserve), model max tokens when positive)
def summaryBudget(factor: F64, reserveTokens: F64, +modelMaxTokens: F64) -> F64:
  F.minimum(F.truncate(F.multiply(factor, reserveTokens)), Bool.pick(F64, F.isGreater(F.compare(modelMaxTokens, zero())), modelMaxTokens, F.infinity(False{})))

type Summary is Data:
  Summary{text: String, usage: Ai.Usage}

def hasToolCall(blocks: List<&2, Ai.AssistantContent<V.Value>>) -> Bool:
  match blocks:
    case Nil{}: False{}
    case Ai.AssistantToolCall{_} <> _: True{}
    case _ <> rest: hasToolCall(rest)

def summaryContent(-D: Data, response: Assistant(D), label: String) -> Result<&2, &2, String, Summary>:
  match response:
    case Ai.AssistantMessage{+content, _, _, _, _, _, _, _, usage, _, _, _, _, _, _}:
      Bool.pick(Result<&2, &2, String, Summary>, hasToolCall(content), Fail{label ++ " attempted to call a tool"}, Done{Summary{Text.contentText(V.Value, Text.ContentBlocks{Utils.assistantBlocks(content)}, "\n"), usage}})

def summaryOf(-D: Data, failure: Maybe<&2, String>, response: Assistant(D), label: String) -> Result<&2, &2, String, Summary>:
  match failure:
    case Some{message}: Fail{message}
    case None{}: summaryContent(D, response, label)

def summaryResult(-D: Data, +response: Assistant(D), +label: String) -> Result<&2, &2, String, Summary>:
  summaryOf(D, getSummarizationFailure(D, response, label), response, label)

def withFocus(basePrompt: String, customInstructions: Maybe<&2, String>) -> String:
  match customInstructions:
    case None{}: basePrompt
    case Some{SNil{}}: basePrompt
    case Some{focus}: basePrompt ++ "\n\nAdditional focus: " ++ focus

def previousBlock(previousSummary: Maybe<&2, String>) -> String:
  match previousSummary:
    case None{}: ""
    case Some{SNil{}}: ""
    case Some{summary}: "<previous-summary>\n" ++ summary ++ "\n</previous-summary>\n\n"

def basePromptFor(previousSummary: Maybe<&2, String>) -> String:
  match previousSummary:
    case None{}: SUMMARIZATION_PROMPT()
    case Some{SNil{}}: SUMMARIZATION_PROMPT()
    case Some{_}: UPDATE_SUMMARIZATION_PROMPT()

def conversationBlock(-D: Data, -T: Data, -C: Data, messages: List<&2, Msg(D, T, C)>) -> String:
  "<conversation>\n" ++ Utils.serializeConversation(D, T, Messages.convertToLlm(D, T, C, messages)) ++ "\n</conversation>\n\n"

def summarize(~D: Data, ~T: Data, summarizer: Summarizer(D, T), promptText: String, maxTokens: F64, +label: String, signal: Maybe<&2, A.AbortSignal<Unit>>, retry: Maybe<&2, Retry.RetryPolicy>, callbacks: Maybe<&2, Retry.RetryCallbacks()>) -> IO(Result<&2, &2, String, Summary>):
  do IO<Result<&2, &2, String, Summary>>:
    now : F64 <- Date.now()
    response : Assistant(D) <- completeSummarization(~D, ~T, summarizer, SummaryRequest{summarizationContext(D, T, promptText, now), maxTokens}, retry, signal, callbacks)
    return summaryResult(D, response, label)

# upstream generateSummaryWithUsage: the conversation, an optional previous
# summary and the (update) prompt, within 80% of the reserve.
def generateSummaryWithUsage(~D: Data, ~T: Data, ~C: Data, summarizer: Summarizer(D, T), messages: List<&2, Msg(D, T, C)>, model: Ai.Model<Ai.JsonValue>, reserveTokens: F64, signal: Maybe<&2, A.AbortSignal<Unit>>, customInstructions: Maybe<&2, String>, +previousSummary: Maybe<&2, String>, retry: Maybe<&2, Retry.RetryPolicy>, callbacks: Maybe<&2, Retry.RetryCallbacks()>) -> IO(Result<&2, &2, String, Summary>):
  summarize(~D, ~T, summarizer, conversationBlock(D, T, C, messages) ++ previousBlock(previousSummary) ++ withFocus(basePromptFor(previousSummary), customInstructions), summaryBudget(F.divide(F.fromU32(4), F.fromU32(5)), reserveTokens, Ai.modelMaxTokens(model)), "Summarization", signal, retry, callbacks)

def generateTurnPrefixSummary(~D: Data, ~T: Data, ~C: Data, summarizer: Summarizer(D, T), messages: List<&2, Msg(D, T, C)>, model: Ai.Model<Ai.JsonValue>, reserveTokens: F64, signal: Maybe<&2, A.AbortSignal<Unit>>, retry: Maybe<&2, Retry.RetryPolicy>, callbacks: Maybe<&2, Retry.RetryCallbacks()>) -> IO(Result<&2, &2, String, Summary>):
  summarize(~D, ~T, summarizer, conversationBlock(D, T, C, messages) ++ TURN_PREFIX_SUMMARIZATION_PROMPT(), summaryBudget(F.divide(F.fromU32(1), F.fromU32(2)), reserveTokens, Ai.modelMaxTokens(model)), "Turn prefix summarization", signal, retry, callbacks)

def addMaybe(left: Maybe<&2, F64>, right: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match left right:
    case None{} None{}: None{}
    case Some{a} None{}: Some{a}
    case None{} Some{b}: Some{b}
    case Some{a} Some{b}: Some{F.add(a, b)}

def combineUsage(first: Ai.Usage, second: Ai.Usage) -> Ai.Usage:
  match first second:
    case Ai.Usage{i1, o1, r1, w1, h1, g1, t1, Ai.UsageCost{ci1, co1, cr1, cw1, ct1}} Ai.Usage{i2, o2, r2, w2, h2, g2, t2, Ai.UsageCost{ci2, co2, cr2, cw2, ct2}}:
      Ai.Usage{F.add(i1, i2), F.add(o1, o2), F.add(r1, r2), F.add(w1, w2), addMaybe(h1, h2), addMaybe(g1, g2), F.add(t1, t2), Ai.UsageCost{F.add(ci1, ci2), F.add(co1, co2), F.add(cr1, cr2), F.add(cw1, cw2), F.add(ct1, ct2)}}

def combinedSummary(history: Result<&2, &2, String, Maybe<&2, Summary>>, previousSummary: Maybe<&2, String>, prefix: Result<&2, &2, String, Summary>) -> Result<&2, &2, String, Summary>:
  match history prefix:
    case Fail{message} _: Fail{message}
    case _ Fail{message}: Fail{message}
    case Done{None{}} Done{Summary{prefixText, prefixUsage}}: Done{Summary{Maybe.default(&2, String, previousSummary, "No prior history.") ++ "\n\n---\n\n**Turn Context (split turn):**\n\n" ++ prefixText, prefixUsage}}
    case Done{Some{Summary{historyText, historyUsage}}} Done{Summary{prefixText, prefixUsage}}: Done{Summary{historyText ++ "\n\n---\n\n**Turn Context (split turn):**\n\n" ++ prefixText, combineUsage(historyUsage, prefixUsage)}}

def historySummary(~D: Data, ~T: Data, ~C: Data, summarizer: Summarizer(D, T), messages: List<&2, Msg(D, T, C)>, model: Ai.Model<Ai.JsonValue>, reserveTokens: F64, signal: Maybe<&2, A.AbortSignal<Unit>>, customInstructions: Maybe<&2, String>, previousSummary: Maybe<&2, String>, retry: Maybe<&2, Retry.RetryPolicy>, callbacks: Maybe<&2, Retry.RetryCallbacks()>) -> IO(Result<&2, &2, String, Maybe<&2, Summary>>):
  match messages:
    case Nil{}: IO.pure(Result<&2, &2, String, Maybe<&2, Summary>>, Done{None{}})
    case _:
      do IO<Result<&2, &2, String, Maybe<&2, Summary>>>:
        result : Result<&2, &2, String, Summary> <- generateSummaryWithUsage(~D, ~T, ~C, summarizer, messages, model, reserveTokens, signal, customInstructions, previousSummary, retry, callbacks)
        return Result.map(&2, &2, String, Summary, Maybe<&2, Summary>, summary => Some{summary}, result)

def summaryFor(~D: Data, ~T: Data, ~C: Data, +summarizer: Summarizer(D, T), +messagesToSummarize: List<&2, Msg(D, T, C)>, turnPrefixMessages: List<&2, Msg(D, T, C)>, isSplitTurn: Bool, +model: Ai.Model<Ai.JsonValue>, +reserveTokens: F64, +signal: Maybe<&2, A.AbortSignal<Unit>>, +customInstructions: Maybe<&2, String>, +previousSummary: Maybe<&2, String>, +retry: Maybe<&2, Retry.RetryPolicy>, +callbacks: Maybe<&2, Retry.RetryCallbacks()>) -> IO(Result<&2, &2, String, Summary>):
  match turnPrefixMessages isSplitTurn:
    case prefix <> rest True{}:
      do IO<Result<&2, &2, String, Summary>>:
        history : Result<&2, &2, String, Maybe<&2, Summary>> <- historySummary(~D, ~T, ~C, summarizer, messagesToSummarize, model, reserveTokens, signal, customInstructions, previousSummary, retry, callbacks)
        prefixSummary : Result<&2, &2, String, Summary> <- generateTurnPrefixSummary(~D, ~T, ~C, summarizer, prefix <> rest, model, reserveTokens, signal, retry, callbacks)
        return combinedSummary(history, previousSummary, prefixSummary)
    case _ _: generateSummaryWithUsage(~D, ~T, ~C, summarizer, messagesToSummarize, model, reserveTokens, signal, customInstructions, previousSummary, retry, callbacks)

def resultOf(summary: Result<&2, &2, String, Summary>, firstKeptEntryId: String, tokensBefore: F64, lists: Utils.FileLists) -> Result<&2, &2, String, CompactionResult>:
  match summary lists:
    case Fail{message} _: Fail{message}
    case Done{Summary{text, usage}} Utils.FileLists{+readFiles, +modifiedFiles}: Done{CompactionResult{text ++ Utils.formatFileOperations(readFiles, modifiedFiles), firstKeptEntryId, tokensBefore, None{}, Some{usage}, Some{CompactionDetails{readFiles, modifiedFiles}}}}

# upstream compact: summarize the history (and a split turn's prefix), then
# append the file lists. Errors are returned, not thrown.
def compact(~D: Data, ~T: Data, ~C: Data, summarizer: Summarizer(D, T), preparation: CompactionPreparation<D, T, C>, model: Ai.Model<Ai.JsonValue>, customInstructions: Maybe<&2, String>, signal: Maybe<&2, A.AbortSignal<Unit>>, retry: Maybe<&2, Retry.RetryPolicy>, callbacks: Maybe<&2, Retry.RetryCallbacks()>) -> IO(Result<&2, &2, String, CompactionResult>):
  match preparation:
    case CompactionPreparation{firstKeptEntryId, messagesToSummarize, turnPrefixMessages, isSplitTurn, tokensBefore, previousSummary, fileOps, settings}:
      do IO<Result<&2, &2, String, CompactionResult>>:
        summary : Result<&2, &2, String, Summary> <- summaryFor(~D, ~T, ~C, summarizer, messagesToSummarize, turnPrefixMessages, isSplitTurn, model, reserveTokensOf(settings), signal, customInstructions, previousSummary, retry, callbacks)
        return resultOf(summary, firstKeptEntryId, tokensBefore, Utils.computeFileLists(fileOps))

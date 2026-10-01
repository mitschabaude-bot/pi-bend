import Base
import ../../src/core/extensions/types.bend as Ext
import ../../src/core/extensions/context.bend as Ctx
import ../../src/core/extensions/loader.bend as Loader
import ../../src/core/compaction/compaction.bend as Compaction
import ../../src/core/compaction/utils.bend as CompactionUtils
import ../../src/core/messages.bend as Messages
import ../../src/core/model-runtime.bend as Models
import ../../src/core/provider-composer.bend as Composer
import ../../src/core/tools/index.bend as Tools
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/uuid.bend as Uuid
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/number-string.bend as NumberString
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/text.bend as Text

# pi v0.87.1 examples/extensions/custom-compaction.ts: replace the default
# compaction with a full summary of the entire context (messagesToSummarize
# and turnPrefixMessages), made by a different model (Gemini Flash) through
# ctx.modelRegistry.complete, which resolves the request's auth.

def Outcome() -> Data: Result<&2, &2, String, Maybe<&2, Ext.SessionBeforeCompactResult>>

def skipped() -> IO(Outcome()): IO.pure(Outcome(), Done{None{}})

# Number.prototype.toLocaleString (en-US) of a token count.
def fixed(value: F64) -> String: Maybe.default(&2, String, NumberString.formatFixed(value, 0n), "")

def consed(char: Char, rest: String) -> String: SCon{char, rest}

# `count` is the number of digits from this one to the end; a separator
# precedes each later digit that starts a group of three.
def grouped(digits: String, +count: Nat) -> String:
  match digits:
    case SNil{}: ""
    case SCon{char, rest}:
      +tail = consed(char, grouped(rest, count - 1n))
      Bool.pick(String, Nat.is_eq(Nat.mod(count, 3n), 0n), "," ++ tail, tail)

def groupedDigits(+digits: String) -> String:
  match digits:
    case SCon{first, rest}: SCon{first, grouped(rest, String.length(digits) - 1n)}
    case SNil{}: ""

def localeCount(value: F64) -> String: groupedDigits(fixed(value))

def previousContext(summary: Maybe<&2, String>) -> String:
  match summary:
    case None{}: ""
    case Some{text}: "\n\nPrevious session summary for context:\n" ++ text

def summaryPrompt(+previous: String, +conversation: String) -> String:
  "You are a conversation summarizer. Create a comprehensive summary of this conversation that captures:" ++ previous ++ "\n\n1. The main goals and objectives discussed\n2. Key decisions made and their rationale\n3. Important code changes, file modifications, or technical details\n4. Current state of any ongoing work\n5. Any blockers, issues, or open questions\n6. Next steps that were planned or suggested\n\nBe thorough but concise. The summary will replace the ENTIRE conversation history, so include all information needed to continue the work effectively.\n\nFormat the summary as structured markdown with clear sections.\n\n<conversation>\n" ++ conversation ++ "\n</conversation>"

def textBlocks(content: List<&2, Ai.AssistantContent<V.Value>>) -> List<&2, String>:
  match content:
    case Nil{}: Nil{}
    case Ai.AssistantText{Ai.TextContent{text, _}} <> rest: text <> textBlocks(rest)
    case _ <> rest: textBlocks(rest)

def summaryOf(response: Ai.AssistantMessage<V.Value, V.Value>) -> String:
  String.join(textBlocks(Ai.assistantContent(V.Value, V.Value, response)), "\n")

def usageOf(response: Ai.AssistantMessage<V.Value, V.Value>) -> Ai.Usage:
  match response:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, usage, _, _, _, _, _, _}: usage

def emptySummary(+ctx: Ctx.ExtensionContext, signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  do IO<Outcome()>:
    aborted : Bool <- Abort.aborted(Unit, signal)
    Bool.pick(Unit -> IO(Unit), aborted, _ => IO.pure(Unit, Unit{}), _ => Ctx.notify(ctx, "Compaction summary was empty, using default compaction", Ctx.WarningNotice{}))(Unit{})
    skipped()

# Return compaction content; the session manager adds id and parentId. The
# preparation's firstKeptEntryId keeps the recent messages.
def summarized(+ctx: Ctx.ExtensionContext, signal: Abort.AbortSignal<Unit>, +firstKeptEntryId: String, +tokensBefore: F64, +response: Ai.AssistantMessage<V.Value, V.Value>) -> IO(Outcome()):
  +summary = summaryOf(response)
  Bool.pick(Unit -> IO(Outcome()), String.is_empty(Text.trim(summary)),
    _ => emptySummary(ctx, signal),
    _ => IO.pure(Outcome(), Done{Some{Ext.SessionBeforeCompactResult{None{}, Some{Compaction.CompactionResult{summary, firstKeptEntryId, tokensBefore, None{}, Some{usageOf(response)}, None{}}}}}}))(Unit{})

def requestId(generated: Result<&2, &2, Uuid.Error, String>) -> Maybe<&2, String>:
  match generated:
    case Done{id}: Some{id}
    case Fail{_}: None{}

# The request honors the compaction's abort signal, without cache writes, on
# a fresh routing id.
def requestOptions(signal: Abort.AbortSignal<Unit>, sessionId: Maybe<&2, String>) -> Composer.ApiStreamOptions:
  Composer.CommonOptions{Ai.StreamOptions{Some{signal}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{F.fromU32(8192)}, None{}, Some{Ai.CacheNone{}}, sessionId, None{}, None{}}}

def summarize(+ctx: Ctx.ExtensionContext, +model: Ai.Model<Ai.JsonValue>, preparation: Compaction.CompactionPreparation<V.Value, Tools.ToolDetails, V.Value>, +signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  match preparation:
    case Compaction.CompactionPreparation{+firstKeptEntryId, messagesToSummarize, turnPrefixMessages, _, +tokensBefore, previousSummary, _, _}:
      +allMessages = List.append(&2, Ext.AgentMessage(), messagesToSummarize, turnPrefixMessages)
      +conversation = CompactionUtils.serializeConversation(V.Value, Tools.ToolDetails, Messages.convertToLlm(V.Value, Tools.ToolDetails, V.Value, allMessages))
      do IO<Outcome()>:
        Ctx.notify(ctx, "Custom compaction: summarizing " ++ Nat.show(List.length(&2, Ext.AgentMessage(), allMessages)) ++ " messages (" ++ localeCount(tokensBefore) ++ " tokens) with " ++ Ai.modelId(model) ++ "...", Ctx.InfoNotice{})
        now : F64 <- Date.now()
        ids : Uuid.Generator <- Uuid.generator()
        generated : Result<&2, &2, Uuid.Error, String> <- Uuid.uuidv7(ids, None{})
        +messages : List<&2, Ai.Message<V.Value, V.Value, V.Value, Tools.ToolDetails>> = [Ai.User{Ai.UserMessage{Ai.UserBlocks{[Ai.TextImageText{Ai.TextContent{summaryPrompt(previousContext(previousSummary), conversation), None{}}}]}, now}}]
        response : Ai.AssistantMessage<V.Value, V.Value> <- Models.complete(Ctx.modelRegistry(ctx), model, Ai.Context{None{}, messages, None{}}, Some{requestOptions(signal, requestId(generated))})
        summarized(ctx, signal, firstKeptEntryId, tokensBefore, response)

def withModel(+ctx: Ctx.ExtensionContext, found: Maybe<&2, Ai.Model<Ai.JsonValue>>, preparation: Compaction.CompactionPreparation<V.Value, Tools.ToolDetails, V.Value>, signal: Abort.AbortSignal<Unit>) -> IO(Outcome()):
  match found:
    case None{}:
      do IO<Outcome()>:
        Ctx.notify(ctx, "Could not find Gemini Flash model, using default compaction", Ctx.WarningNotice{})
        skipped()
    case Some{model}: summarize(ctx, model, preparation, signal)

def compacting(+ctx: Ctx.ExtensionContext, event: Ext.SessionBeforeCompactEvent) -> IO(Outcome()):
  match event:
    case Ext.SessionBeforeCompactEvent{preparation, _, _, _, _, signal}:
      do IO<Outcome()>:
        Ctx.notify(ctx, "Custom compaction extension triggered", Ctx.InfoNotice{})
        # Gemini Flash summarizes (cheaper and faster than most conversation models).
        found : Maybe<&2, Ai.Model<Ai.JsonValue>> <- Models.getModel(Ctx.modelRegistry(ctx), "google", "gemini-2.5-flash")
        withModel(ctx, found, preparation, signal)

def onBeforeCompact(unit: Unit, call: Ext.HandlerCall<Ext.SessionBeforeCompactEvent>) -> IO(Outcome()):
  match call:
    case Ext.HandlerCall{event, ctx}: compacting(ctx, event)

def subscribed(result: Result<&2, &2, String, Loader.Unsubscribe>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{error}: Fail{error}
    case Done{_}: Done{Unit{}}

def customCompaction(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.SessionBeforeCompactEvent, Ext.SessionBeforeCompactResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.SessionBeforeCompactEvent>, ~Outcome(), ~onBeforeCompact, Unit{})
    result : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnSessionBeforeCompact{handler})
    return subscribed(result)

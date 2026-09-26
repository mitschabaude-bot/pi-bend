import Base
import ../packages/agent/src/agent.bend as Agent
import ../packages/agent/src/agent-loop.bend as Loop
import ../packages/agent/src/stream-fn.bend as StreamFn
import ../packages/agent/src/types.bend as T
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/event-stream.bend as Stream
import ../packages/ai/src/utils/message-json.bend as Json
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/record.bend as Rec
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/f64.bend as F
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/system-prompt.bend as Prompt
import ../packages/coding-agent/src/core/compaction/compaction.bend as Compaction
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/modes/json-event.bend as JsonEvent
import ./model-runtime-fixture.bend as ModelFixture
import ./agent-session.bend as H
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/ai/src/utils/uuid.bend as Uuid
import ../packages/ai/src/utils/text.bend as AiText

# Scenarios for upstream's suite/regressions tests that need AgentSession
# behavior beyond tests/agent-session.bend. The provider streams like
# upstream's registerFauxProvider: a start event, then each content block's
# start/delta/end events with the text (or the tool call's JSON arguments)
# split into chunks, then done. Adaptations: chunks are a fixed four tokens
# (16 characters) instead of a random 3-5 tokens. Usage follows upstream's
# withUsageEstimate (prompt and output estimates, with the prompt cache).
# tests/regressions_check.py reads the printed JSON lines.

def EventStream() -> Data: Stream.AssistantMessageEventStream(V.Value, Unit)

type Reply is Data:
  Text{text: String}
  Plain{text: String}
  Costed{text: String}
  Call{id: String, name: String, arguments: V.Value, json: String}
  Calls{calls: List<&2, Ai.ToolCall<V.Value>>}
  Interrupted{text: String, started: Chan(Unit)}
  Failed{errorMessage: String}
  FailedText{text: String, errorMessage: String}
  Stopped{reply: Reply}

# Each request takes the next hold: Pass runs at once, Hold waits at a gate
# (tests/agent-session.bend's Gate); requests after the listed holds pass.
# The last request's abort signal is kept, and a request whose signal is
# aborted when it proceeds ends as aborted, as upstream's faux stream does.
type Hold is Data:
  Pass{}
  Held{gate: H.Gate}

def Signal() -> Data: Abort.AbortSignal<Unit>

type Faux is Data:
  Faux{replies: R.Ref<List<&2, Reply>>, streams: R.Ref<List<&2, EventStream()>>, gates: R.Ref<List<&2, Hold>>, model: String, signal: R.Ref<Maybe<&2, Signal()>>, prompts: R.Ref<Rec.Record<String>>}

def popHold(holds: List<&2, Hold>) -> List<&2, Hold> & Maybe<&2, H.Gate>:
  match holds:
    case Nil{}: (Nil{}, None{})
    case Pass{} <> rest: (rest, None{})
    case Held{gate} <> rest: (rest, Some{gate})

def signalOf(input: H.Input()) -> Maybe<&2, Signal()>:
  match input:
    case T.StreamInput{_, _, Some{T.AgentLoopConfig{Ai.SimpleStreamOptions{signal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _, _}}}: signal
    case _: None{}

def blockTexts(blocks: List<&2, Ai.TextImageContent>) -> String:
  match blocks:
    case Nil{}: ""
    case Ai.TextImageText{Ai.TextContent{text, _}} <> rest: text ++ blockTexts(rest)
    case _ <> rest: blockTexts(rest)

def lastUserIn(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, Tools.ToolDetails>>, found: Maybe<&2, String>) -> Maybe<&2, String>:
  match messages:
    case Nil{}: found
    case Ai.User{Ai.UserMessage{Ai.UserText{text}, _}} <> rest: lastUserIn(rest, Some{text})
    case Ai.User{Ai.UserMessage{Ai.UserBlocks{blocks}, _}} <> rest: lastUserIn(rest, Some{blockTexts(blocks)})
    case _ <> rest: lastUserIn(rest, found)

# The text of the request's last user message.
def lastUserOf(input: H.Input()) -> Maybe<&2, String>:
  match input:
    case T.StreamInput{_, Ai.TranscriptContext{messages}, _}: lastUserIn(messages, None{})

def apiKeyOf(input: H.Input()) -> Maybe<&2, String>:
  match input:
    case T.StreamInput{_, _, Some{T.AgentLoopConfig{Ai.SimpleStreamOptions{_, _, apiKey, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _, _}}}: apiKey
    case _: None{}

def isAborted(signal: Maybe<&2, Signal()>) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool, False{})
    case Some{value}: Abort.aborted(Unit, value)

def zero() -> F64: U32.to_f64(0)

def estimate(text: String) -> F64: U32.to_f64(U32.from_nat((String.length(text) + 3n) / 4n))

def usageOf(+output: F64) -> Ai.Usage:
  Ai.Usage{zero(), output, zero(), zero(), None{}, None{}, output, Ai.UsageCost{zero(), zero(), zero(), zero(), zero()}}

# upstream faux withUsageEstimate's prompt side: the serialized request
# context in tokens (ceil(characters / 4)), split into input, cache read and
# cache write against the previous prompt of the same session.
type PromptUsage is Data:
  PromptUsage{input: F64, cacheRead: F64, cacheWrite: F64}

# The model a reply comes from, its time and the request's prompt usage.
type Stamp is Data:
  Stamp{model: String, time: F64, prompt: PromptUsage}

def noPrompt() -> PromptUsage: PromptUsage{zero(), zero(), zero()}

def usageAt(now: Stamp, +output: F64) -> Ai.Usage:
  match now:
    case Stamp{_, _, PromptUsage{+input, +cacheRead, +cacheWrite}}: Ai.Usage{input, output, cacheRead, cacheWrite, None{}, None{}, F64.add(F64.add(input, output), F64.add(cacheRead, cacheWrite)), Ai.UsageCost{zero(), zero(), zero(), zero(), zero()}}

# upstream faux serializeContext: each message as `role:text`, joined by
# blank lines; images as `[image:mime:length]`, tool calls as `name:args`,
# system messages with their rendered prompt and declared tool changes.
def jsonText(value: V.Value) -> String: H.line(value)

def imageText(image: Ai.ImageContent) -> String:
  match image:
    case Ai.ImageContent{data, mime}: "[image:" ++ mime ++ ":" ++ Nat.show(String.length(data)) ++ "]"

def blockText(block: Ai.TextImageContent) -> String:
  match block:
    case Ai.TextImageText{Ai.TextContent{text, _}}: text
    case Ai.TextImageImage{image}: imageText(image)

def blocksTexts(blocks: List<&2, Ai.TextImageContent>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case block <> rest: blockText(block) <> blocksTexts(rest)

def userContentText(content: Ai.UserContent) -> String:
  match content:
    case Ai.UserText{text}: text
    case Ai.UserBlocks{blocks}: String.join(blocksTexts(blocks), "\n")

def callText(call: Ai.ToolCall<V.Value>) -> String:
  match call:
    case Ai.ToolCall{_, name, arguments, _, _}: name ++ ":" ++ jsonText(arguments)

def callsTexts(calls: List<&2, Ai.ToolCall<V.Value>>) -> List<&2, String>:
  match calls:
    case Nil{}: Nil{}
    case call <> rest: callText(call) <> callsTexts(rest)

def callsText(calls: List<&2, Ai.ToolCall<V.Value>>) -> String: String.join(callsTexts(calls), "\n")

def assistantTexts(content: List<&2, Ai.AssistantContent<V.Value>>) -> List<&2, String>:
  match content:
    case Nil{}: Nil{}
    case Ai.AssistantText{Ai.TextContent{text, _}} <> rest: text <> assistantTexts(rest)
    case Ai.AssistantThinking{Ai.ThinkingContent{thinking, _, _}} <> rest: thinking <> assistantTexts(rest)
    case Ai.AssistantToolCall{call} <> rest: callText(call) <> assistantTexts(rest)

def toolResultText(message: Ai.ToolResultMessage<Tools.ToolDetails>) -> String:
  match message:
    case Ai.ToolResultMessage{_, name, content, _, _, _, _}: String.join(name <> blocksTexts(content), "\n")

def removedTools(tools: Maybe<&2, List<&2, Ai.ToolReference>>) -> List<&2, String>:
  match tools:
    case Some{Ai.ToolReference{name} <> rest}: ("tool-:" ++ jsonText(Json.object(Json.field("name", Json.text(name), Nil{})))) <> removedTools(Some{rest})
    case _: Nil{}

def addedTools(tools: Maybe<&2, List<&2, Ai.Tool<V.Value>>>) -> List<&2, String>:
  match tools:
    case Some{tool <> rest}: ("tool+:" ++ jsonText(Json.tool(tool))) <> addedTools(Some{rest})
    case _: Nil{}

def nonEmptyParts(parts: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case +part <> rest:
      +tail = nonEmptyParts(rest)
      Bool.pick(List<&2, String>, String.is_empty(part), tail, part <> tail)

def systemText(+message: Ai.SystemMessage<V.Value>) -> String:
  match message:
    case Ai.SystemMessage{_, _, added, removed, _}: String.join(nonEmptyParts(AiText.renderComplete(V.Value, message) <> List.append(&2, String, removedTools(removed), addedTools(added))), "\n")

def messageText(message: Ai.Message<V.Value, V.Value, Unit, Tools.ToolDetails>) -> String:
  match message:
    case Ai.System{system}: "system:" ++ systemText(system)
    case Ai.User{Ai.UserMessage{content, _}}: "user:" ++ userContentText(content)
    case Ai.Assistant{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: "assistant:" ++ String.join(assistantTexts(content), "\n")
    case Ai.ToolResult{result}: "toolResult:" ++ toolResultText(result)

def messageTexts(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, Tools.ToolDetails>>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: messageText(message) <> messageTexts(rest)

def roleName(message: Ai.Message<V.Value, V.Value, Unit, Tools.ToolDetails>) -> String:
  match message:
    case Ai.System{_}: "\"system\""
    case Ai.User{_}: "\"user\""
    case Ai.Assistant{_}: "\"assistant\""
    case Ai.ToolResult{_}: "\"toolResult\""

def rolesOf(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, Tools.ToolDetails>>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: roleName(message) <> rolesOf(rest)

def requestRoles(input: H.Input()) -> List<&2, String>:
  match input:
    case T.StreamInput{_, Ai.TranscriptContext{messages}, _}: rolesOf(messages)

def serializeContext(input: H.Input()) -> String:
  match input:
    case T.StreamInput{_, Ai.TranscriptContext{messages}, _}: String.join(messageTexts(messages), "\n\n")

def cacheKey(input: H.Input()) -> Maybe<&2, String>:
  match input:
    case T.StreamInput{_, _, Some{T.AgentLoopConfig{Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, Some{Ai.CacheNone{}}, _, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _, _}}}: None{}
    case T.StreamInput{_, _, Some{T.AgentLoopConfig{Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, sessionId, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _, _}}}: sessionId
    case _: None{}

def commonPrefix(left: String, right: String, +count: Nat) -> Nat:
  match left right:
    case SCon{a, restLeft} SCon{b, restRight}: Bool.pick(Nat, Char.is_eq(a, b), commonPrefix(restLeft, restRight, count + 1n), count)
    case _ _: count

def cached(+prompt: String, +previous: String) -> PromptUsage:
  +shared = commonPrefix(previous, prompt, 0n)
  +read = estimate(String.take(previous, shared))
  PromptUsage{F64.max(zero(), F64.sub(estimate(prompt), read)), read, estimate(String.drop(prompt, shared))}

def usageFor(+prompt: String, key: Maybe<&2, String>, previous: Maybe<&2, String>) -> PromptUsage:
  match key previous:
    case None{} _: PromptUsage{estimate(prompt), zero(), zero()}
    case Some{_} None{}: PromptUsage{zero(), zero(), estimate(prompt)}
    case Some{_} Some{earlier}: cached(prompt, earlier)

def remembered(+record: Rec.Record<String>, key: Maybe<&2, String>, +prompt: String) -> Rec.Record<String>:
  match key:
    case None{}: record
    case Some{id}: Rec.set(String, record, id, prompt)

# withUsageEstimate's prompt tokens, with the session's prompt cache.
def promptUsage(+previous: Rec.Record<String>, +input: H.Input()) -> Rec.Record<String> & PromptUsage:
  +prompt = serializeContext(input)
  +key = cacheKey(input)
  (remembered(previous, key, prompt), usageFor(prompt, key, Maybe.bind(&2, String, String, key, id => Rec.get(String, previous, id))))

# 6324's reply: input 1, output 1, total cost 0.25.
def costedUsage() -> Ai.Usage:
  Ai.Usage{U32.to_f64(1), U32.to_f64(1), zero(), zero(), None{}, None{}, U32.to_f64(2), Ai.UsageCost{zero(), zero(), zero(), zero(), F64.div(U32.to_f64(1), U32.to_f64(4))}}

def replyMessage(content: List<&2, Ai.AssistantContent<V.Value>>, stop: Ai.StopReason, usage: Ai.Usage, now: Stamp) -> Ai.AssistantMessage<V.Value, Unit>:
  match now:
    case Stamp{model, time, _}: Ai.AssistantMessage{content, "openai-responses", "faux", model, None{}, None{}, None{}, None{}, usage, stop, None{}, None{}, None{}, None{}, time}

def textBlock(text: String) -> List<&2, Ai.AssistantContent<V.Value>>: Ai.AssistantText{Ai.TextContent{text, None{}}} <> Nil{}

def callBlock(+id: String, +name: String, arguments: V.Value) -> List<&2, Ai.AssistantContent<V.Value>>:
  Ai.AssistantToolCall{Ai.ToolCall{id, name, arguments, None{}, None{}}} <> Nil{}

# Chunks of 16 characters, collected reversed; empty text is one empty chunk.
def gather(text: String, +reversed: String, +count: Nat) -> List<&2, String>:
  match text:
    case SNil{}: Bool.pick(List<&2, String>, Nat.is_eq(count, 0n), Nil{}, String.reverse(reversed) <> Nil{})
    case SCon{+c, +rest}: Bool.pick(Unit -> List<&2, String>, Nat.is_eq(count, 15n), _ => String.reverse(SCon{c, reversed}) <> gather(rest, "", 0n), _ => gather(rest, SCon{c, reversed}, count + 1n))(Unit{})

def chunks(text: String) -> List<&2, String>:
  match text:
    case SNil{}: "" <> Nil{}
    case SCon{c, rest}: gather(SCon{c, rest}, "", 0n)

def push(stream: EventStream(), event: Ai.AssistantMessageEvent<V.Value, Unit>) -> IO(Unit):
  Stream.push(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, stream, event)

def textDeltas(+stream: EventStream(), parts: List<&2, String>, +sofar: String, +usage: Ai.Usage, +now: Stamp) -> IO(Unit):
  match parts:
    case Nil{}: IO.pure(Unit, Unit{})
    case +part <> rest:
      +next = sofar ++ part
      do IO<Unit>:
        push(stream, Ai.TextDelta{zero(), part, replyMessage(textBlock(next), Ai.Pending{}, usage, now)})
        textDeltas(stream, rest, next, usage, now)

def callDeltas(+stream: EventStream(), parts: List<&2, String>, +partial: Ai.AssistantMessage<V.Value, Unit>) -> IO(Unit):
  match parts:
    case Nil{}: IO.pure(Unit, Unit{})
    case +part <> rest:
      do IO<Unit>:
        push(stream, Ai.ToolcallDelta{zero(), part, partial})
        callDeltas(stream, rest, partial)

def callsBlock(calls: List<&2, Ai.ToolCall<V.Value>>) -> List<&2, Ai.AssistantContent<V.Value>>:
  match calls:
    case Nil{}: Nil{}
    case call <> rest: Ai.AssistantToolCall{call} <> callsBlock(rest)

# Several tool calls in one reply, each announced by its start and end.
def callEvents(+stream: EventStream(), calls: List<&2, Ai.ToolCall<V.Value>>, +index: U32, +partial: Ai.AssistantMessage<V.Value, Unit>) -> IO(Unit):
  match calls:
    case Nil{}: IO.pure(Unit, Unit{})
    case call <> rest:
      do IO<Unit>:
        push(stream, Ai.ToolcallStart{U32.to_f64(index), partial})
        push(stream, Ai.ToolcallEnd{U32.to_f64(index), call, partial})
        callEvents(stream, rest, U32.add(index, 1), partial)

def waitAborted(fuel: Nat, +signal: Maybe<&2, Signal()>) -> IO(Bool):
  match fuel:
    case 0n: IO.pure(Bool, False{})
    case 1n+rest:
      do IO<Bool>:
        aborted : Bool <- isAborted(signal)
        Bool.pick(Unit -> IO(Bool), aborted, _ => IO.pure(Bool, True{}), _ => IO.bind(Unit, Bool, IO.sleep(1), _ => waitAborted(rest, signal)))(Unit{})

def interruptedRest(+stream: EventStream(), parts: List<&2, String>, +first: String, +text: String, +now: Stamp, aborted: Bool) -> IO(Unit):
  match aborted:
    case True{}: push(stream, Ai.StreamError{Ai.ErrorAborted{}, replyMessage(textBlock(first), Ai.Aborted{}, usageAt(now, estimate(text)), now)})
    case False{}:
      +usage = usageAt(now, estimate(text))
      do IO<Unit>:
        textDeltas(stream, parts, first, usage, now)
        push(stream, Ai.TextEnd{zero(), text, replyMessage(textBlock(text), Ai.Pending{}, usage, now)})
        push(stream, Ai.StreamDone{Ai.DoneStop{}, replyMessage(textBlock(text), Ai.Stop{}, usage, now)})

# A long reply whose stream, after its first chunk, waits (up to five
# seconds) for the request to be aborted and then ends as aborted, as
# upstream's faux stream checks its signal between chunks.
def interruptedChunks(+stream: EventStream(), parts: List<&2, String>, +text: String, started: Chan(Unit), signal: Maybe<&2, Signal()>, +now: Stamp) -> IO(Unit):
  match parts:
    case Nil{}: IO.pure(Unit, Unit{})
    case +first <> rest:
      +usage = usageAt(now, estimate(text))
      do IO<Unit>:
        push(stream, Ai.Start{replyMessage(Nil{}, Ai.Pending{}, usage, now)})
        push(stream, Ai.TextStart{zero(), replyMessage(textBlock(""), Ai.Pending{}, usage, now)})
        push(stream, Ai.TextDelta{zero(), first, replyMessage(textBlock(first), Ai.Pending{}, usage, now)})
        sent : Bool <- Chan.send(Unit, started, Unit{})
        aborted : Bool <- waitAborted(5000n, signal)
        interruptedRest(stream, rest, first, text, now, aborted)

def interruptedReply(+stream: EventStream(), +text: String, started: Chan(Unit), signal: Maybe<&2, Signal()>, +now: Stamp) -> IO(Unit):
  interruptedChunks(stream, chunks(text), text, started, signal, now)

# An error reply: no content, stop reason error, the error message.
def failedWith(errorMessage: String, usage: Ai.Usage, content: List<&2, Ai.AssistantContent<V.Value>>, now: Stamp) -> Ai.AssistantMessage<V.Value, Unit>:
  match now:
    case Stamp{model, time, _}: Ai.AssistantMessage{content, "openai-responses", "faux", model, None{}, None{}, None{}, None{}, usage, Ai.Error{}, None{}, Some{errorMessage}, None{}, None{}, time}

def failedMessage(errorMessage: String, +now: Stamp) -> Ai.AssistantMessage<V.Value, Unit>:
  +usage = usageAt(now, zero())
  failedWith(errorMessage, usage, Nil{}, now)

# `length` ends the reply at the length limit (upstream
# fauxAssistantMessage(..., { stopReason: "length" })).
def doneReason(length: Bool, reason: Ai.DoneReason) -> Ai.DoneReason: Bool.pick(Ai.DoneReason, length, Ai.DoneLength{}, reason)
def stopReasonFor(length: Bool, stop: Ai.StopReason) -> Ai.StopReason: Bool.pick(Ai.StopReason, length, Ai.Length{}, stop)

def answerStop(+stream: EventStream(), reply: Reply, +now: Stamp, +length: Bool) -> IO(Unit):
  match reply:
    case Text{+text}:
      +usage = usageAt(now, estimate(text))
      do IO<Unit>:
        push(stream, Ai.Start{replyMessage(Nil{}, Ai.Pending{}, usage, now)})
        push(stream, Ai.TextStart{zero(), replyMessage(textBlock(""), Ai.Pending{}, usage, now)})
        textDeltas(stream, chunks(text), "", usage, now)
        push(stream, Ai.TextEnd{zero(), text, replyMessage(textBlock(text), Ai.Pending{}, usage, now)})
        push(stream, Ai.StreamDone{doneReason(length, Ai.DoneStop{}), replyMessage(textBlock(text), stopReasonFor(length, Ai.Stop{}), usage, now)})
    case Costed{+text}:
      +usage = costedUsage()
      do IO<Unit>:
        push(stream, Ai.Start{replyMessage(Nil{}, Ai.Pending{}, usage, now)})
        push(stream, Ai.StreamDone{Ai.DoneStop{}, replyMessage(textBlock(text), Ai.Stop{}, usage, now)})
    case Plain{+text}:
      +usage = usageOf(zero())
      do IO<Unit>:
        push(stream, Ai.Start{replyMessage(Nil{}, Ai.Pending{}, usage, now)})
        push(stream, Ai.TextStart{zero(), replyMessage(textBlock(""), Ai.Pending{}, usage, now)})
        textDeltas(stream, chunks(text), "", usage, now)
        push(stream, Ai.TextEnd{zero(), text, replyMessage(textBlock(text), Ai.Pending{}, usage, now)})
        push(stream, Ai.StreamDone{Ai.DoneStop{}, replyMessage(textBlock(text), Ai.Stop{}, usage, now)})
    case Call{+id, +name, +arguments, +json}:
      +usage = usageAt(now, estimate(json))
      +started = replyMessage(callBlock(id, name, V.ObjectValue{Rec.new(V.Value)}), Ai.Pending{}, usage, now)
      do IO<Unit>:
        push(stream, Ai.Start{replyMessage(Nil{}, Ai.Pending{}, usage, now)})
        push(stream, Ai.ToolcallStart{zero(), started})
        callDeltas(stream, chunks(json), started)
        push(stream, Ai.ToolcallEnd{zero(), Ai.ToolCall{id, name, arguments, None{}, None{}}, replyMessage(callBlock(id, name, arguments), Ai.Pending{}, usage, now)})
        push(stream, Ai.StreamDone{doneReason(length, Ai.DoneToolUse{}), replyMessage(callBlock(id, name, arguments), stopReasonFor(length, Ai.ToolUse{}), usage, now)})
    case Calls{+calls}:
      +usage = usageAt(now, estimate(callsText(calls)))
      +partial = replyMessage(callsBlock(calls), Ai.Pending{}, usage, now)
      do IO<Unit>:
        push(stream, Ai.Start{replyMessage(Nil{}, Ai.Pending{}, usage, now)})
        callEvents(stream, calls, 0, partial)
        push(stream, Ai.StreamDone{Ai.DoneToolUse{}, replyMessage(callsBlock(calls), Ai.ToolUse{}, usage, now)})
    case Interrupted{_, _}: IO.pure(Unit, Unit{})
    case Failed{+errorMessage}:
      do IO<Unit>:
        push(stream, Ai.Start{replyMessage(Nil{}, Ai.Pending{}, usageOf(zero()), now)})
        push(stream, Ai.StreamError{Ai.ErrorError{}, failedMessage(errorMessage, now)})
    case FailedText{+text, errorMessage}:
      +usage = usageAt(now, estimate(text))
      do IO<Unit>:
        push(stream, Ai.Start{replyMessage(Nil{}, Ai.Pending{}, usage, now)})
        push(stream, Ai.StreamError{Ai.ErrorError{}, failedWith(errorMessage, usage, textBlock(text), now)})
    case Stopped{inner}: answerStop(stream, inner, now, True{})

def answer(+stream: EventStream(), reply: Reply, +now: Stamp) -> IO(Unit): answerStop(stream, reply, now, False{})

def abortedReply(+stream: EventStream(), +now: Stamp) -> IO(Unit):
  do IO<Unit>:
    push(stream, Ai.Start{replyMessage(Nil{}, Ai.Pending{}, usageOf(zero()), now)})
    push(stream, Ai.StreamError{Ai.ErrorAborted{}, replyMessage(Nil{}, Ai.Aborted{}, usageOf(zero()), now)})

# An interrupted reply streams from its own task, so the loop reads it while
# it waits for the abort.
def answerAsync(+stream: EventStream(), reply: Reply, +now: Stamp, signal: Maybe<&2, Signal()>) -> IO(Unit):
  match reply:
    case Interrupted{text, started}: IO.spawn(Unit, interruptedReply(stream, text, started, signal, now))
    case other: answer(stream, other, now)

def popReply(replies: List<&2, Reply>) -> List<&2, Reply> & Reply:
  match replies:
    case Nil{}: (Nil{}, Text{"(no scripted response)"})
    case reply <> rest: (rest, reply)

def maxTokensOf(input: H.Input()) -> String:
  match input:
    case T.StreamInput{_, _, Some{T.AgentLoopConfig{Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, Some{cap}, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _, _}}}: Nat.show(Result.default(&2, &2, F.Error, Nat, F.convert(cap), 0n))
    case _: "null"

def requestModel(input: H.Input()) -> String:
  match input:
    case T.StreamInput{model, _, _}: Ai.modelId(model)

# Replies carry the request's model (upstream's faux clones each reply with
# the requested model).
def providing(faux: Faux, +input: H.Input()) -> IO(H.Output()):
  match faux:
    case Faux{replies, streams, gates, _, signals, prompts}:
      +model = requestModel(input)
      +signal = signalOf(input)
      do IO<H.Output()>:
        R.write(Maybe<&2, Signal()>, signals, signal)
        IO.print("{\"type\":\"request\",\"model\":" ++ Decode.quote(model) ++ ",\"apiKey\":" ++ H.maybeQuoted(apiKeyOf(input)) ++ ",\"lastUser\":" ++ H.maybeQuoted(lastUserOf(input)) ++ ",\"maxTokens\":" ++ maxTokensOf(input) ++ ",\"roles\":[" ++ String.join(requestRoles(input), ",") ++ "],\"context\":" ++ Decode.quote(serializeContext(input)) ++ "}")
        gate : Maybe<&2, H.Gate> <- R.modify(List<&2, Hold>, Maybe<&2, H.Gate>, gates, remaining => popHold(remaining))
        H.holdAt(gate)
        aborted : Bool <- isAborted(signal)
        reply : Reply <- R.modify(List<&2, Reply>, Reply, replies, remaining => popReply(remaining))
        IO.sleep(1)
        +usage : PromptUsage <- R.modify(Rec.Record<String>, PromptUsage, prompts, previous => promptUsage(previous, input))
        +now : F64 <- Date.now()
        +stream : EventStream() <- Stream.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, EventStream()>, Unit, streams, old => (stream <> old, Unit{}))
        Bool.pick(Unit -> IO(Unit), aborted, _ => abortedReply(stream, Stamp{model, now, usage}), _ => answerAsync(stream, reply, Stamp{model, now, usage}, signal))(Unit{})
        return Done{T.borrowedStream(Unit, Tools.ToolError, stream)}

def provider(faux: Faux, input: H.Input()) -> IO(H.Output()): providing(faux, input)

# Prints every session event on the wire, and for message_update also the
# session event's own assistant message, which the wire form omits.
def observed(+event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.AgentEvent{T.MessageUpdate{+value, _}}:
      do IO<Unit>:
        H.printed(JsonEvent.toSessionJsonEvent(event))
        H.printed(Done{Json.object(Json.field("type", Json.text("session_update_message"), Json.field("message", JsonEvent.message(value), Nil{})))})
    case _: H.printed(JsonEvent.toSessionJsonEvent(event))

def observe(env: Unit, event: Session.AgentSessionEvent) -> IO(Unit): observed(event)

type Fixture is Data:
  Fixture{session: Session.AgentSession, listener: Session.Listener(), stream: Runtime.Stream(), validator: Loop.Validator(Tools.ToolError), converter: Runtime.Converter(), registry: StreamFn.Registry(Unit, Tools.ToolDetails, Runtime.LoopConfig(), Tools.ToolError), faux: Faux}

def emptyLoadout() -> Runtime.Loadout: Runtime.Loadout{Rec.new(String), Nil{}, Nil{}, Nil{}, None{}, Nil{}, None{}, Nil{}}

# The agent starts from the stored session's context, as the upstream
# harness's `agent.state.messages = buildSessionContext().messages`.
def contextList(context: Result<&2, &2, S.Error, S.SessionContext<Unit, Tools.ToolDetails, V.Value>>) -> List<&2, Session.Message()>:
  match context:
    case Done{S.SessionContext{messages, _, _}}: messages
    case Fail{_}: Nil{}

def contextOf(stored: Session.Session()) -> List<&2, Session.Message()>:
  contextList(S.sessionContext(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored)))

type Setup is Data:
  Setup{replies: List<&2, Reply>, gates: List<&2, Hold>, model: Ai.Model<Ai.JsonValue>}

# The loadout is built over the session's model runtime (an extension
# runner shares it).
# upstream's harness Agent has no session id, so the faux's prompt cache
# never applies (withUsageEstimate's cache branch needs one).
def harnessOptions(stream: Runtime.Stream(), converter: Runtime.Converter(), selected: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> Agent.AgentOptions<Unit, Tools.ToolDetails, Runtime.Custom(), Tools.ToolError, Unit>:
  Agent.AgentOptions{Some{Agent.AgentInitialState{Some{""}, selected, Some{Ai.Off{}}, Some{Nil{}}, None{}}}, Some{converter}, None{}, Some{stream}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

# `others` are further faux models the model runtime lists after the
# setup's (upstream registerFauxProvider({ models })).
def fixtureModels(+stored: Session.Session(), +cwd: String, +settings: Settings.SettingsManager, setup: Setup, others: List<&2, Ai.Model<Ai.JsonValue>>, build: Models.ModelRuntime -> IO(Runtime.Loadout)) -> IO(Fixture):
  match setup:
    case Setup{replies, gates, +model}:
      do IO<Fixture>:
        +replyRef : R.Ref<List<&2, Reply>> <- R.new(List<&2, Reply>, replies)
        +streams : R.Ref<List<&2, EventStream()>> <- R.new(List<&2, EventStream()>, Nil{})
        +gateRef : R.Ref<List<&2, Hold>> <- R.new(List<&2, Hold>, gates)
        +signalRef : R.Ref<Maybe<&2, Signal()>> <- R.new(Maybe<&2, Signal()>, None{})
        +promptRef : R.Ref<Rec.Record<String>> <- R.new(Rec.Record<String>, Rec.new(String))
        +stream : Runtime.Stream() <- C.create(~Faux, ~H.Input(), ~H.Output(), ~provider, Faux{replyRef, streams, gateRef, Ai.modelId(model), signalRef, promptRef})
        +registry : StreamFn.Registry(Unit, Tools.ToolDetails, Runtime.LoopConfig(), Tools.ToolError) <- StreamFn.create(Unit, Tools.ToolDetails, Runtime.LoopConfig(), Tools.ToolError)
        +validator : Loop.Validator(Tools.ToolError) <- Loop.createPlain(~Tools.ToolError, ~Runtime.validationError)
        +converter : Runtime.Converter() <- Runtime.createConverter(False{})
        created : Result<&2, &2, StreamFn.MissingDefault, Runtime.Owner()> <- Agent.new(~Unit, ~Tools.ToolDetails, ~Runtime.Custom(), ~Tools.ToolError, ~Unit, harnessOptions(stream, converter, Some{model}), registry, validator, Tools.emptyDetails())
        +agent : Runtime.Owner() <- H.requireAgent(created)
        Agent.replaceMessages(Unit, Tools.ToolDetails, Runtime.Custom(), Tools.ToolError, Unit, agent, contextOf(stored))
        +models : Models.ModelRuntime <- ModelFixture.create(ModelFixture.Source{"faux", "PI_FAUX_API_KEY", model <> others} <> Nil{})
        loadout : Runtime.Loadout <- build(models)
        +session : Session.AgentSession <- Session.create(agent, stored, settings, cwd, loadout, models, Nil{})
        +listener : Session.Listener() <- C.create(~Unit, ~Session.AgentSessionEvent, ~Unit, ~observe, Unit{})
        Session.subscribe(session, listener)
        return Fixture{session, listener, stream, validator, converter, registry, Faux{replyRef, streams, gateRef, Ai.modelId(model), signalRef, promptRef}}

def fixtureBuilt(+stored: Session.Session(), +cwd: String, +settings: Settings.SettingsManager, setup: Setup, build: Models.ModelRuntime -> IO(Runtime.Loadout)) -> IO(Fixture):
  fixtureModels(stored, cwd, settings, setup, Nil{}, build)

def fixtureWithLoadout(+stored: Session.Session(), +cwd: String, +settings: Settings.SettingsManager, setup: Setup, +loadout: Runtime.Loadout) -> IO(Fixture):
  fixtureBuilt(stored, cwd, settings, setup, models => IO.pure(Runtime.Loadout, loadout))

def fixtureWith(+stored: Session.Session(), +cwd: String, +settings: Settings.SettingsManager, setup: Setup) -> IO(Fixture):
  fixtureWithLoadout(stored, cwd, settings, setup, emptyLoadout())

def fixture(+stored: Session.Session(), +cwd: String, agentDir: String, setup: Setup) -> IO(Fixture):
  do IO<Fixture>:
    loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.options())
    fixtureWith(stored, cwd, H.settingsOf(loaded), setup)

def teardown(value: Fixture) -> IO(Unit):
  match value:
    case Fixture{+session, +listener, stream, validator, converter, registry, Faux{replies, streams, gates, _, signals, prompts}}:
      do IO<Unit>:
        Session.unsubscribe(session, listener)
        C.dispose(Session.AgentSessionEvent, Unit, listener)
        +agent : Runtime.Owner() = Session.agentOf(session)
        Session.dispose(session)
        Agent.dispose(Unit, Tools.ToolDetails, Runtime.Custom(), Tools.ToolError, Unit, agent)
        StreamFn.dispose(Unit, Tools.ToolDetails, Runtime.LoopConfig(), Tools.ToolError, registry)
        Loop.disposeValidation(Tools.ToolError, validator)
        Runtime.disposeConverter(converter)
        C.dispose(H.Input(), H.Output(), stream)
        unused : List<&2, Reply> <- R.dispose(List<&2, Reply>, replies)
        opened : List<&2, EventStream()> <- R.dispose(List<&2, EventStream()>, streams)
        H.disposeStreams(opened)
        held : List<&2, Hold> <- R.dispose(List<&2, Hold>, gates)
        signal : Maybe<&2, Signal()> <- R.dispose(Maybe<&2, Signal()>, signals)
        cached : Rec.Record<String> <- R.dispose(Rec.Record<String>, prompts)
        return Unit{}

def sessionOf(value: Fixture) -> Session.AgentSession:
  match value:
    case Fixture{session, _, _, _, _, _, _}: session

def plainSetup(replies: List<&2, Reply>) -> Setup: Setup{replies, Nil{}, H.fauxModel()}

def fixtureLoaded(+stored: Session.Session(), +cwd: String, +settings: Settings.SettingsManager, +loadout: Runtime.Loadout) -> IO(Fixture):
  fixtureWithLoadout(stored, cwd, settings, plainSetup(Nil{}), loadout)


def requireAppended(result: Sessions.Outcome(Sessions.Appended<Unit, Tools.ToolDetails, V.Value>)) -> IO(Session.Session()):
  match result:
    case Done{Sessions.Appended{session, _}}: IO.pure(Session.Session(), session)
    case Fail{error}: IO.die(Session.Session(), 1, Sessions.message(error))

# The session starts from the seed messages, stored in memory.
def seeded(seed: List<&2, Session.Message()>, +stored: Session.Session()) -> IO(Session.Session()):
  match seed:
    case Nil{}: IO.pure(Session.Session(), stored)
    case message <> rest:
      do IO<Session.Session()>:
        appended : Sessions.Outcome(Sessions.Appended<Unit, Tools.ToolDetails, V.Value>) <- Sessions.appendMessage(~Unit, ~Tools.ToolDetails, ~V.Value, ~Session.unitValue, ~Tools.detailsValue, ~Session.rawValue, stored, message)
        next : Session.Session() <- requireAppended(appended)
        seeded(rest, next)

def withSeeded(+dir: String, agentDir: String, seed: List<&2, Session.Message()>, setup: Setup, body: Session.AgentSession -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    uuids : Uuid.Generator <- Uuid.generator()
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(uuids, dir, Sessions.noOptions())
    empty : Session.Session() <- H.requireSession(created)
    stored : Session.Session() <- seeded(seed, empty)
    +value : Fixture <- fixture(stored, dir, agentDir, setup)
    body(sessionOf(value))
    teardown(value)

def withSession(+dir: String, agentDir: String, replies: List<&2, Reply>, body: Session.AgentSession -> IO(Unit)) -> IO(Unit):
  withSeeded(dir, agentDir, Nil{}, plainSetup(replies), body)

def promptWith(+text: String, +session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.prompt(session, text, Nil{}, None{})
    H.reportPrompt(result)
    H.reportMessages(session)

def reportName(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    IO.print("{\"type\":\"session_name\",\"name\":" ++ H.maybeQuoted(S.getSessionName(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored))) ++ "}")

def named(+name: String, +session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.setSessionName(session, name)
    H.reportOutcome("set_name", result)
    reportName(session)

# 'x' repeated.
def repeated(count: Nat) -> String: String.repeat("x", count)

def writeCall() -> Reply:
  +content = repeated(100n)
  Call{"call_7925", "write", Json.object(Json.field("path", Json.text("output.txt"), Json.field("content", Json.text(content), Nil{}))), "{\"path\":\"output.txt\",\"content\":\"" ++ content ++ "\"}"}

# upstream SettingsManager.inMemory(settings) behind a session whose resource
# reload (upstream DefaultResourceLoader.reload) reloads its settings.
def managerOf(pair: Settings.InMemorySettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, manager): manager

def reportSettings(+label: String, +manager: Settings.SettingsManager) -> IO(Unit):
  H.printed(Done{Json.object(Json.field("type", Json.text(label), Json.field("defaultThinkingLevel", Maybe.default(&2, V.Value, Maybe.map(&2, Ai.ModelThinkingLevel, V.Value, Settings.encodeThinking, Settings.getDefaultThinkingLevel(manager)), V.Null{}), Json.field("imageAutoResize", V.Boolean{Settings.getImageAutoResize(manager)}, Json.field("compactionEnabled", V.Boolean{Settings.getCompactionEnabled(manager)}, Json.field("global", Settings.toValue(Settings.getGlobalSettings(manager)), Nil{}))))))})

def reloadSettings(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.reload(session)
    H.reportOutcome("reload", result)
    manager : Settings.SettingsManager <- Session.getSettings(session)
    reportSettings("settings", manager)

def decoded(value: Result<&2, &2, Decode.ParseError, V.Value>) -> Settings.Outcome(Settings.Settings):
  match value:
    case Done{value}: Settings.decode(Settings.migrate(value))
    case Fail{_}: Settings.decode(V.Null{})

def reloadScenario(+dir: String, +initial: Settings.Outcome(Settings.Settings)) -> IO(Unit):
  match initial:
    case Fail{_}: IO.die(Unit, 1, "invalid initial settings")
    case Done{settings}:
      do IO<Unit>:
        uuids : Uuid.Generator <- Uuid.generator()
        created : Sessions.Outcome(Session.Session()) <- Session.memorySession(uuids, dir, Sessions.noOptions())
        stored : Session.Session() <- H.requireSession(created)
        memory : Settings.InMemorySettingsStorage & Settings.SettingsManager <- Settings.inMemory(settings, Settings.options())
        +value : Fixture <- fixtureWith(stored, dir, managerOf(memory), plainSetup(Nil{}))
        reloadSettings(sessionOf(value))
        teardown(value)

# suite/regressions/8989: a fork removes the context-invisible label that a
# compaction's boundary pointed to. Ids are the stamps upstream generates.
def Manager() -> Data: S.SessionManager<Unit, Tools.ToolDetails, V.Value>
def Step() -> Data: Result<&2, &2, S.Error, Manager()>

def then(step: Step(), next: Manager() -> Step()) -> Step():
  Result.bind(&2, &2, S.Error, Manager(), Manager(), step, next)

def stamp(+id: String) -> S.EntryStamp: S.EntryStamp{id, "2026-01-01T00:00:00.000Z"}

def userMsg(text: String) -> Session.Message(): T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, zero()}}}

def forkedAtLabel() -> Step():
  start = S.inMemory(Unit, Tools.ToolDetails, V.Value, S.SessionHeader{Some{3n}, "session", "2026-01-01T00:00:00.000Z", "/tmp", None{}})
  old = then(start, state => S.appendMessage(Unit, Tools.ToolDetails, V.Value, state, stamp("old"), userMsg("old")))
  labeled = then(old, state => S.appendLabelChange(Unit, Tools.ToolDetails, V.Value, state, stamp("label"), "old", Some{"checkpoint"}))
  kept = then(labeled, state => S.appendMessage(Unit, Tools.ToolDetails, V.Value, state, stamp("kept"), userMsg("kept")))
  compacted = then(kept, state => S.appendCompaction(Unit, Tools.ToolDetails, V.Value, state, stamp("compaction"), "summary", Some{"label"}, 100n, None{}, None{}, None{}))
  after = then(compacted, state => S.appendMessage(Unit, Tools.ToolDetails, V.Value, state, stamp("after"), userMsg("after")))
  then(after, state => S.createBranchedSession(Unit, Tools.ToolDetails, V.Value, state, "after", stamp("fork"), "copied-label" <> Nil{}))

def firstKept(entry: Maybe<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>) -> V.Value:
  match entry:
    case Some{S.Compaction{S.CompactionEntry{_, _, keep, _, _, _, _, _}}}: V.Text{keep}
    case _: V.Null{}

def contextMessages(context: Result<&2, &2, S.Error, S.SessionContext<Unit, Tools.ToolDetails, V.Value>>) -> V.Value:
  match context:
    case Done{S.SessionContext{messages, _, _}}: V.ArrayValue{JsonEvent.messages(messages)}
    case Fail{_}: V.Null{}

def reportFork(step: Step()) -> IO(Unit):
  match step:
    case Fail{_}: IO.print("{\"type\":\"fork_failed\"}")
    case Done{+state}: H.printed(Done{Json.object(Json.field("type", Json.text("fork"), Json.field("firstKeptEntryId", firstKept(S.getEntry(Unit, Tools.ToolDetails, V.Value, state, "compaction")), Json.field("messages", contextMessages(S.sessionContext(Unit, Tools.ToolDetails, V.Value, state)), Nil{}))))})

# A faux model with upstream's `models: [{ id: "faux-1", contextWindow, maxTokens }]`.
def namedModel(+id: String, window: U32, maxTokens: U32) -> Ai.Model<Ai.JsonValue>:
  Ai.Model{id, id, Ai.OpenAIResponsesApi{}, "faux", "https://faux.invalid", False{}, None{}, Ai.InputText{} <> Nil{}, None{}, Ai.ModelCost{zero(), zero(), zero(), zero(), None{}}, None{}, U32.to_f64(window), U32.to_f64(maxTokens), None{}, None{}, None{}}

def sizedModel(window: U32, maxTokens: U32) -> Ai.Model<Ai.JsonValue>: namedModel("faux-1", window, maxTokens)

def userAt(text: String, +timestamp: F64) -> Session.Message(): T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}}, timestamp}}}

def assistantAt(text: String, stop: Ai.StopReason, usage: Ai.Usage, +timestamp: F64) -> Session.Message():
  T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{textBlock(text), "openai-responses", "faux", "faux-1", None{}, None{}, None{}, None{}, usage, stop, None{}, None{}, None{}, None{}, timestamp}}}

def before(now: F64, ms: U32) -> F64: F64.sub(now, U32.to_f64(ms))

def reportRemaining(replies: R.Ref<List<&2, Reply>>) -> IO(Unit):
  do IO<Unit>:
    remaining : List<&2, Reply> <- R.read(List<&2, Reply>, replies)
    IO.print("{\"type\":\"remaining\",\"count\":" ++ Nat.show(List.length(&2, Reply, remaining)) ++ "}")

def repliesOf(value: Fixture) -> R.Ref<List<&2, Reply>>:
  match value:
    case Fixture{_, _, _, _, _, _, Faux{replies, _, _, _, _, _}}: replies

# Persisted entries as JSON messages (upstream sessionManager.getEntries()).
def entryMessages(entries: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>) -> List<&2, V.Value>:
  match entries:
    case Nil{}: Nil{}
    case S.SessionMessageEntry{_, message} <> rest: JsonEvent.message(message) <> entryMessages(rest)
    case _ <> rest: entryMessages(rest)

def reportPersisted(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    H.printed(Done{Json.object(Json.field("type", Json.text("persisted"), Json.field("messages", V.ArrayValue{entryMessages(S.getEntries(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored)))}, Nil{})))})
    H.reportEntries(session)

def seededFixture(+dir: String, agentDir: String, seed: List<&2, Session.Message()>, setup: Setup) -> IO(Fixture):
  do IO<Fixture>:
    uuids : Uuid.Generator <- Uuid.generator()
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(uuids, dir, Sessions.noOptions())
    empty : Session.Session() <- H.requireSession(created)
    stored : Session.Session() <- seeded(seed, empty)
    fixture(stored, dir, agentDir, setup)

# 8328: a zero-usage reply to `text` under a 100-token window.
def zeroUsageScenario(+dir: String, agentDir: String, +text: String) -> IO(Unit):
  do IO<Unit>:
    +value : Fixture <- seededFixture(dir, agentDir, Nil{}, Setup{Plain{"response"} <> Text{"threshold summary"} <> Nil{}, Nil{}, sizedModel(100, 20)})
    result : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), text, Nil{}, None{})
    H.reportPrompt(result)
    Session.waitForIdle(sessionOf(value))
    reportRemaining(repliesOf(value))
    teardown(value)

def fullUsage() -> Ai.Usage: Ai.Usage{U32.to_f64(100), zero(), zero(), zero(), None{}, None{}, U32.to_f64(100), Ai.UsageCost{zero(), zero(), zero(), zero(), zero()}}

# pre-prompt-compaction-no-continue: a length-stopped reply that fills the
# window is compacted before the next prompt, which then runs by itself.
def prePromptScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +now : F64 <- Date.now()
    +value : Fixture <- seededFixture(dir, agentDir, userAt("previous prompt", before(now, 1000)) <> assistantAt("length-stop assistant response", Ai.Length{}, fullUsage(), before(now, 500)) <> Nil{}, Setup{Text{"pre-prompt summary"} <> Text{"answered next prompt"} <> Nil{}, Nil{}, sizedModel(100, 100)})
    result : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "next prompt", Nil{}, None{})
    H.reportPrompt(result)
    reportRemaining(repliesOf(value))
    H.reportMessages(sessionOf(value))
    teardown(value)

type Compacted is Data:
  Compacted{result: Result<&2, &2, String, Compaction.CompactionResult>}

def compactInBackground(session: Session.AgentSession, done: Chan(Compacted)) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Compaction.CompactionResult> <- Session.compact(session, None{})
    sent : Bool <- Chan.send(Compacted, done, Compacted{result})
    R.requireSent(sent)

def reportCompacted(received: Maybe<&1, Compacted>) -> IO(Unit):
  match received:
    case Some{Compacted{result}}: H.reportCompact(result)
    case None{}: IO.print("{\"type\":\"compact_failed\",\"error\":\"compaction fiber did not finish\"}")

def release(gate: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Unit, gate, Unit{})
    R.requireSent(sent)

# 7150: a prompt while a manual compaction's summary request is held open.
def promptDuringCompaction(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +now : F64 <- Date.now()
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +gate : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Compacted) <- Chan.new(Compacted, 1)
    +value : Fixture <- seededFixture(dir, agentDir, userAt("old user message", before(now, 1000)) <> assistantAt("old assistant response", Ai.Stop{}, usageOf(zero()), before(now, 500)) <> Nil{}, Setup{Text{"manual compacted"} <> Text{"probe response"} <> Nil{}, Held{H.Gate{started, gate}} <> Nil{}, H.fauxModel()})
    IO.spawn(Unit, compactInBackground(sessionOf(value), done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    H.reportCompacting(sessionOf(value))
    probe : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "PROBE-7150", Nil{}, None{})
    H.reportOutcome("probe", probe)
    release(gate)
    finished : Maybe<&1, Compacted> <- Chan.recv(Compacted, done)
    reportCompacted(finished)
    H.reportMessages(sessionOf(value))
    reportPersisted(sessionOf(value))
    teardown(value)
    Chan.close(Unit, started)
    Chan.close(Unit, gate)
    Chan.close(Compacted, done)

def promptLater(session: Session.AgentSession, +text: String, done: Chan(Result<&2, &2, String, Unit>)) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.prompt(session, text, Nil{}, None{})
    sent : Bool <- Chan.send(Result<&2, &2, String, Unit>, done, result)
    R.requireSent(sent)

def reportLeaf(+label: String, +session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    stored : Session.Session() <- Session.sessionOf(session)
    IO.print("{\"type\":\"" ++ label ++ "\",\"leafId\":" ++ Decode.quote(H.currentLeaf(stored)) ++ "}")

def firstId(ids: List<&2, String>) -> String:
  match ids:
    case id <> _: id
    case Nil{}: "missing-entry"

def firstUser(stored: Session.Session()) -> String:
  firstId(H.userIds(S.getEntries(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored))))

# tree-during-streaming: navigation from inside the active response.
def treeDuringStreaming(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +gate : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Result<&2, &2, String, Unit>) <- Chan.new(Result<&2, &2, String, Unit>, 1)
    +value : Fixture <- seededFixture(dir, agentDir, userMsg("first") <> Nil{}, Setup{Text{"response"} <> Nil{}, Held{H.Gate{started, gate}} <> Nil{}, H.fauxModel()})
    reportLeaf("target", sessionOf(value))
    IO.spawn(Unit, promptLater(sessionOf(value), "second", done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    reportLeaf("active", sessionOf(value))
    stored : Session.Session() <- Session.sessionOf(sessionOf(value))
    navigated : Result<&2, &2, String, Session.Navigation> <- Session.navigateTree(sessionOf(value), firstUser(stored))
    H.reportNavigation(navigated)
    reportLeaf("after_navigation", sessionOf(value))
    release(gate)
    finished : Maybe<&1, Result<&2, &2, String, Unit>> <- Chan.recv(Result<&2, &2, String, Unit>, done)
    H.reportFinished(finished)
    teardown(value)
    Chan.close(Unit, started)
    Chan.close(Unit, gate)
    Chan.close(Result<&2, &2, String, Unit>, done)

def baseFields(base: S.SessionEntryBase, rest: List<&2, Rec.Property<V.Value>>) -> List<&2, Rec.Property<V.Value>>:
  match base:
    case S.SessionEntryBase{id, parent, _}: Json.field("id", Json.text(id), Json.field("parentId", Maybe.default(&2, V.Value, Maybe.map(&2, String, V.Value, p => V.Text{p}, parent), V.Null{}), rest))

# Entries in order, message entries with their message (upstream
# sessionManager.getEntries()).
def entryShapes(entries: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>) -> List<&2, V.Value>:
  match entries:
    case Nil{}: Nil{}
    case S.SessionMessageEntry{base, message} <> rest: Json.object(Json.field("type", Json.text("message"), baseFields(base, Json.field("message", JsonEvent.message(message), Nil{})))) <> entryShapes(rest)
    case S.Compaction{S.CompactionEntry{base, _, _, _, _, _, _, _}} <> rest: Json.object(Json.field("type", Json.text("compaction"), baseFields(base, Nil{}))) <> entryShapes(rest)
    case S.BranchSummaryEntry{base, _, summary, _, _, _} <> rest: Json.object(Json.field("type", Json.text("branch_summary"), baseFields(base, Json.field("summary", Json.text(summary), Nil{})))) <> entryShapes(rest)
    case _ <> rest: Json.object(Json.field("type", Json.text("other"), Nil{})) <> entryShapes(rest)

def reportEntryShapes(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    H.printed(Done{Json.object(Json.field("type", Json.text("entry_shapes"), Json.field("entries", V.ArrayValue{entryShapes(S.getEntries(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored)))}, Nil{})))})

def signalsOf(value: Fixture) -> R.Ref<Maybe<&2, Signal()>>:
  match value:
    case Fixture{_, _, _, _, _, _, Faux{_, _, _, _, signals, _}}: signals

# Waits (up to a second) until the held request's signal is aborted.
def untilAborted(fuel: Nat, +signals: R.Ref<Maybe<&2, Signal()>>) -> IO(Bool):
  match fuel:
    case 0n: IO.pure(Bool, False{})
    case 1n+rest:
      do IO<Bool>:
        signal : Maybe<&2, Signal()> <- R.read(Maybe<&2, Signal()>, signals)
        aborted : Bool <- isAborted(signal)
        Bool.pick(Unit -> IO(Bool), aborted, _ => IO.pure(Bool, True{}), _ => IO.bind(Unit, Bool, IO.sleep(1), _ => untilAborted(rest, signals)))(Unit{})

def reportAbortSeen(seen: Bool) -> IO(Unit): IO.print("{\"type\":\"request_aborted\",\"value\":" ++ H.boolJson(seen) ++ "}")

# 7253: a manual compaction requested while the second response is held.
def compactDuringResponse(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +gate : Chan(Unit) <- Chan.new(Unit, 1)
    +prompted : Chan(Result<&2, &2, String, Unit>) <- Chan.new(Result<&2, &2, String, Unit>, 1)
    +compacted : Chan(Compacted) <- Chan.new(Compacted, 1)
    +value : Fixture <- seededFixture(dir, agentDir, Nil{}, Setup{Call{"call_noop", "noop", V.ObjectValue{Rec.new(V.Value)}, "{}"} <> Text{"second response:" ++ repeated(4000n)} <> Text{"manual summary"} <> Text{"manual summary"} <> Nil{}, Pass{} <> Held{H.Gate{started, gate}} <> Nil{}, sizedModel(1000, 1000)})
    IO.spawn(Unit, promptLater(sessionOf(value), "Run the tool, then continue responding.", prompted))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    IO.spawn(Unit, compactInBackground(sessionOf(value), compacted))
    seen : Bool <- untilAborted(1000n, signalsOf(value))
    reportAbortSeen(seen)
    release(gate)
    finished : Maybe<&1, Result<&2, &2, String, Unit>> <- Chan.recv(Result<&2, &2, String, Unit>, prompted)
    H.reportFinished(finished)
    result : Maybe<&1, Compacted> <- Chan.recv(Compacted, compacted)
    reportCompacted(result)
    reportEntryShapes(sessionOf(value))
    teardown(value)
    Chan.close(Unit, started)
    Chan.close(Unit, gate)
    Chan.close(Result<&2, &2, String, Unit>, prompted)
    Chan.close(Compacted, compacted)

# Tool registry scenarios (5109, 2835): the runtime's tool resolution
# (Runtime.resolveTools) over the built-in tools, a loadout assembled as the
# runtime assembles it (registry, active tools, system prompt sections for
# them) and the session's tool API. The registry's tools carry the built-in
# names and descriptions with a stub execution: the scenarios never run them.
def stubExecute(unit: Unit, input: Tools.Input()) -> IO(Tools.Output()):
  IO.pure(Tools.Output(), Fail{Tools.failure("not executed")})

def stubTools(names: List<&2, Tools.ToolName>, +execute: Tools.Execute()) -> List<&2, Tools.Tool()>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest: T.AgentTool{Tools.toolName(name), Tools.promptSnippet(name), V.Null{}, None{}, Tools.toolName(name), None{}, execute, None{}, None{}} <> stubTools(rest, execute)

def optionalList(+text: String) -> Maybe<&2, List<&2, String>>:
  Bool.pick(Maybe<&2, List<&2, String>>, String.eq(text, "-"), None{}, Some{Bool.pick(List<&2, String>, String.is_empty(text), Nil{}, String.split(text, ','))})

def noToolsNamed(text: String) -> Maybe<&2, Runtime.NoTools>:
  match text:
    case "all": Some{Runtime.NoToolsAll{}}
    case "builtin": Some{Runtime.NoToolsBuiltin{}}
    case _: None{}

def toolOptions(+cwd: String, +agentDir: String, selection: Runtime.ToolSelection, +settings: Settings.SettingsManager) -> Runtime.CreateOptions:
  Runtime.CreateOptions{cwd, agentDir, "", "", "/pi", None{}, None{}, None{}, None{}, None{}, Nil{}, selection, False{}, Runtime.emptySeed(), settings, Runtime.ResourceOptions{Nil{}, True{}, Nil{}, True{}}}

def toolLoadout(+source: Runtime.LoadoutSource, setup: Runtime.ToolSetup, +execute: Tools.Execute()) -> Runtime.Loadout:
  match setup:
    case Runtime.ToolSetup{registry, active}:
      +tools = stubTools(registry, execute)
      +chosen = Runtime.activeTools(tools, active)
      Runtime.Loadout{Result.default(&2, &2, String, Prompt.SystemPromptSections(), Runtime.sectionsForTools(source, Session.toolNamesOf(chosen), Nil{}, Nil{}), Rec.new(String)), chosen, Nil{}, Nil{}, None{}, Nil{}, Some{source}, tools}

def infoNames(infos: List<&2, Session.ToolInfo>) -> List<&2, V.Value>:
  match infos:
    case Nil{}: Nil{}
    case Session.ToolInfo{name, _, _} <> rest: V.Text{name} <> infoNames(rest)

def texts(values: List<&2, String>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> texts(rest)

def reportTools(+label: String, +session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    all : List<&2, Session.ToolInfo> <- Session.getAllTools(session)
    active : List<&2, String> <- Session.getActiveToolNames(session)
    prompt : String <- Session.systemPrompt(session)
    H.printed(Done{Json.object(Json.field("type", Json.text(label), Json.field("all", V.ArrayValue{infoNames(all)}, Json.field("active", V.ArrayValue{texts(active)}, Json.field("systemPrompt", Json.text(prompt), Nil{})))))})

def activated(+session: Session.AgentSession, activate: Maybe<&2, List<&2, String>>) -> IO(Unit):
  match activate:
    case None{}: IO.pure(Unit, Unit{})
    case Some{names}:
      do IO<Unit>:
        Session.setActiveToolsByName(session, names)
        reportTools("activated", session)

def toolsWith(+dir: String, +agentDir: String, selection: Runtime.ToolSelection, activate: Maybe<&2, List<&2, String>>, +settings: Settings.SettingsManager) -> IO(Unit):
  do IO<Unit>:
    +execute : Tools.Execute() <- C.create(~Unit, ~Tools.Input(), ~Tools.Output(), ~stubExecute, Unit{})
    +options : Runtime.CreateOptions = toolOptions(dir, agentDir, selection, settings)
    +loadout : Runtime.Loadout = toolLoadout(Runtime.LoadoutSource{Paths.Environment{dir, agentDir, Runtime.urlContext()}, options, "/pi"}, Runtime.toolSetupOf(options), execute)
    uuids : Uuid.Generator <- Uuid.generator()
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(uuids, dir, Sessions.noOptions())
    stored : Session.Session() <- H.requireSession(created)
    +value : Fixture <- fixtureLoaded(stored, dir, settings, loadout)
    reportTools("tools", sessionOf(value))
    activated(sessionOf(value), activate)
    teardown(value)
    C.dispose(Tools.Input(), Tools.Output(), execute)

def toolsScenario(+dir: String, +agentDir: String, +allow: String, +exclude: String, +noTools: String, +activate: String) -> IO(Unit):
  do IO<Unit>:
    loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(dir, agentDir, Settings.options())
    toolsWith(dir, agentDir, Runtime.ToolSelection{optionalList(allow), noToolsNamed(noTools), optionalList(exclude)}, optionalList(activate), H.settingsOf(loaded))

# 6324: navigation with a summary of the abandoned branch.
def branchUsageCost(usage: Maybe<&2, Ai.Usage>) -> V.Value:
  match usage:
    case Some{Ai.Usage{_, _, _, _, _, _, _, Ai.UsageCost{_, _, _, _, total}}}: V.Number{total}
    case None{}: V.Null{}

def optionalText(value: Maybe<&2, String>) -> V.Value:
  match value:
    case Some{text}: V.Text{text}
    case None{}: V.Null{}

def reportTreeNavigation(result: Result<&2, &2, String, Session.TreeNavigation>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("{\"type\":\"tree_error\",\"error\":" ++ Decode.quote(message) ++ "}")
    case Done{Session.TreeNavigationAborted{}}: IO.print("{\"type\":\"tree_navigation\",\"cancelled\":true,\"aborted\":true}")
    case Done{Session.TreeNavigationCancelled{}}: IO.print("{\"type\":\"tree_navigation\",\"cancelled\":true}")
    case Done{Session.TreeNavigated{editorText, leafId, Some{S.BranchSummaryEntry{S.SessionEntryBase{id, _, _}, _, summary, _, usage, _}}}}:
      H.printed(Done{Json.object(Json.field("type", Json.text("tree_navigation"), Json.field("cancelled", V.Boolean{False{}}, Json.field("editorText", optionalText(editorText), Json.field("leafId", Maybe.default(&2, V.Value, Maybe.map(&2, String, V.Value, t => V.Text{t}, leafId), V.Null{}), Json.field("summaryEntry", Json.object(Json.field("type", Json.text("branch_summary"), Json.field("id", Json.text(id), Json.field("summary", Json.text(summary), Json.field("costTotal", branchUsageCost(usage), Nil{}))))), Nil{}))))))})
    case Done{Session.TreeNavigated{editorText, leafId, _}}: IO.print("{\"type\":\"tree_navigation\",\"cancelled\":false,\"editorText\":" ++ H.maybeQuoted(editorText) ++ ",\"leafId\":" ++ H.maybeQuoted(leafId) ++ ",\"summaryEntry\":null}")

def branchSummaryScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +value : Fixture <- seededFixture(dir, agentDir, userMsg("first branch") <> assistantAt("first reply", Ai.Stop{}, usageOf(zero()), zero()) <> userMsg("abandoned branch work") <> assistantAt("abandoned reply", Ai.Stop{}, usageOf(zero()), zero()) <> Nil{}, Setup{Costed{"branch summary text"} <> Nil{}, Nil{}, H.fauxModel()})
    stored : Session.Session() <- Session.sessionOf(sessionOf(value))
    result : Result<&2, &2, String, Session.TreeNavigation> <- Session.navigateTreeWith(sessionOf(value), firstUser(stored), Session.NavigateTreeOptions{True{}, None{}, None{}, None{}})
    reportTreeNavigation(result)
    reportRemaining(repliesOf(value))
    teardown(value)

# agent-session-tree-navigation.test.ts over the faux: the prompts run in
# order (each answered "reply N"), `branch` first navigates to the first
# assistant reply and prompts once more, then the navigation runs. Targets:
# first-user, user:N, assistant:N (1-based) or leaf. `hold` holds the summary
# request and aborts the branch summary while it is held.
def roleOf(entry: S.SessionEntry<Unit, Tools.ToolDetails, V.Value>) -> String:
  match entry:
    case S.SessionMessageEntry{_, T.LlmMessage{Ai.User{_}}}: "user"
    case S.SessionMessageEntry{_, T.LlmMessage{Ai.Assistant{_}}}: "assistant"
    case _: "other"

def idOfEntry(entry: S.SessionEntry<Unit, Tools.ToolDetails, V.Value>) -> String: S.entryId(Unit, Tools.ToolDetails, V.Value, entry)

def entryIds(entries: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>, +role: String) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> rest:
      +tail = entryIds(rest, role)
      Bool.pick(List<&2, String>, String.eq(roleOf(entry), role), idOfEntry(entry) <> tail, tail)

def nth(ids: List<&2, String>, index: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ids, index - 1n), "missing-entry")

def indexOf(+text: String) -> Nat: Maybe.default(&2, Nat, Nat.read(text), 0n)

def selectTarget(parts: List<&2, String>, +entries: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>, +leaf: String) -> String:
  match parts:
    case "user" <> index <> Nil{}: nth(entryIds(entries, "user"), indexOf(index))
    case "assistant" <> index <> Nil{}: nth(entryIds(entries, "assistant"), indexOf(index))
    case "leaf" <> Nil{}: leaf
    case _: nth(entryIds(entries, "user"), 1n)

def targetIn(+stored: Session.Session(), +target: String) -> String:
  selectTarget(String.split(target, ':'), S.getEntries(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored)), H.currentLeaf(stored))

def reply(+index: Nat) -> Reply: Text{"reply " ++ Nat.show(index)}

def replies(prompts: List<&2, String>, +index: Nat) -> List<&2, Reply>:
  match prompts:
    case Nil{}: Nil{}
    case _ <> rest: reply(index) <> replies(rest, index + 1n)

def promptsOf(+text: String) -> List<&2, String>: Bool.pick(List<&2, String>, String.eq(text, "-"), Nil{}, String.split(text, ';'))

def navigateOptions(+summarize: String, +custom: String) -> Session.NavigateTreeOptions:
  Session.NavigateTreeOptions{String.eq(summarize, "summarize"), Bool.pick(Maybe<&2, String>, String.eq(custom, "-"), None{}, Some{custom}), None{}, None{}}

def reportLeafState(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    stored : Session.Session() <- Session.sessionOf(session)
    IO.print("{\"type\":\"leaf\",\"leafId\":" ++ H.maybeQuoted(S.getLeafId(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored))) ++ "}")
    reportEntryShapes(session)

def promptAll(+session: Session.AgentSession, prompts: List<&2, String>) -> IO(Unit):
  match prompts:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Session.prompt(session, text, Nil{}, None{})
        promptAll(session, rest)

def branched(+session: Session.AgentSession, prompts: List<&2, String>) -> IO(Unit):
  match prompts:
    case Nil{}: IO.pure(Unit, Unit{})
    case more:
      do IO<Unit>:
        stored : Session.Session() <- Session.sessionOf(session)
        moved : Result<&2, &2, String, Session.Navigation> <- Session.navigateTree(session, targetIn(stored, "assistant:1"))
        promptAll(session, more)

type Navigated is Data:
  Navigated{result: Result<&2, &2, String, Session.TreeNavigation>}

def navigateInBackground(session: Session.AgentSession, +targetId: String, options: Session.NavigateTreeOptions, done: Chan(Navigated)) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Session.TreeNavigation> <- Session.navigateTreeWith(session, targetId, options)
    sent : Bool <- Chan.send(Navigated, done, Navigated{result})
    R.requireSent(sent)

def reportNavigated(received: Maybe<&1, Navigated>) -> IO(Unit):
  match received:
    case Some{Navigated{result}}: reportTreeNavigation(result)
    case None{}: IO.print("{\"type\":\"tree_error\",\"error\":\"navigation fiber did not finish\"}")

def heldNavigation(+session: Session.AgentSession, +targetId: String, options: Session.NavigateTreeOptions, started: Chan(Unit), gate: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    +done : Chan(Navigated) <- Chan.new(Navigated, 1)
    IO.spawn(Unit, navigateInBackground(session, targetId, options, done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    H.reportCompacting(session)
    Session.abortBranchSummary(session)
    release(gate)
    finished : Maybe<&1, Navigated> <- Chan.recv(Navigated, done)
    reportNavigated(finished)
    Chan.close(Navigated, done)

def holdsFor(prompts: List<&2, String>) -> List<&2, Hold>:
  match prompts:
    case Nil{}: Nil{}
    case _ <> rest: Pass{} <> holdsFor(rest)

def treeScenario(+dir: String, agentDir: String, +prompts: String, +more: String, +target: String, +summarize: String, +custom: String, +hold: String) -> IO(Unit):
  do IO<Unit>:
    +first : List<&2, String> = promptsOf(prompts)
    +second : List<&2, String> = promptsOf(more)
    +count : Nat = List.length(&2, String, first)
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +gate : Chan(Unit) <- Chan.new(Unit, 1)
    +held : Bool = String.eq(hold, "hold")
    +value : Fixture <- seededFixture(dir, agentDir, Nil{}, Setup{List.append(&2, Reply, replies(first, 1n), List.append(&2, Reply, replies(second, count + 1n), [Text{"branch summary"}])), Bool.pick(List<&2, Hold>, held, List.append(&2, Hold, holdsFor(first), List.append(&2, Hold, holdsFor(second), [Held{H.Gate{started, gate}}])), Nil{}), H.fauxModel()})
    promptAll(sessionOf(value), first)
    branched(sessionOf(value), second)
    reportLeafState(sessionOf(value))
    stored : Session.Session() <- Session.sessionOf(sessionOf(value))
    +targetId : String = targetIn(stored, target)
    IO.print("{\"type\":\"target\",\"id\":" ++ Decode.quote(targetId) ++ "}")
    Bool.pick(Unit -> IO(Unit), held, _ => heldNavigation(sessionOf(value), targetId, navigateOptions(summarize, custom), started, gate), _ => IO.bind(Result<&2, &2, String, Session.TreeNavigation>, Unit, Session.navigateTreeWith(sessionOf(value), targetId, navigateOptions(summarize, custom)), reportTreeNavigation))(Unit{})
    reportLeafState(sessionOf(value))
    teardown(value)
    Chan.close(Unit, started)
    Chan.close(Unit, gate)

# 9178: navigation while a manual compaction's summary request is held.
def treeDuringCompaction(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +gate : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Compacted) <- Chan.new(Compacted, 1)
    +value : Fixture <- seededFixture(dir, agentDir, userMsg("first user") <> assistantAt("first assistant", Ai.Stop{}, usageOf(zero()), zero()) <> userMsg("second user") <> assistantAt("second assistant", Ai.Stop{}, usageOf(zero()), zero()) <> Nil{}, Setup{Text{"summary"} <> Text{"prefix summary"} <> Nil{}, Held{H.Gate{started, gate}} <> Nil{}, H.fauxModel()})
    reportLeaf("original", sessionOf(value))
    IO.spawn(Unit, compactInBackground(sessionOf(value), done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    H.reportCompacting(sessionOf(value))
    stored : Session.Session() <- Session.sessionOf(sessionOf(value))
    navigated : Result<&2, &2, String, Session.Navigation> <- Session.navigateTree(sessionOf(value), targetIn(stored, "assistant:1"))
    H.reportNavigation(navigated)
    reportLeaf("during", sessionOf(value))
    release(gate)
    finished : Maybe<&1, Compacted> <- Chan.recv(Compacted, done)
    reportCompacted(finished)
    reportEntryShapes(sessionOf(value))
    H.reportMessages(sessionOf(value))
    teardown(value)
    Chan.close(Unit, started)
    Chan.close(Unit, gate)
    Chan.close(Compacted, done)

def number(+text: String) -> Nat: Maybe.default(&2, Nat, Nat.read(text), 0n)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "name" <> dir <> agentDir <> name <> Nil{}: withSession(dir, agentDir, Nil{}, session => named(name, session))
    case "prompt" <> dir <> agentDir <> text <> answerText <> Nil{}: withSession(dir, agentDir, Text{answerText} <> Nil{}, session => promptWith(text, session))
    case "stream" <> dir <> agentDir <> count <> Nil{}: withSession(dir, agentDir, Text{repeated(number(count))} <> Nil{}, session => promptWith("respond", session))
    case "toolcall" <> dir <> agentDir <> Nil{}: withSession(dir, agentDir, writeCall() <> Text{"done"} <> Nil{}, session => promptWith("write a file", session))
    case "fork_label" <> Nil{}: reportFork(forkedAtLabel())
    case "zero_usage" <> dir <> agentDir <> text <> Nil{}: zeroUsageScenario(dir, agentDir, text)
    case "pre_prompt" <> dir <> agentDir <> Nil{}: prePromptScenario(dir, agentDir)
    case "compaction_prompt" <> dir <> agentDir <> Nil{}: promptDuringCompaction(dir, agentDir)
    case "tree_streaming" <> dir <> agentDir <> Nil{}: treeDuringStreaming(dir, agentDir)
    case "compact_during_response" <> dir <> agentDir <> Nil{}: compactDuringResponse(dir, agentDir)
    case "tools" <> dir <> agentDir <> allow <> exclude <> noTools <> activate <> Nil{}: toolsScenario(dir, agentDir, allow, exclude, noTools, activate)
    case "branch_summary" <> dir <> agentDir <> Nil{}: branchSummaryScenario(dir, agentDir)
    case "tree" <> dir <> agentDir <> prompts <> more <> target <> summarize <> custom <> hold <> Nil{}: treeScenario(dir, agentDir, prompts, more, target, summarize, custom, hold)
    case "tree_during_compaction" <> dir <> agentDir <> Nil{}: treeDuringCompaction(dir, agentDir)
    case "settings_reload" <> dir <> agentDir <> settings <> Nil{}: reloadScenario(dir, decoded(Decode.parse(settings)))
    case _: IO.die(Unit, 1, "usage: regressions <name <dir> <agentDir> <name> | prompt <dir> <agentDir> <text> <reply> | stream <dir> <agentDir> <characters> | toolcall <dir> <agentDir>>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

import Base
import ../types.bend as T
import ../utils/cost.bend as Cost
import ../utils/event-stream.bend as Events
import ../utils/hash.bend as Hash
import ../utils/json.bend as JsonWire
import ../utils/json-parse.bend as JsonRepair
import ../utils/headers.bend as HeaderUtils
import ../utils/model-api.bend as ModelApi
import ../utils/sanitize-unicode.bend as Unicode
import ../utils/schema-json.bend as SchemaJson
import ../utils/text.bend as Text
import ../utils/thinking-levels.bend as Levels
import ../utils/transcript.bend as Transcript
import ./constrained-sampling.bend as Sampling
import ./provider-fetch.bend as Http
import ./simple-options.bend as Simple
import ./transform-messages.bend as Transform
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/pi-user-agent.bend as UserAgent
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/utf16.bend as Utf16
import ../../../runtime/src/utf8.bend as Utf8

# The native Mistral Chat Completions provider (upstream
# api/mistral-conversations.ts): SDK-style payloads serialized to the wire
# format, pi's User-Agent and header overrides, the request timeout, Mistral's
# SSE framing and the chunk fold into assistant events.

def J() -> Data: T.JsonValue

def str(value: String) -> J(): T.JsonString{value}

def num(value: F64) -> J(): T.JsonNumber{value}

def obj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}

def arr(values: List<&2, J()>) -> J(): T.JsonArray{values}

def field(name: String, value: J(), rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>: R.Property{name, value} <> rest

def optional(name: String, value: Maybe<&2, J()>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match value:
    case None{}: rest
    case Some{item}: R.Property{name, item} <> rest

def MISTRAL_TOOL_CALL_ID_LENGTH() -> Nat: 9n

def MAX_MISTRAL_ERROR_BODY_CHARS() -> Nat: 4000n

# Options
# -------

# upstream MistralOptions["toolChoice"].
type MistralToolChoice is Data:
  ChoiceAuto{}
  ChoiceNone{}
  ChoiceAny{}
  ChoiceRequired{}
  ChoiceFunction{name: String}

# upstream MistralOptions extends StreamOptions; the shared options are one
# field. promptMode's only value is "reasoning". reasoningEffort is the
# model's mapped thinking value (upstream types it "none" | "high").
type MistralOptions<-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data> is Data:
  MistralOptions{base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, toolChoice: Maybe<&2, MistralToolChoice>, promptMode: Maybe<&2, Unit>, reasoningEffort: Maybe<&2, String>}

def Options(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data) -> Data: MistralOptions<Signal, Telemetry, Fetch, Error>

def usesReasoningEffort(+id: String) -> Bool:
  String.eq(id, "mistral-small-2603") || String.eq(id, "mistral-small-latest") || String.starts_with(id, "mistral-medium-") || String.eq(id, "zai-glm-5-2")

def usesPromptModeReasoning(+reasoning: Bool, +id: String) -> Bool: reasoning && Bool.not(usesReasoningEffort(id))

def mappedEffort(value: Maybe<&2, T.Nullable<String>>) -> String:
  match value:
    case Some{T.PresentValue{mapped}}: mapped
    case _: "high"

# upstream mapReasoningEffort: the model's mapping for the level, else "high".
def mapReasoningEffort(model: T.Model<J()>, level: T.ThinkingLevel) -> String:
  match model:
    case T.Model{_, _, _, _, _, _, mapping, _, _, _, _, _, _, _, _, _}: mappedEffort(Levels.mapped(mapping, T.Thinking{level}))

def simpleChoice(value: T.ToolChoice) -> MistralToolChoice:
  match value:
    case T.AutoTool{}: ChoiceAuto{}
    case T.NoTool{}: ChoiceNone{}

def thinkingMap(model: T.Model<J()>) -> Maybe<&2, T.ThinkingLevelMap>:
  match model:
    case T.Model{_, _, _, _, _, _, mapping, _, _, _, _, _, _, _, _, _}: mapping

def enabledLevel(level: T.ModelThinkingLevel) -> Maybe<&2, T.ThinkingLevel>:
  match level:
    case T.Off{}: None{}
    case T.Thinking{selected}: Some{selected}

def clampedReasoning(+model: T.Model<J()>, level: Maybe<&2, T.ThinkingLevel>) -> Maybe<&2, T.ThinkingLevel>:
  match level:
    case None{}: None{}
    case Some{requested}: enabledLevel(Levels.closest(Levels.available(T.modelReasoning(model), thinkingMap(model)), Levels.rank(T.Thinking{requested}), T.Off{}))

def promptModeFor(+model: T.Model<J()>, +reasoning: Maybe<&2, T.ThinkingLevel>) -> Maybe<&2, Unit>:
  Bool.pick(Maybe<&2, Unit>, T.modelReasoning(model) && Maybe.is_some(&2, T.ThinkingLevel, reasoning) && usesPromptModeReasoning(T.modelReasoning(model), T.modelId(model)), Some{Unit{}}, None{})

def effortFor(+model: T.Model<J()>, reasoning: Maybe<&2, T.ThinkingLevel>) -> Maybe<&2, String>:
  match reasoning:
    case None{}: None{}
    case Some{level}: Bool.pick(Maybe<&2, String>, T.modelReasoning(model) && usesReasoningEffort(T.modelId(model)), Some{mapReasoningEffort(model, level)}, None{})

def simpleToolChoice(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Maybe<&2, MistralToolChoice>:
  match options:
    case Some{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, Some{choice}, _, _, _}}: Some{simpleChoice(choice)}
    case _: None{}

def simpleReasoning(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Maybe<&2, T.ThinkingLevel>:
  match options:
    case Some{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, level, _, _}}: level
    case None{}: None{}

def simpleKey(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Maybe<&2, String>:
  match options:
    case Some{T.SimpleStreamOptions{_, _, key, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: key
    case None{}: None{}

def missingKey(model: T.Model<J()>) -> String: "No API key for provider: " ++ T.modelProvider(model)

def keyedOptions(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>, key: Maybe<&2, String>) -> Result<&2, &2, String, Options(Signal, Telemetry, Fetch, Error)>:
  match key:
    case None{}: Fail{missingKey(model)}
    case Some{SNil{}}: Fail{missingKey(model)}
    case Some{key}:
      +base = Simple.buildBaseOptions(~G, ~D, ~J(), ~Signal, ~Telemetry, ~Fetch, ~Error, model, context, options, Some{key})
      +reasoning = clampedReasoning(model, simpleReasoning(Signal, Telemetry, Fetch, Error, options))
      Done{MistralOptions{base, simpleToolChoice(Signal, Telemetry, Fetch, Error, options), promptModeFor(model, reasoning), effortFor(model, reasoning)}}

# upstream streamSimple's options: the shared base options with the tool
# choice, and promptMode or reasoningEffort for a reasoning model with a
# (clamped, non-off) level. A missing key is thrown before any stream exists.
def streamSimpleOptions(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Result<&2, &2, String, Options(Signal, Telemetry, Fetch, Error)>:
  keyedOptions(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, model, context, options, simpleKey(Signal, Telemetry, Fetch, Error, options))

# Tool-call ids
# -------------

def alphanumeric(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{+code}, rest}:
      +tail = alphanumeric(rest)
      Bool.pick(String, (U32.is_ge(code, 48) && U32.is_le(code, 57)) || (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122)), SCon{Chr{code}, tail}, tail)

def seeded(+seedBase: String, +attempt: Nat) -> String:
  Bool.pick(String, Nat.is_eq(attempt, 0n), seedBase, seedBase ++ ":" ++ Nat.show(attempt))

# upstream deriveMistralToolCallId: a 9-character alphanumeric id.
def deriveMistralToolCallId(+id: String, +attempt: Nat) -> String:
  +normalized = alphanumeric(id)
  Bool.pick(String, Nat.is_eq(attempt, 0n) && Nat.is_eq(String.length(normalized), MISTRAL_TOOL_CALL_ID_LENGTH()), normalized, String.take(alphanumeric(Hash.shortHash(seeded(Bool.pick(String, String.is_empty(normalized), id, normalized), attempt))), MISTRAL_TOOL_CALL_ID_LENGTH()))

# upstream createMistralToolCallIdNormalizer: ids map to derived candidates
# that no other id owns.
type IdMaps is Data:
  IdMaps{ids: R.Record<String>, owners: R.Record<String>}

def claimed(+id: String, +candidate: String, maps: IdMaps) -> IdMaps & String:
  match maps:
    case IdMaps{ids, owners}: (IdMaps{R.set(String, ids, id, candidate), R.set(String, owners, candidate, id)}, candidate)

def ownerOf(maps: IdMaps, candidate: String) -> Maybe<&2, String>:
  match maps:
    case IdMaps{_, owners}: R.get(String, owners, candidate)

def owned(+id: String, owner: Maybe<&2, String>) -> Bool:
  match owner:
    case None{}: False{}
    case Some{other}: Bool.not(String.eq(other, id))

# Try attempts until a candidate is free or already this id's.
@unsafe def attemptId(+id: String, +attempt: Nat, +maps: IdMaps, taken: Bool) -> IdMaps & String:
  match taken:
    case False{}: claimed(id, deriveMistralToolCallId(id, attempt), maps)
    case True{}: attemptId(id, attempt + 1n, maps, owned(id, ownerOf(maps, deriveMistralToolCallId(id, attempt + 1n))))

def existingId(maps: IdMaps, id: String) -> Maybe<&2, String>:
  match maps:
    case IdMaps{ids, _}: R.get(String, ids, id)

def normalizedId(+maps: IdMaps, +id: String, existing: Maybe<&2, String>) -> IdMaps & String:
  match existing:
    case Some{SCon{c, cs}}: (maps, SCon{c, cs})
    case _: attemptId(id, 0n, maps, owned(id, ownerOf(maps, deriveMistralToolCallId(id, 0n))))

def normalizeWith(+id: String, +maps: IdMaps) -> IdMaps & String:
  normalizedId(maps, id, existingId(maps, id))

def normalizeInput(-A: Data, -G: Data, -M: Data, maps: Ref.Ref<IdMaps>, input: Transform.NormalizeToolCallIdInput<A, G, M>) -> IO(Result<&2, &2, Sampling.Error, String>):
  match input:
    case Transform.NormalizeToolCallIdInput{+id, _, _}:
      do IO<Result<&2, &2, Sampling.Error, String>>:
        normalized : String <- Ref.modify(IdMaps, String, maps, current => normalizeWith(id, current))
        return Done{normalized}

# Messages
# --------

def textChunk(text: String) -> J(): obj(field("type", str("text"), field("text", str(text), Nil{})))

def imageChunk(mimeType: String, data: String) -> J(): obj(field("type", str("image_url"), field("imageUrl", str("data:" ++ mimeType ++ ";base64," ++ data), Nil{})))

def thinkingChunk(text: String) -> J(): obj(field("type", str("thinking"), field("thinking", arr([obj(field("type", str("text"), field("text", str(text), Nil{})))]), Nil{})))

def chatMessage(role: String, rest: List<&2, R.Property<J()>>) -> J(): obj(field("role", str(role), rest))

def hasImage(parts: List<&2, T.TextImageContent>) -> Bool:
  match parts:
    case Nil{}: False{}
    case T.TextImageImage{_} <> _: True{}
    case _ <> rest: hasImage(rest)

def userChunks(parts: List<&2, T.TextImageContent>, +supportsImages: Bool) -> List<&2, J()>:
  match parts:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{text, _}} <> rest: textChunk(Unicode.sanitizeSurrogates(text)) <> userChunks(rest, supportsImages)
    case T.TextImageImage{T.ImageContent{data, mimeType}} <> rest:
      +tail = userChunks(rest, supportsImages)
      Bool.pick(List<&2, J()>, supportsImages, imageChunk(mimeType, data) <> tail, tail)

def userBlocks(+hadImages: Bool, +supportsImages: Bool, chunks: List<&2, J()>) -> List<&2, J()>:
  match chunks:
    case Nil{}: Bool.pick(List<&2, J()>, hadImages && Bool.not(supportsImages), chatMessage("user", field("content", str("(image omitted: model does not support images)"), Nil{})) <> Nil{}, Nil{})
    case +first <> rest: chatMessage("user", field("content", arr(first <> rest), Nil{})) <> Nil{}

def userMessage(content: T.UserContent, +supportsImages: Bool) -> List<&2, J()>:
  match content:
    case T.UserText{text}: chatMessage("user", field("content", str(Unicode.sanitizeSurrogates(text)), Nil{})) <> Nil{}
    case T.UserBlocks{+parts}: userBlocks(hasImage(parts), supportsImages, userChunks(parts, supportsImages))

def nonblank(text: String) -> Bool: Bool.not(String.is_empty(Space.trim(text)))

def argumentsJson(value: V.Value) -> String:
  match value:
    case V.Null{}: "{}"
    case V.Boolean{False{}}: "{}"
    case V.Text{SNil{}}: "{}"
    case other: Maybe.default(&2, String, JsonWire.stringify(SchemaJson.toJson(other)), "{}")

def assistantChunks(blocks: List<&2, T.AssistantContent<V.Value>>) -> List<&2, J()>:
  match blocks:
    case Nil{}: Nil{}
    case T.AssistantText{T.TextContent{+text, _}} <> rest:
      +tail = assistantChunks(rest)
      Bool.pick(List<&2, J()>, nonblank(text), textChunk(Unicode.sanitizeSurrogates(text)) <> tail, tail)
    case T.AssistantThinking{T.ThinkingContent{+thinking, _, _}} <> rest:
      +tail = assistantChunks(rest)
      Bool.pick(List<&2, J()>, nonblank(thinking), thinkingChunk(Unicode.sanitizeSurrogates(thinking)) <> tail, tail)
    case _ <> rest: assistantChunks(rest)

def assistantCalls(blocks: List<&2, T.AssistantContent<V.Value>>) -> List<&2, J()>:
  match blocks:
    case Nil{}: Nil{}
    case T.AssistantToolCall{T.ToolCall{id, name, arguments, _, _}} <> rest: obj(field("id", str(id), field("type", str("function"), field("function", obj(field("name", str(name), field("arguments", str(argumentsJson(arguments)), Nil{}))), field("index", num(F.fromU32(0)), Nil{}))))) <> assistantCalls(rest)
    case _ <> rest: assistantCalls(rest)

def nonemptyArray(name: String, values: List<&2, J()>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match values:
    case Nil{}: rest
    case +first <> others: field(name, arr(first <> others), rest)

def assistantMessage(+blocks: List<&2, T.AssistantContent<V.Value>>) -> List<&2, J()>:
  +chunks = assistantChunks(blocks)
  +calls = assistantCalls(blocks)
  Bool.pick(List<&2, J()>, List.is_empty(&2, J(), chunks) && List.is_empty(&2, J(), calls), Nil{}, chatMessage("assistant", field("prefix", T.JsonBoolean{False{}}, nonemptyArray("content", chunks, nonemptyArray("toolCalls", calls, Nil{})))) <> Nil{})

def resultTexts(parts: List<&2, T.TextImageContent>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{text, _}} <> rest: Unicode.sanitizeSurrogates(text) <> resultTexts(rest)
    case _ <> rest: resultTexts(rest)

def resultImages(parts: List<&2, T.TextImageContent>) -> List<&2, J()>:
  match parts:
    case Nil{}: Nil{}
    case T.TextImageImage{T.ImageContent{data, mimeType}} <> rest: imageChunk(mimeType, data) <> resultImages(rest)
    case _ <> rest: resultImages(rest)

# upstream buildToolResultText.
def buildToolResultText(text: String, +hasImages: Bool, +supportsImages: Bool, +isError: Bool) -> String:
  +trimmed = Space.trim(text)
  +errorPrefix = Bool.pick(String, isError, "[tool error] ", "")
  Bool.pick(String, Bool.not(String.is_empty(trimmed)), errorPrefix ++ trimmed ++ Bool.pick(String, hasImages && Bool.not(supportsImages), "\n[tool image omitted: model does not support images]", ""), Bool.pick(String, hasImages, Bool.pick(String, supportsImages, Bool.pick(String, isError, "[tool error] (see attached image)", "(see attached image)"), Bool.pick(String, isError, "[tool error] (image omitted: model does not support images)", "(image omitted: model does not support images)")), Bool.pick(String, isError, "[tool error] (no tool output)", "(no tool output)")))

def toolResultMessage(-D: Data, result: T.ToolResultMessage<D>, +supportsImages: Bool) -> List<&2, J()>:
  match result:
    case T.ToolResultMessage{toolCallId, toolName, +content, _, _, isError, _}:
      +text = buildToolResultText(String.join(resultTexts(content), "\n"), hasImage(content), supportsImages, isError)
      chatMessage("tool", field("toolCallId", str(toolCallId), field("name", str(toolName), field("content", arr(textChunk(text) <> Bool.pick(List<&2, J()>, supportsImages, resultImages(content), Nil{})), Nil{})))) <> Nil{}

def systemMessage(text: String) -> List<&2, J()>:
  match text:
    case SNil{}: Nil{}
    case SCon{c, cs}: chatMessage("system", field("content", str(Unicode.sanitizeSurrogates(SCon{c, cs})), Nil{})) <> Nil{}

def systemText(+update: T.SystemMessage<V.Value>, +first: Bool) -> String:
  Bool.pick(String, first, Text.renderComplete(V.Value, update), Text.renderUpdate(V.Value, update))

def choiceJson(value: MistralToolChoice) -> J():
  match value:
    case ChoiceAuto{}: str("auto")
    case ChoiceNone{}: str("none")
    case ChoiceAny{}: str("any")
    case ChoiceRequired{}: str("required")
    case ChoiceFunction{name}: obj(field("type", str("function"), field("function", obj(field("name", str(name), Nil{})), Nil{})))

# upstream shouldUsePromptCaching: the session id, unless retention is "none".
def promptCacheKey(retention: Maybe<&2, T.CacheRetention>, sessionId: Maybe<&2, String>) -> Maybe<&2, String>:
  match retention sessionId:
    case Some{T.CacheNone{}} _: None{}
    case _ Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _ _: None{}

def toolsField(tools: List<&2, J()>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match tools:
    case Nil{}: rest
    case +first <> others: field("tools", arr(first <> others), rest)

def EventStream(-G: Data) -> Data: Events.AssistantMessageEventStream(V.Value, G)

def supportsMidConvoSystemMessages(model: T.Model<J()>) -> Maybe<&2, Bool>:
  match model:
    case T.Model{_, _, T.MistralConversationsApi{}, _, _, _, _, _, _, _, _, _, _, _, _, Some{T.MistralConversationsCompat{value}}}: value
    case _: None{}

def timeoutNumber(value: Result<&2, &2, F.Error, Nat>) -> U32:
  match value:
    case Done{number}: U32.from_nat(Nat.min(4294967295n, number))
    case Fail{_}: 60000

# upstream `options?.timeoutMs ?? 60_000`.
def requestTimeout(value: Maybe<&2, F64>) -> U32:
  match value:
    case None{}: 60000
    case Some{milliseconds}: timeoutNumber(F.convert(F.truncate(milliseconds)))

# The request settings that stay the same whatever the payload.
type Request<-Reason: Data, -E: Data> is Data:
  Request{key: String, agent: String, headers: Maybe<&2, T.ProviderHeaders()>, onPayload: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, fetch: Fetch.Fetch(Reason), urlContext: URL.Context, timeout: U32, temperature: Maybe<&2, F64>, maxTokens: Maybe<&2, F64>, choice: Maybe<&2, MistralToolChoice>, promptMode: Maybe<&2, Unit>, effort: Maybe<&2, String>, cacheKey: Maybe<&2, String>}

def Message(-G: Data) -> Data: T.AssistantMessage<V.Value, G>

# upstream consumeChatStream's state: the output message, the open text or
# thinking block (always the last content block) and the tool blocks by key,
# in insertion order, with their argument scratch buffers.
type BlockKind is Data:
  TextKind{}
  ThinkingKind{}

type ToolKey is Data:
  IndexKey{index: F64}
  IdKey{id: String}

type ToolEntry is Data:
  ToolEntry{key: ToolKey, index: Nat, partialArgs: String}

type State<-G: Data> is Data:
  State{output: Message(G), current: Maybe<&2, BlockKind>, tools: List<&2, ToolEntry>}

def zero() -> F64: F.fromU32(0)

def createOutput(-G: Data, model: T.Model<J()>, timestamp: F64) -> Message(G):
  match model:
    case T.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _, _, _}: T.AssistantMessage{Nil{}, ModelApi.name(api), provider, id, None{}, None{}, None{}, None{}, T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}, T.Pending{}, None{}, None{}, None{}, None{}, timestamp}

def createState(-G: Data, model: T.Model<J()>, timestamp: F64) -> State<G>:
  State{createOutput(G, model, timestamp), None{}, Nil{}}

def Event(-G: Data) -> Data: T.AssistantMessageEvent<V.Value, G>

def push(-G: Data, +events: EventStream(G), event: Event(G)) -> IO(Unit):
  Events.push(Event(G), Message(G), events, event)

def withError(-G: Data, message: Message(G), stop: T.StopReason, errorMessage: String) -> Message(G):
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, _, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, Some{errorMessage}, raw, endTurn, timestamp}

# upstream's catch block: the output so far, stopped as aborted when the
# caller's signal is aborted and as an error otherwise.
def failed(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, output: Message(G), message: String) -> IO(Unit):
  do IO<Unit>:
    +aborted : Bool <- Abort.aborted(Reason, parent)
    push(G, events, T.StreamError{Bool.pick(T.ErrorReason, aborted, T.ErrorAborted{}, T.ErrorError{}), withError(G, output, Bool.pick(T.StopReason, aborted, T.Aborted{}, T.Error{}), message)})

def outputOf(-G: Data, state: State<G>) -> Message(G):
  match state:
    case State{output, _, _}: output

def normalizeBody(-A: Data, -G: Data, -M: Data, maps: Ref.Ref<IdMaps>) -> Transform.NormalizeToolCallIdInput<A, G, M> -> IO(Result<&2, &2, Sampling.Error, String>):
  input => normalizeInput(A, G, M, maps, input)

def converted(-G: Data, -D: Data, value: T.Message<V.Value, V.Value, G, D>, +first: Bool, +supportsImages: Bool) -> List<&2, J()>:
  match value:
    case T.System{system}: systemMessage(systemText(system, first))
    case T.User{T.UserMessage{content, _}}: userMessage(content, supportsImages)
    case T.Assistant{T.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: assistantMessage(content)
    case T.ToolResult{result}: toolResultMessage(D, result, supportsImages)

# upstream toChatMessages.
def toChatMessages(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>, +supportsImages: Bool, +first: Bool) -> List<&2, J()>:
  match messages:
    case Nil{}: Nil{}
    case value <> rest: List.append(&2, J(), converted(G, D, value, first, supportsImages), toChatMessages(G, D, rest, supportsImages, False{}))

def functionTool(+name: String, description: String, strict: Maybe<&2, Bool>, parameters: Result<&2, &2, Sampling.Error, V.Value>) -> Result<&2, &2, Sampling.Error, J()>:
  match parameters:
    case Fail{cause}: Fail{cause}
    case Done{schema}: Done{obj(field("type", str("function"), field("function", obj(field("name", str(name), field("description", str(description), field("parameters", SchemaJson.toJson(schema), field("strict", T.JsonBoolean{Maybe.default(&2, Bool, strict, False{})}, Nil{}))))), Nil{})))}

def strictTool(+tool: T.Tool<V.Value>, resolved: Result<&2, &2, Sampling.Error, Maybe<&2, Bool>>) -> Result<&2, &2, Sampling.Error, J()>:
  match tool resolved:
    case _ Fail{cause}: Fail{cause}
    case T.Tool{name, description, _, _} Done{+strict}: functionTool(name, description, strict, Sampling.getJsonSchemaToolParameters(tool, strict))

# upstream toFunctionTools: strict JSON schemas where the tool asks for them.
def toFunctionTools(tools: List<&2, T.Tool<V.Value>>) -> Result<&2, &2, Sampling.Error, List<&2, J()>>:
  match tools:
    case Nil{}: Done{Nil{}}
    case +tool <> rest:
      do Result<&2, &2, Sampling.Error, List<&2, J()>>:
        converted : J() <- strictTool(tool, Sampling.resolveJsonSchemaStrictSampling(tool, True{}))
        others : List<&2, J()> <- toFunctionTools(rest)
        return converted <> others

def withRequest(-Reason: Data, -E: Data, request: Request<Reason, E>, agent: String) -> Request<Reason, E>:
  match request:
    case Request{key, _, headers, onPayload, onResponse, fetch, urlContext, timeout, temperature, maxTokens, choice, promptMode, effort, cacheKey}: Request{key, agent, headers, onPayload, onResponse, fetch, urlContext, timeout, temperature, maxTokens, choice, promptMode, effort, cacheKey}

# upstream buildChatPayload, in the SDK's camelCase shape that onPayload sees.
def buildChatPayload(model: T.Model<J()>, messages: List<&2, J()>, tools: List<&2, J()>, temperature: Maybe<&2, F64>, maxTokens: Maybe<&2, F64>, choice: Maybe<&2, MistralToolChoice>, promptMode: Maybe<&2, Unit>, effort: Maybe<&2, String>, cacheKey: Maybe<&2, String>) -> J():
  obj(field("model", str(T.modelId(model)), field("stream", T.JsonBoolean{True{}}, field("messages", arr(messages), toolsField(tools, optional("temperature", Maybe.map(&2, F64, J(), num, temperature), optional("maxTokens", Maybe.map(&2, F64, J(), num, maxTokens), optional("toolChoice", Maybe.map(&2, MistralToolChoice, J(), choiceJson, choice), optional("promptMode", Maybe.map(&2, Unit, J(), mode => str("reasoning"), promptMode), optional("reasoningEffort", Maybe.map(&2, String, J(), str, effort), optional("promptCacheKey", Maybe.map(&2, String, J(), str, cacheKey), Nil{})))))))))))

def modelHeaders(model: T.Model<J()>) -> Maybe<&2, R.Record<String>>:
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, headers, _}: headers

def namedAffinity(entries: List<&2, String>) -> Bool:
  match entries:
    case Nil{}: False{}
    case name <> rest: String.eq(String.to_lower(name), "x-affinity") || namedAffinity(rest)

def propertyNames(-A: Data, entries: List<&2, R.Property<A>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, _} <> rest: name <> propertyNames(A, rest)

def recordKeys(-A: Data, record: R.Record<A>) -> List<&2, String>:
  match record:
    case R.Record{entries}: propertyNames(A, entries)

def modelAffinity(value: Maybe<&2, R.Record<String>>) -> Bool:
  match value:
    case None{}: False{}
    case Some{record}: namedAffinity(recordKeys(String, record))

def optionAffinity(value: Maybe<&2, T.ProviderHeaders()>) -> Bool:
  match value:
    case None{}: False{}
    case Some{record}: namedAffinity(recordKeys(T.Nullable<String>, record))

def withAffinity(result: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, affinity: Maybe<&2, String>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  match affinity:
    case None{}: result
    case Some{session}: Http.layered(result, "x-affinity", session)

# upstream buildMistralHeaders.
def buildMistralHeaders(agent: String, key: String, +modelHeaders: Maybe<&2, R.Record<String>>, +optionHeaders: Maybe<&2, T.ProviderHeaders()>, cacheKey: Maybe<&2, String>) -> Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>:
  +base = Http.headerList([R.Property{"User-Agent", agent}, R.Property{"accept", "text/event-stream"}, R.Property{"authorization", "Bearer " ++ key}, R.Property{"content-type", "application/json"}])
  +layered = Http.overridden(Http.overridden(base, Some{HeaderUtils.overlayStrings(R.new(T.Nullable<String>), modelHeaders)}), optionHeaders)
  withAffinity(layered, Bool.pick(Maybe<&2, String>, modelAffinity(modelHeaders) || optionAffinity(optionHeaders), None{}, cacheKey))

def withoutSuffix(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'?', _}: SNil{}
    case SCon{'#', _}: SNil{}
    case SCon{c, rest}: SCon{c, withoutSuffix(rest)}

def trimTrailingSlashes(reversed: String) -> String:
  match reversed:
    case SCon{'/', rest}: trimTrailingSlashes(rest)
    case other: String.reverse(other)

# upstream requestMistralStream's URL: `v1/chat/completions` resolved against
# the base URL with one trailing slash.
def requestUrl(model: T.Model<J()>) -> String:
  match model:
    case T.Model{_, _, _, _, base, _, _, _, _, _, _, _, _, _, _, _}: trimTrailingSlashes(String.reverse(withoutSuffix(base))) ++ "/v1/chat/completions"

# What the request needs once the payload is settled.
type Setup<-Reason: Data, -E: Data> is Data:
  Setup{model: T.Model<J()>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>, onResponse: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, fetch: Fetch.Fetch(Reason), url: Result<&2, &2, URL.Error, URL.URL>, timeout: U32}

def mapObject(value: J(), change: R.Record<J()> -> R.Record<J()>) -> J():
  match value:
    case T.JsonObject{fields}: T.JsonObject{change(fields)}
    case other: other

def remapped(+fields: R.Record<J()>, +source: String, target: String, value: Maybe<&2, J()>) -> R.Record<J()>:
  match value:
    case None{}: fields
    case Some{item}: R.remove(J(), R.set(J(), fields, target, item), source)

type Rename is Data:
  Rename{source: String, target: String}

# upstream remapMistralProperty: `record[target] = record[source]` (in place
# when target exists), then the source member is deleted.
def remap(+fields: R.Record<J()>, +source: String, target: String) -> R.Record<J()>:
  remapped(fields, source, target, R.get(J(), fields, source))

def remapAll(pairs: List<&2, Rename>, fields: R.Record<J()>) -> R.Record<J()>:
  match pairs:
    case Nil{}: fields
    case Rename{source, target} <> rest: remapAll(rest, remap(fields, source, target))

def payloadPairs() -> List<&2, Rename>:
  [Rename{"topP", "top_p"}, Rename{"maxTokens", "max_tokens"}, Rename{"randomSeed", "random_seed"}, Rename{"responseFormat", "response_format"}, Rename{"toolChoice", "tool_choice"}, Rename{"presencePenalty", "presence_penalty"}, Rename{"frequencyPenalty", "frequency_penalty"}, Rename{"parallelToolCalls", "parallel_tool_calls"}, Rename{"reasoningEffort", "reasoning_effort"}, Rename{"promptMode", "prompt_mode"}, Rename{"promptCacheKey", "prompt_cache_key"}, Rename{"safePrompt", "safe_prompt"}]

def replaced(+fields: R.Record<J()>, +name: String, value: Maybe<&2, J()>) -> R.Record<J()>:
  match value:
    case None{}: fields
    case Some{item}: R.set(J(), fields, name, item)

def chunkPairs() -> List<&2, Rename>:
  [Rename{"imageUrl", "image_url"}, Rename{"documentUrl", "document_url"}, Rename{"documentName", "document_name"}, Rename{"fileId", "file_id"}, Rename{"referenceIds", "reference_ids"}, Rename{"inputAudio", "input_audio"}]

def wireChunk(chunk: J()) -> J(): mapObject(chunk, fields => remapAll(chunkPairs(), fields))

def wireChunks(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case chunk <> rest: wireChunk(chunk) <> wireChunks(rest)

def wireContent(value: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonArray{values}}: Some{T.JsonArray{wireChunks(values)}}
    case other: other

def wireMessageFields(+fields: R.Record<J()>) -> R.Record<J()>:
  +remapped = remapAll([Rename{"toolCalls", "tool_calls"}, Rename{"toolCallId", "tool_call_id"}], fields)
  replaced(remapped, "content", wireContent(R.get(J(), remapped, "content")))

# upstream toMistralWireMessage.
def toMistralWireMessage(value: J()) -> J(): mapObject(value, fields => wireMessageFields(fields))

def wireMessages(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: toMistralWireMessage(value) <> wireMessages(rest)

def wireMessageList(value: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonArray{values}}: Some{T.JsonArray{wireMessages(values)}}
    case other: other

def wireSchema(value: J()) -> J(): mapObject(value, fields => remap(fields, "schemaDefinition", "schema"))

def objectOnly(value: J()) -> J(): wireSchema(value)

def wireFormatFields(+fields: R.Record<J()>) -> R.Record<J()>:
  +remapped = remap(fields, "jsonSchema", "json_schema")
  replaced(remapped, "json_schema", Maybe.map(&2, J(), J(), schema => objectOnly(schema), R.get(J(), remapped, "json_schema")))

def wireFormat(value: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonObject{fields}}: Some{T.JsonObject{wireFormatFields(fields)}}
    case other: other

def wirePayloadFields(+fields: R.Record<J()>) -> R.Record<J()>:
  +remapped = remapAll(payloadPairs(), fields)
  +messages = replaced(remapped, "messages", wireMessageList(R.get(J(), remapped, "messages")))
  replaced(messages, "response_format", wireFormat(R.get(J(), messages, "response_format")))

# upstream toMistralWirePayload: SDK camelCase members renamed to the wire's
# snake_case, including message, content-chunk and response-format members.
def toMistralWirePayload(payload: J()) -> J(): mapObject(payload, fields => wirePayloadFields(fields))

def truncateErrorText(+text: String, +maxChars: Nat) -> String:
  +length = Utf16.length(text)
  Bool.pick(String, Nat.is_le(length, maxChars), text, Utf16.take(text, maxChars) ++ "... [truncated " ++ Nat.show(length - maxChars) ++ " chars]")

# upstream formatMistralError for a MistralHttpError.
def httpErrorMessage(+status: U32, +statusText: String, body: String) -> String:
  +trimmed = Space.trim(body)
  Bool.pick(String, String.is_empty(trimmed), "Mistral API error (" ++ U32.show(status) ++ "): " ++ Bool.pick(String, String.is_empty(statusText), "Request failed with status " ++ U32.show(status), statusText), "Mistral API error (" ++ U32.show(status) ++ "): " ++ truncateErrorText(trimmed, MAX_MISTRAL_ERROR_BODY_CHARS()))

# A failed read reports the abort reason: the caller's abort or the request
# timeout (DOMException messages), or the transport's termination.
def readFailure(-Reason: Data, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> String:
  match reason:
    case Some{Abort.Supplied{Deadline.Expired{}}}: "The operation was aborted due to timeout"
    case Some{_}: "This operation was aborted"
    case None{}: "terminated"

def classified(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +signal: Fetch.Signal(Reason), output: Message(G)) -> IO(Unit):
  do IO<Unit>:
    reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, signal)
    failed(~Reason, ~G, events, parent, output, readFailure(Reason, reason))

def failedStatus(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +signal: Fetch.Signal(Reason), output: Message(G), +metadata: Response.Metadata, text: Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String>) -> IO(Unit):
  match text:
    case Fail{_}: classified(~Reason, ~G, events, parent, signal, output)
    case Done{body}: failed(~Reason, ~G, events, parent, output, httpErrorMessage(Response.metadataStatus(metadata), Response.statusText(metadata), body))

# How reading ended: the body or a [DONE] marker ended the events, reading
# failed (its message depends on the abort reason), or an event was invalid.
type Outcome is Data:
  Consumed{}
  ReadFailed{}
  Invalid{message: String}

type Reading<-G: Data> is Data:
  Reading{decoder: Utf8.Decoder, buffer: String, state: State<G>}

type Phase is Data:
  Streaming{}
  Ending{}
  Ended{}

type Loop<-G: Data> is Data:
  Pull{reading: Reading<G>}
  Frames{reading: Reading<G>, frames: List<&2, String>, phase: Phase}
  Stop{state: State<G>, outcome: Outcome}

def splitLines(text: String, current: String, lines: List<&2, String>) -> List<&2, String>:
  match text:
    case SNil{}: List.reverse(&2, String, String.reverse(current) <> lines)
    case SCon{'\r', SCon{'\n', rest}}: splitLines(rest, SNil{}, String.reverse(current) <> lines)
    case SCon{'\r', rest}: splitLines(rest, SNil{}, String.reverse(current) <> lines)
    case SCon{'\n', rest}: splitLines(rest, SNil{}, String.reverse(current) <> lines)
    case SCon{c, rest}: splitLines(rest, SCon{c, current}, lines)

def dataLines(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case +line <> rest:
      +tail = dataLines(rest)
      Bool.pick(List<&2, String>, String.starts_with(line, "data:"), Space.trimStart(String.drop(line, 5n)) <> tail, tail)

# The data of an event block: its `data:` lines, joined and trimmed.
def eventData(raw: String) -> String:
  Space.trim(String.join(dataLines(splitLines(raw, SNil{}, Nil{})), "\n"))

# upstream parseMistralEvent.
type ParsedEvent is Data:
  NoEvent{}
  StreamDone{}
  ChunkEvent{data: R.Record<V.Value>}
  InvalidEvent{message: String}

def choicesArray(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.ArrayValue{_}}: True{}
    case _: False{}

def chunkValue(value: V.Value) -> ParsedEvent:
  match value:
    case V.ObjectValue{+fields}: Bool.pick(ParsedEvent, choicesArray(R.get(V.Value, fields, "choices")), ChunkEvent{fields}, InvalidEvent{"Invalid Mistral streaming event"})
    case _: InvalidEvent{"Invalid Mistral streaming event"}

def parsedChunk(result: Result<&2, &2, Decode.ParseError, V.Value>) -> ParsedEvent:
  match result:
    case Fail{_}: InvalidEvent{"Invalid JSON in Mistral streaming event"}
    case Done{value}: chunkValue(value)

def dataEvent(data: String) -> ParsedEvent:
  match data:
    case SNil{}: NoEvent{}
    case "[DONE]": StreamDone{}
    case other: parsedChunk(Decode.parse(other))

def parseMistralEvent(raw: String) -> ParsedEvent: dataEvent(eventData(raw))

def readingState(-G: Data, reading: Reading<G>) -> State<G>:
  match reading:
    case Reading{_, _, state}: state

type Framed is Data:
  Framed{frames: List<&2, String>, rest: String}

# upstream findMistralEventBoundary splits at the first of \r\n\r\n, \r\n\r,
# \r\n\n, \r\r\n, \n\r\n, \r\r, \n\r or \n\n (alternatives in that order).
def splitEvents(text: String, current: String, frames: List<&2, String>) -> Framed:
  match text:
    case SNil{}: Framed{List.reverse(&2, String, frames), String.reverse(current)}
    case SCon{'\r', SCon{'\n', SCon{'\r', SCon{'\n', rest}}}}: splitEvents(rest, SNil{}, String.reverse(current) <> frames)
    case SCon{'\r', SCon{'\n', SCon{'\r', rest}}}: splitEvents(rest, SNil{}, String.reverse(current) <> frames)
    case SCon{'\r', SCon{'\n', SCon{'\n', rest}}}: splitEvents(rest, SNil{}, String.reverse(current) <> frames)
    case SCon{'\r', SCon{'\r', SCon{'\n', rest}}}: splitEvents(rest, SNil{}, String.reverse(current) <> frames)
    case SCon{'\n', SCon{'\r', SCon{'\n', rest}}}: splitEvents(rest, SNil{}, String.reverse(current) <> frames)
    case SCon{'\r', SCon{'\r', rest}}: splitEvents(rest, SNil{}, String.reverse(current) <> frames)
    case SCon{'\n', SCon{'\r', rest}}: splitEvents(rest, SNil{}, String.reverse(current) <> frames)
    case SCon{'\n', SCon{'\n', rest}}: splitEvents(rest, SNil{}, String.reverse(current) <> frames)
    case SCon{c, rest}: splitEvents(rest, SCon{c, current}, frames)

def framed(-G: Data, decoder: Utf8.Decoder, state: State<G>, phase: Phase, split: Framed) -> Loop<G>:
  match split:
    case Framed{frames, rest}: Frames{Reading{decoder, rest, state}, frames, phase}

def decodedChunk(-G: Data, reading: Reading<G>, decoded: Utf8.Decoded, phase: Phase) -> Loop<G>:
  match reading decoded:
    case Reading{_, buffer, state} Utf8.Decoded{decoder, text}: framed(G, decoder, state, phase, splitEvents(buffer ++ text, SNil{}, Nil{}))

def decoderOf(-G: Data, reading: Reading<G>) -> Utf8.Decoder:
  match reading:
    case Reading{decoder, _, _}: decoder

def pulled(-Reason: Data, -G: Data, +reading: Reading<G>, result: Result<&2, &2, Http.ReadError(Reason), Maybe<&2, List<&2, U32>>>) -> Loop<G>:
  match result:
    case Fail{_}: Stop{readingState(G, reading), ReadFailed{}}
    case Done{None{}}: decodedChunk(G, reading, Utf8.finish(decoderOf(G, reading)), Ending{})
    case Done{Some{bytes}}: decodedChunk(G, reading, Utf8.decode(decoderOf(G, reading), bytes), Streaming{})

def blankBuffer(-G: Data, reading: Reading<G>) -> Bool:
  match reading:
    case Reading{_, buffer, _}: String.is_empty(Space.trim(buffer))

def tailFrame(-G: Data, reading: Reading<G>) -> Loop<G>:
  match reading:
    case Reading{decoder, buffer, state}: Frames{Reading{decoder, "", state}, buffer <> Nil{}, Ended{}}

def exhausted(-G: Data, +reading: Reading<G>, phase: Phase) -> Loop<G>:
  match phase:
    case Streaming{}: Pull{reading}
    case Ending{}: Bool.pick(Loop<G>, blankBuffer(G, reading), Stop{readingState(G, reading), Consumed{}}, tailFrame(G, reading))
    case Ended{}: Stop{readingState(G, reading), Consumed{}}

type Step<-G: Data> is Data:
  Step{state: State<G>, events: List<&2, Event(G)>}

def withUsage(-G: Data, message: Message(G), usage: T.Usage, +cost: T.UsageCost) -> Message(G):
  match message usage:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, _, stop, deferred, error, raw, endTurn, timestamp} T.Usage{input, output, cacheRead, cacheWrite, longWrite, reasoning, total, _}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, T.Usage{input, output, cacheRead, cacheWrite, longWrite, reasoning, total, cost}, stop, deferred, error, raw, endTurn, timestamp}

def usageOf(-G: Data, message: Message(G)) -> T.Usage: T.assistantUsage(V.Value, G, message)

def truthyNumber(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{+number}}: Bool.pick(Maybe<&2, F64>, F.isEqual(F.compare(number, zero())) || F.isNaN(number), None{}, Some{number})
    case _: None{}

def nonNull(value: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.Null{}}: None{}
    case other: other

def member(value: Maybe<&2, V.Value>, name: String) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: nonNull(R.get(V.Value, fields, name))
    case _: None{}

def firstPresent(values: List<&2, Maybe<&2, V.Value>>) -> Maybe<&2, V.Value>:
  match values:
    case Nil{}: None{}
    case Some{value} <> _: Some{value}
    case None{} <> rest: firstPresent(rest)

def finiteNumber(value: Maybe<&2, V.Value>) -> F64:
  match value:
    case Some{V.Number{+number}}: Bool.pick(F64, F.isFinite(F.decode(number)), number, zero())
    case _: zero()

# upstream getMistralCachedPromptTokens.
def cachedTokens(+usage: R.Record<V.Value>, +prompt: F64) -> F64:
  +usageValue = {Some{V.ObjectValue{usage}} : Maybe<&2, V.Value>}
  +raw = firstPresent([member(member(usageValue, "promptTokensDetails"), "cachedTokens"), member(member(usageValue, "prompt_tokens_details"), "cached_tokens"), member(member(usageValue, "promptTokenDetails"), "cachedTokens"), member(member(usageValue, "prompt_token_details"), "cached_tokens"), nonNull(R.get(V.Value, usage, "numCachedTokens")), nonNull(R.get(V.Value, usage, "num_cached_tokens"))])
  F.minimum(prompt, F.maximum(zero(), finiteNumber(raw)))

def computedUsage(+usage: R.Record<V.Value>, previous: T.Usage) -> T.Usage:
  match previous:
    case T.Usage{_, _, _, _, longWrite, reasoning, _, cost}:
      +prompt = Maybe.default(&2, F64, truthyNumber(R.get(V.Value, usage, "prompt_tokens")), zero())
      +cached = cachedTokens(usage, prompt)
      +input = F.maximum(zero(), F.subtract(prompt, cached))
      +output = Maybe.default(&2, F64, truthyNumber(R.get(V.Value, usage, "completion_tokens")), zero())
      T.Usage{input, output, cached, zero(), longWrite, reasoning, Maybe.default(&2, F64, truthyNumber(R.get(V.Value, usage, "total_tokens")), F.add(F.add(F.add(input, output), cached), zero())), cost}

def usageStep(-G: Data, +model: T.Model<J()>, state: State<G>, value: Maybe<&2, V.Value>) -> State<G>:
  match state value:
    case State{+output, current, tools} Some{V.ObjectValue{+usage}}:
      +computed = computedUsage(usage, usageOf(G, output))
      State{withUsage(G, output, computed, Cost.calculate(J(), model, computed)), current, tools}
    case other _: other

def withResponseId(-G: Data, message: Message(G), id: Maybe<&2, V.Value>) -> Message(G):
  match message id:
    case T.AssistantMessage{content, api, provider, model, responseModel, None{}, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp} Some{V.Text{value}}: T.AssistantMessage{content, api, provider, model, responseModel, Some{value}, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}
    case T.AssistantMessage{content, api, provider, model, responseModel, Some{SNil{}}, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp} Some{V.Text{value}}: T.AssistantMessage{content, api, provider, model, responseModel, Some{value}, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}
    case other _: other

def mapOutput(-G: Data, state: State<G>, change: Message(G) -> Message(G)) -> State<G>:
  match state:
    case State{output, current, tools}: State{change(output), current, tools}

def firstChoice(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<V.Value>>:
  match value:
    case Some{V.ArrayValue{V.ObjectValue{fields} <> _}}: Some{fields}
    case _: None{}

def objectFields(value: Maybe<&2, V.Value>) -> R.Record<V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: fields
    case _: R.new(V.Value)

# upstream mapChatStopReason.
type StopMapping is Data:
  StopMapping{stopReason: T.StopReason, errorMessage: Maybe<&2, String>}

def mapChatStopReason(+reason: String) -> StopMapping:
  match reason:
    case "stop": StopMapping{T.Stop{}, None{}}
    case "length": StopMapping{T.Length{}, None{}}
    case "model_length": StopMapping{T.Length{}, None{}}
    case "tool_calls": StopMapping{T.ToolUse{}, None{}}
    case "error": StopMapping{T.Error{}, Some{"Provider stopped with: error"}}
    case other: StopMapping{T.Error{}, Some{"Provider stopped with: " ++ other}}

def withStop(-G: Data, message: Message(G), +raw: String, mapped: StopMapping) -> Message(G):
  match message mapped:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, _, deferred, error, _, endTurn, timestamp} StopMapping{stop, errorMessage}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, Maybe.or(&2, String, errorMessage, error), Some{raw}, endTurn, timestamp}

def finishReason(-G: Data, state: State<G>, value: Maybe<&2, V.Value>) -> State<G>:
  match value:
    case Some{V.Text{SCon{+c, +cs}}}: mapOutput(G, state, message => withStop(G, message, SCon{c, cs}, mapChatStopReason(SCon{c, cs})))
    case _: state

def withEvents(-G: Data, step: Step<G>, before: List<&2, Event(G)>) -> Step<G>:
  match step:
    case Step{state, events}: Step{state, List.append(&2, Event(G), before, events)}

def then(-G: Data, step: Step<G>, next: State<G> -> Step<G>) -> Step<G>:
  match step:
    case Step{state, events}: withEvents(G, next(state), events)

def sameKind(current: Maybe<&2, BlockKind>, kind: BlockKind) -> Bool:
  match current kind:
    case Some{TextKind{}} TextKind{}: True{}
    case Some{ThinkingKind{}} ThinkingKind{}: True{}
    case _ _: False{}

def Content() -> Data: T.AssistantContent<V.Value>

def withContent(-G: Data, message: Message(G), change: List<&2, Content()> -> List<&2, Content()>) -> Message(G):
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{change(content), api, provider, model, responseModel, responseId, level, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}

def lastUpdated(content: List<&2, Content()>, change: Content() -> Content()) -> List<&2, Content()>:
  match content:
    case Nil{}: Nil{}
    case head <> Nil{}: change(head) <> Nil{}
    case head <> rest: head <> lastUpdated(rest, change)

def appendText(block: Content(), +delta: String) -> Content():
  match block:
    case T.AssistantText{T.TextContent{text, signature}}: T.AssistantText{T.TextContent{text ++ delta, signature}}
    case T.AssistantThinking{T.ThinkingContent{thinking, signature, redacted}}: T.AssistantThinking{T.ThinkingContent{thinking ++ delta, signature, redacted}}
    case other: other

def contentLength(-G: Data, message: Message(G)) -> Nat: List.length(&2, Content(), T.assistantContent(V.Value, G, message))

def lastIndex(-G: Data, message: Message(G)) -> F64: F.fromNat(contentLength(G, message) - 1n)

def deltaEvent(-G: Data, kind: BlockKind, +delta: String, +message: Message(G)) -> Event(G):
  match kind:
    case TextKind{}: T.TextDelta{lastIndex(G, message), delta, message}
    case ThinkingKind{}: T.ThinkingDelta{lastIndex(G, message), delta, message}

# A text or thinking delta: open a block of that kind if the open block is not
# one (finishing it first), then append the delta.
def deltaInOpen(-G: Data, state: State<G>, +kind: BlockKind, +delta: String) -> Step<G>:
  match state:
    case State{output, current, tools}:
      +message = withContent(G, output, content => lastUpdated(content, block => appendText(block, delta)))
      Step{State{message, Some{kind}, tools}, deltaEvent(G, kind, delta, message) <> Nil{}}

def appended(content: List<&2, Content()>, block: Content()) -> List<&2, Content()>: List.append(&2, Content(), content, block <> Nil{})

def blockAt(content: List<&2, Content()>, +index: Nat) -> Maybe<&2, Content()>:
  match content index:
    case Nil{} _: None{}
    case head <> _ 0n: Some{head}
    case _ <> rest 1n+previous: blockAt(rest, previous)

def blockText(block: Maybe<&2, Content()>) -> String:
  match block:
    case Some{T.AssistantText{T.TextContent{text, _}}}: text
    case Some{T.AssistantThinking{T.ThinkingContent{thinking, _, _}}}: thinking
    case _: ""

def lastText(-G: Data, +message: Message(G)) -> String:
  blockText(blockAt(T.assistantContent(V.Value, G, message), contentLength(G, message) - 1n))

# upstream finishCurrentBlock: text_end or thinking_end for the open block.
def finished(-G: Data, +message: Message(G), current: Maybe<&2, BlockKind>) -> List<&2, Event(G)>:
  match current:
    case None{}: Nil{}
    case Some{TextKind{}}: T.TextEnd{lastIndex(G, message), lastText(G, message), message} <> Nil{}
    case Some{ThinkingKind{}}: T.ThinkingEnd{lastIndex(G, message), lastText(G, message), message} <> Nil{}

def emptyBlock(kind: BlockKind) -> Content():
  match kind:
    case TextKind{}: T.AssistantText{T.TextContent{"", None{}}}
    case ThinkingKind{}: T.AssistantThinking{T.ThinkingContent{"", None{}, None{}}}

def startEvent(-G: Data, kind: BlockKind, +message: Message(G)) -> Event(G):
  match kind:
    case TextKind{}: T.TextStart{lastIndex(G, message), message}
    case ThinkingKind{}: T.ThinkingStart{lastIndex(G, message), message}

def opened(-G: Data, state: State<G>, +kind: BlockKind, +delta: String) -> Step<G>:
  match state:
    case State{+output, current, tools}:
      +begun = withContent(G, output, content => appended(content, emptyBlock(kind)))
      withEvents(G, deltaInOpen(G, State{begun, Some{kind}, tools}, kind, delta), List.append(&2, Event(G), finished(G, output, current), startEvent(G, kind, begun) <> Nil{}))

def currentOf(-G: Data, state: State<G>) -> Maybe<&2, BlockKind>:
  match state:
    case State{_, current, _}: current

def blockDelta(-G: Data, +state: State<G>, +kind: BlockKind, +delta: String) -> Step<G>:
  Bool.pick(Step<G>, sameKind(currentOf(G, state), kind), deltaInOpen(G, state, kind, delta), opened(G, state, kind, delta))

def nonemptyText(value: Maybe<&2, V.Value>, rest: List<&2, String>) -> List<&2, String>:
  match value:
    case Some{V.Text{SCon{c, cs}}}: SCon{c, cs} <> rest
    case _: rest

# Content items: a string (text), or a `thinking` or `text` chunk.
def thinkingTexts(parts: List<&2, V.Value>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case V.ObjectValue{+fields} <> rest:
      +tail = thinkingTexts(rest)
      nonemptyText(R.get(V.Value, fields, "text"), tail)
    case _ <> rest: thinkingTexts(rest)

def thinkingParts(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{parts}}: parts
    case _: Nil{}

def textOf(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case _: ""

def thinkingItem(-G: Data, state: State<G>, delta: String) -> Step<G>:
  match delta:
    case SNil{}: Step{state, Nil{}}
    case SCon{c, cs}: blockDelta(G, state, ThinkingKind{}, SCon{c, cs})

def objectItem(-G: Data, state: State<G>, +fields: R.Record<V.Value>, kind: Maybe<&2, V.Value>) -> Step<G>:
  match kind:
    case Some{V.Text{"thinking"}}: thinkingItem(G, state, Unicode.sanitizeSurrogates(String.join(thinkingTexts(thinkingParts(R.get(V.Value, fields, "thinking"))), "")))
    case Some{V.Text{"text"}}: blockDelta(G, state, TextKind{}, Unicode.sanitizeSurrogates(textOf(R.get(V.Value, fields, "text"))))
    case _: Step{state, Nil{}}

def contentItem(-G: Data, state: State<G>, item: V.Value) -> Step<G>:
  match item:
    case V.Text{text}: blockDelta(G, state, TextKind{}, Unicode.sanitizeSurrogates(text))
    case V.ObjectValue{+fields}: objectItem(G, state, fields, R.get(V.Value, fields, "type"))
    case _: Step{state, Nil{}}

def contentItems(-G: Data, items: List<&2, V.Value>, state: State<G>) -> Step<G>:
  match items:
    case Nil{}: Step{state, Nil{}}
    case item <> rest: then(G, contentItem(G, state, item), next => contentItems(G, rest, next))

# upstream: an open text or thinking block is finished before any tool call.
def closedBlock(-G: Data, state: State<G>) -> Step<G>:
  match state:
    case State{+output, current, tools}: Step{State{output, None{}, tools}, finished(G, output, current)}

def sameKey(left: ToolKey, right: ToolKey) -> Bool:
  match left right:
    case IndexKey{a} IndexKey{b}: F.isEqual(F.compare(a, b))
    case IdKey{a} IdKey{b}: String.eq(a, b)
    case _ _: False{}

def entryKey(entry: ToolEntry) -> ToolKey:
  match entry:
    case ToolEntry{key, _, _}: key

def foundEntry(entry: ToolEntry, found: Bool, later: Maybe<&2, ToolEntry>) -> Maybe<&2, ToolEntry>:
  match found:
    case True{}: Some{entry}
    case False{}: later

def entryFor(entries: List<&2, ToolEntry>, +key: ToolKey) -> Maybe<&2, ToolEntry>:
  match entries:
    case Nil{}: None{}
    case +entry <> rest: foundEntry(entry, sameKey(entryKey(entry), key), entryFor(rest, key))

def stringOr(value: Maybe<&2, V.Value>, fallback: String) -> String:
  match value:
    case Some{V.Text{text}}: text
    case _: fallback

def numberField(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{number}}: Some{number}
    case _: None{}

# `typeof arguments === "string" ? arguments : JSON.stringify(arguments || {})`.
def argumentsDelta(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case Some{V.Null{}}: "{}"
    case Some{V.Boolean{False{}}}: "{}"
    case Some{other}: Maybe.default(&2, String, JsonWire.stringify(SchemaJson.toJson(other)), "{}")
    case None{}: "{}"

def fallbackCallId(index: Maybe<&2, F64>) -> String:
  deriveMistralToolCallId("toolcall:" ++ Maybe.default(&2, String, F.toDecimal(Maybe.default(&2, F64, index, zero())), "0"), 0n)

def callIdOf(value: Maybe<&2, V.Value>, index: Maybe<&2, F64>) -> String:
  match value:
    case Some{V.Text{SCon{+c, +cs}}}: Bool.pick(String, String.eq(SCon{c, cs}, "null"), fallbackCallId(index), SCon{c, cs})
    case _: fallbackCallId(index)

def keyOf(index: Maybe<&2, F64>, +callId: String) -> ToolKey:
  match index:
    case Some{value}: IndexKey{value}
    case None{}: IdKey{callId}

def updatedAt(content: List<&2, Content()>, +index: Nat, change: Content() -> Content()) -> List<&2, Content()>:
  match content index:
    case Nil{} _: Nil{}
    case head <> rest 0n: change(head) <> rest
    case head <> rest 1n+previous: head <> updatedAt(rest, previous, change)

def replacedEntry(entries: List<&2, ToolEntry>, +updated: ToolEntry) -> List<&2, ToolEntry>:
  match entries:
    case Nil{}: Nil{}
    case +entry <> rest: Bool.pick(ToolEntry, sameKey(entryKey(entry), entryKey(updated)), updated, entry) <> replacedEntry(rest, updated)

def withArguments(block: Content(), +arguments: V.Value) -> Content():
  match block:
    case T.AssistantToolCall{T.ToolCall{id, name, _, signature, namespace}}: T.AssistantToolCall{T.ToolCall{id, name, arguments, signature, namespace}}
    case other: other

# One streamed tool call: a new tool block for an unseen key, then the
# argument delta appended to its scratch buffer and parsed.
def toolDeltaAt(-G: Data, state: State<G>, entry: ToolEntry, +delta: String) -> Step<G>:
  match state entry:
    case State{output, current, tools} ToolEntry{key, +index, previous}:
      +accumulated = previous ++ delta
      +arguments = JsonRepair.parseStreamingJson(Some{accumulated})
      +message = withContent(G, output, content => updatedAt(content, index, block => withArguments(block, arguments)))
      Step{State{message, current, replacedEntry(tools, ToolEntry{key, index, accumulated})}, T.ToolcallDelta{F.fromNat(index), delta, message} <> Nil{}}

def newTool(-G: Data, state: State<G>, +key: ToolKey, +callId: String, +name: String, +delta: String) -> Step<G>:
  match state:
    case State{+output, current, tools}:
      +index = contentLength(G, output)
      +message = withContent(G, output, content => appended(content, T.AssistantToolCall{T.ToolCall{callId, name, V.ObjectValue{R.new(V.Value)}, None{}, None{}}}))
      +entry = {ToolEntry{key, index, ""} : ToolEntry}
      withEvents(G, toolDeltaAt(G, State{message, current, List.append(&2, ToolEntry, tools, entry <> Nil{})}, entry, delta), T.ToolcallStart{F.fromNat(index), message} <> Nil{})

def toolFor(-G: Data, +state: State<G>, +key: ToolKey, +callId: String, +name: String, +delta: String, existing: Maybe<&2, ToolEntry>) -> Step<G>:
  match existing:
    case Some{entry}: toolDeltaAt(G, state, entry, delta)
    case None{}: newTool(G, state, key, callId, name, delta)

def toolsOf(-G: Data, state: State<G>) -> List<&2, ToolEntry>:
  match state:
    case State{_, _, tools}: tools

def toolCallStep(-G: Data, +state: State<G>, +fields: R.Record<V.Value>) -> Step<G>:
  +index = numberField(R.get(V.Value, fields, "index"))
  +callId = callIdOf(R.get(V.Value, fields, "id"), index)
  +function = objectFields(R.get(V.Value, fields, "function"))
  +key = keyOf(index, callId)
  toolFor(G, state, key, callId, stringOr(R.get(V.Value, function, "name"), ""), argumentsDelta(R.get(V.Value, function, "arguments")), entryFor(toolsOf(G, state), key))

def toolCallItem(-G: Data, state: State<G>, call: V.Value) -> Step<G>:
  match call:
    case V.ObjectValue{fields}: then(G, closedBlock(G, state), next => toolCallStep(G, next, fields))
    case _: Step{state, Nil{}}

def toolCallItems(-G: Data, calls: List<&2, V.Value>, state: State<G>) -> Step<G>:
  match calls:
    case Nil{}: Step{state, Nil{}}
    case call <> rest: then(G, toolCallItem(G, state, call), next => toolCallItems(G, rest, next))

def contentList(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.Text{text}}: V.Text{text} <> Nil{}
    case Some{V.ArrayValue{items}}: items
    case _: Nil{}

def callList(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{items}}: items
    case _: Nil{}

def deltaStep(-G: Data, state: State<G>, +delta: R.Record<V.Value>) -> Step<G>:
  then(G, contentItems(G, contentList(R.get(V.Value, delta, "content")), state), next => toolCallItems(G, callList(R.get(V.Value, delta, "tool_calls")), next))

def choiceStep(-G: Data, state: State<G>, choice: Maybe<&2, R.Record<V.Value>>) -> Step<G>:
  match choice:
    case None{}: Step{state, Nil{}}
    case Some{+fields}: deltaStep(G, finishReason(G, state, R.get(V.Value, fields, "finish_reason")), objectFields(R.get(V.Value, fields, "delta")))

# upstream consumeChatStream's loop body for one completion chunk.
def chunkStep(-G: Data, +model: T.Model<J()>, state: State<G>, +chunk: R.Record<V.Value>) -> Step<G>:
  choiceStep(G, usageStep(G, model, mapOutput(G, state, message => withResponseId(G, message, R.get(V.Value, chunk, "id"))), R.get(V.Value, chunk, "usage")), firstChoice(R.get(V.Value, chunk, "choices")))

def withState(-G: Data, reading: Reading<G>, state: State<G>) -> Reading<G>:
  match reading:
    case Reading{decoder, buffer, _}: Reading{decoder, buffer, state}

def stepped(-G: Data, reading: Reading<G>, frames: List<&2, String>, phase: Phase, step: Step<G>) -> List<&2, Event(G)> & Loop<G>:
  match step:
    case Step{state, events}: (events, Frames{withState(G, reading, state), frames, phase})

def framesAfter(-G: Data, +model: T.Model<J()>, +reading: Reading<G>, frames: List<&2, String>, phase: Phase, parsed: ParsedEvent) -> List<&2, Event(G)> & Loop<G>:
  match parsed:
    case NoEvent{}: (Nil{}, Frames{reading, frames, phase})
    case StreamDone{}: (Nil{}, Stop{readingState(G, reading), Consumed{}})
    case InvalidEvent{message}: (Nil{}, Stop{readingState(G, reading), Invalid{message}})
    case ChunkEvent{chunk}: stepped(G, reading, frames, phase, chunkStep(G, model, readingState(G, reading), chunk))

def publish(-G: Data, +events: EventStream(G), values: List<&2, Event(G)>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case event <> rest:
      do IO<Unit>:
        push(G, events, event)
        publish(G, events, rest)

def published(-G: Data, +events: EventStream(G), pair: List<&2, Event(G)> & Loop<G>) -> IO(Loop<G>):
  match pair:
    case (values, next):
      do IO<Loop<G>>:
        publish(G, events, values)
        return next

def abortedStop(-G: Data, +reading: Reading<G>, aborted: Bool) -> Loop<G>:
  Bool.pick(Loop<G>, aborted, Stop{readingState(G, reading), ReadFailed{}}, Pull{reading})

# upstream readMistralEvents with consumeChatStream: an aborted signal ends
# reading before and after every read.
@unsafe def drive(~Reason: Data, ~G: Data, +events: EventStream(G), +source: Http.Source(Reason), +signal: Fetch.Signal(Reason), +model: T.Model<J()>, checked: Bool, state: Loop<G>) -> IO(State<G> & Outcome):
  match state checked:
    case Stop{result, outcome} _: IO.pure(State<G> & Outcome, (result, outcome))
    case Pull{reading} False{}:
      do IO<State<G> & Outcome>:
        aborted : Bool <- Abort.aborted(Deadline.Cause<Reason>, signal)
        drive(~Reason, ~G, events, source, signal, model, True{}, abortedStop(G, reading, aborted))
    case Pull{+reading} True{}:
      do IO<State<G> & Outcome>:
        result : Result<&2, &2, Http.ReadError(Reason), Maybe<&2, List<&2, U32>>> <- Http.read(~Reason, source)
        aborted : Bool <- Abort.aborted(Deadline.Cause<Reason>, signal)
        drive(~Reason, ~G, events, source, signal, model, False{}, Bool.pick(Loop<G>, aborted, Stop{readingState(G, reading), ReadFailed{}}, pulled(Reason, G, reading, result)))
    case Frames{reading, Nil{}, phase} _: drive(~Reason, ~G, events, source, signal, model, False{}, exhausted(G, reading, phase))
    case Frames{reading, frame <> rest, phase} _:
      do IO<State<G> & Outcome>:
        next : Loop<G> <- published(G, events, framesAfter(G, model, reading, rest, phase, parseMistralEvent(frame)))
        drive(~Reason, ~G, events, source, signal, model, False{}, next)

def prependEvents(-G: Data, events: List<&2, Event(G)>, pair: Message(G) & List<&2, Event(G)>) -> Message(G) & List<&2, Event(G)>:
  match pair:
    case (message, rest): (message, List.append(&2, Event(G), events, rest))

def callOf(block: Maybe<&2, Content()>) -> Maybe<&2, T.ToolCall<V.Value>>:
  match block:
    case Some{T.AssistantToolCall{call}}: Some{call}
    case _: None{}

def toolCallAt(-G: Data, +message: Message(G), +index: Nat) -> Maybe<&2, T.ToolCall<V.Value>>:
  callOf(blockAt(T.assistantContent(V.Value, G, message), index))

def toolEnd(-G: Data, +message: Message(G), +index: Nat, call: Maybe<&2, T.ToolCall<V.Value>>) -> List<&2, Event(G)>:
  match call:
    case Some{value}: T.ToolcallEnd{F.fromNat(index), value, message} <> Nil{}
    case None{}: Nil{}

def endedTools(-G: Data, entries: List<&2, ToolEntry>, output: Message(G)) -> Message(G) & List<&2, Event(G)>:
  match entries:
    case Nil{}: (output, Nil{})
    case ToolEntry{_, +index, partial} <> rest:
      +arguments = JsonRepair.parseStreamingJson(Some{partial})
      +message = withContent(G, output, content => updatedAt(content, index, block => withArguments(block, arguments)))
      prependEvents(G, toolEnd(G, message, index, toolCallAt(G, message, index)), endedTools(G, rest, message))

# After the last chunk: the open block's end, then each tool block's final
# arguments and toolcall_end in insertion order.
def finalized(-G: Data, state: State<G>) -> Message(G) & List<&2, Event(G)>:
  match state:
    case State{+output, current, tools}: prependEvents(G, finished(G, output, current), endedTools(G, tools, output))

def doneReason(stop: T.StopReason) -> Maybe<&2, T.DoneReason>:
  match stop:
    case T.Stop{}: Some{T.DoneStop{}}
    case T.Length{}: Some{T.DoneLength{}}
    case T.ToolUse{}: Some{T.DoneToolUse{}}
    case T.Deferred{}: Some{T.DoneDeferred{}}
    case _: None{}

def nonemptyOr(value: Maybe<&2, String>) -> String:
  match value:
    case Some{SCon{c, cs}}: SCon{c, cs}
    case _: "An unknown error occurred"

def errorOrUnknown(-G: Data, message: Message(G)) -> String: nonemptyOr(T.assistantErrorMessage(V.Value, G, message))

def stopped(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +output: Message(G), stop: T.StopReason) -> IO(Unit):
  match stop:
    case T.Pending{}: failed(~Reason, ~G, events, parent, output, "Mistral stream ended without a finish reason")
    case T.Aborted{}: failed(~Reason, ~G, events, parent, output, errorOrUnknown(G, output))
    case T.Error{}: failed(~Reason, ~G, events, parent, output, errorOrUnknown(G, output))
    case other: push(G, events, T.StreamDone{Maybe.default(&2, T.DoneReason, doneReason(other), T.DoneStop{}), output})

def stopOf(-G: Data, message: Message(G)) -> T.StopReason: T.assistantStopReason(V.Value, G, message)

# After the stream: an aborted signal, a missing finish reason or an error
# stop reason are thrown; otherwise the stream is done.
def completed(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +output: Message(G), aborted: Bool) -> IO(Unit):
  match aborted:
    case True{}: failed(~Reason, ~G, events, parent, output, "Request was aborted")
    case False{}: stopped(~Reason, ~G, events, parent, output, stopOf(G, output))

def finalizedStream(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, pair: Message(G) & List<&2, Event(G)>) -> IO(Unit):
  match pair:
    case (+output, values):
      do IO<Unit>:
        publish(G, events, values)
        aborted : Bool <- Abort.aborted(Reason, parent)
        completed(~Reason, ~G, events, parent, output, aborted)

def settled(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +signal: Fetch.Signal(Reason), pair: State<G> & Outcome) -> IO(Unit):
  match pair:
    case (state, Consumed{}): finalizedStream(~Reason, ~G, events, parent, finalized(G, state))
    case (state, ReadFailed{}): classified(~Reason, ~G, events, parent, signal, outputOf(G, state))
    case (state, Invalid{message}): failed(~Reason, ~G, events, parent, outputOf(G, state), message)

def streamed(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +signal: Fetch.Signal(Reason), +model: T.Model<J()>, +state: State<G>, pair: Http.Owner(Reason) & Http.Source(Reason)) -> IO(Unit):
  match pair:
    case (owner, source):
      do IO<Unit>:
        push(G, events, T.Start{outputOf(G, state)})
        result : State<G> & Outcome <- drive(~Reason, ~G, events, source, signal, model, False{}, Pull{Reading{Utf8.create(), "", state}})
        Http.release(~Reason, owner)
        settled(~Reason, ~G, events, parent, signal, result)

def releasedPair(~Reason: Data, pair: Http.Owner(Reason) & Http.Source(Reason)) -> IO(Unit):
  match pair:
    case (owner, _): Http.release(~Reason, owner)

def discarded(~Reason: Data, body: Http.Body(Reason)) -> IO(Unit):
  do IO<Unit>:
    pair : Http.Owner(Reason) & Http.Source(Reason) <- Http.reader(~Reason, body)
    releasedPair(~Reason, pair)

def bodyChecked(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +signal: Fetch.Signal(Reason), +model: T.Model<J()>, +state: State<G>, present: Bool, body: Http.Body(Reason)) -> IO(Unit):
  match present:
    case True{}:
      do IO<Unit>:
        pair : Http.Owner(Reason) & Http.Source(Reason) <- Http.reader(~Reason, body)
        streamed(~Reason, ~G, events, parent, signal, model, state, pair)
    case False{}:
      do IO<Unit>:
        discarded(~Reason, body)
        failed(~Reason, ~G, events, parent, outputOf(G, state), "Mistral response has no body")

def statusChecked(~Reason: Data, ~G: Data, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +signal: Fetch.Signal(Reason), +model: T.Model<J()>, +state: State<G>, +metadata: Response.Metadata, body: Http.Body(Reason), ok: Bool) -> IO(Unit):
  match ok:
    case True{}: bodyChecked(~Reason, ~G, events, parent, signal, model, state, Response.bodyPresent(metadata), body)
    case False{}:
      do IO<Unit>:
        text : Result<&2, &2, Response.TextError<Http.ExchangeError(Reason)>, String> <- Http.responseText(~Reason, 1048576n, body)
        failedStatus(~Reason, ~G, events, parent, signal, outputOf(G, state), metadata, text)

def hookedResponse(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +signal: Fetch.Signal(Reason), +model: T.Model<J()>, +state: State<G>, +metadata: Response.Metadata, body: Http.Body(Reason), result: Result<&2, &2, E, Unit>) -> IO(Unit):
  match result:
    case Fail{cause}:
      do IO<Unit>:
        discarded(~Reason, body)
        failed(~Reason, ~G, events, parent, outputOf(G, state), render(cause))
    case Done{_}: statusChecked(~Reason, ~G, events, parent, signal, model, state, metadata, body, Response.ok(metadata))

def withResponseHook(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +signal: Fetch.Signal(Reason), +model: T.Model<J()>, +state: State<G>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, +metadata: Response.Metadata, body: Http.Body(Reason)) -> IO(Unit):
  match hook:
    case None{}: statusChecked(~Reason, ~G, events, parent, signal, model, state, metadata, body, Response.ok(metadata))
    case Some{callback}:
      do IO<Unit>:
        result : Result<&2, &2, E, Unit> <- C.call(T.ResponseInput<T.Model<J()>>, Result<&2, &2, E, Unit>, callback, T.ResponseInput{Http.providerResponse(metadata), model})
        hookedResponse(~Reason, ~E, ~G, ~render, events, parent, signal, model, state, metadata, body, result)

def transportFailure(-Reason: Data, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> String:
  match reason:
    case None{}: "fetch failed"
    case other: readFailure(Reason, other)

def responded(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +signal: Fetch.Signal(Reason), +model: T.Model<J()>, +state: State<G>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, response: Fetch.Result_(Reason)) -> IO(Unit):
  match response:
    case Fail{_}:
      do IO<Unit>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, signal)
        failed(~Reason, ~G, events, parent, outputOf(G, state), transportFailure(Reason, reason))
    case Done{Response.Response{metadata, body}}: withResponseHook(~Reason, ~E, ~G, ~render, events, parent, signal, model, state, hook, metadata, body)

def exchanged(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, fetch: Fetch.Fetch(Reason), request: Http.Request, pair: Deadline.Scope<Reason> & Fetch.Signal(Reason)) -> IO(Unit):
  match pair:
    case (scope, +signal):
      do IO<Unit>:
        response : Fetch.Result_(Reason) <- Http.post(~Reason, fetch, signal, request)
        responded(~Reason, ~E, ~G, ~render, events, parent, signal, model, state, hook, response)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Unit{}

# upstream requestMistralStream: the request timeout covers the whole
# exchange, headers and body (AbortSignal.any with the caller's signal).
def exchange(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +state: State<G>, setup: Setup<Reason, E>, body: Maybe<&2, String>) -> IO(Unit):
  match setup body:
    case Setup{model, _, _, _, _, _} None{}: failed(~Reason, ~G, events, parent, outputOf(G, state), "Could not serialize the Mistral payload")
    case Setup{model, Fail{_}, _, _, _, _} _: failed(~Reason, ~G, events, parent, outputOf(G, state), "Invalid header")
    case Setup{model, _, _, _, Fail{_}, _} _: failed(~Reason, ~G, events, parent, outputOf(G, state), "Invalid URL")
    case Setup{model, Done{headers}, hook, fetch, Done{url}, timeout} Some{text}:
      do IO<Unit>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, timeout, parent)
        exchanged(~Reason, ~E, ~G, ~render, events, parent, model, state, hook, fetch, Http.Request{url, headers, text}, Deadline.borrow(Reason, scope))

def payloaded(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +state: State<G>, setup: Setup<Reason, E>, original: J(), result: Result<&2, &2, E, Maybe<&2, J()>>) -> IO(Unit):
  match result:
    case Fail{cause}: failed(~Reason, ~G, events, parent, outputOf(G, state), render(cause))
    case Done{replacement}: exchange(~Reason, ~E, ~G, ~render, events, parent, state, setup, JsonWire.stringify(toMistralWirePayload(Maybe.default(&2, J(), replacement, original))))

def setupModel(-Reason: Data, -E: Data, setup: Setup<Reason, E>) -> T.Model<J()>:
  match setup:
    case Setup{model, _, _, _, _, _}: model

def withPayloadHook(~Reason: Data, ~E: Data, ~G: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +state: State<G>, +setup: Setup<Reason, E>, +payload: J(), hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, E)>) -> IO(Unit):
  match hook:
    case None{}: payloaded(~Reason, ~E, ~G, ~render, events, parent, state, setup, payload, Done{None{}})
    case Some{callback}:
      do IO<Unit>:
        result : Result<&2, &2, E, Maybe<&2, J()>> <- C.call(T.PayloadInput<J(), T.Model<J()>>, Result<&2, &2, E, Maybe<&2, J()>>, callback, T.PayloadInput{payload, setupModel(Reason, E, setup)})
        payloaded(~Reason, ~E, ~G, ~render, events, parent, state, setup, payload, result)

def convertedPayload(~Reason: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, request: Request<Reason, E>, messages: List<&2, J()>, tools: Result<&2, &2, Sampling.Error, List<&2, J()>>) -> IO(Unit):
  match tools request:
    case Fail{cause} _: failed(~Reason, ~G, events, parent, outputOf(G, state), Sampling.errorMessage(cause))
    case Done{functions} Request{key, agent, headers, onPayload, onResponse, fetch, urlContext, timeout, temperature, maxTokens, choice, promptMode, effort, +cacheKey}:
      withPayloadHook(~Reason, ~E, ~G, ~render, events, parent, state, Setup{model, buildMistralHeaders(agent, key, modelHeaders(model), headers, cacheKey), onResponse, fetch, URL.parse(urlContext, requestUrl(model)), timeout}, buildChatPayload(model, messages, functions, temperature, maxTokens, choice, promptMode, effort, cacheKey), onPayload)

def transformed(~Reason: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, request: Request<Reason, E>, tools: List<&2, T.Tool<V.Value>>, result: Result<&2, &2, Sampling.Error, List<&2, T.Message<V.Value, V.Value, G, D>>>) -> IO(Unit):
  match result:
    case Fail{cause}: failed(~Reason, ~G, events, parent, outputOf(G, state), Sampling.errorMessage(cause))
    case Done{messages}: convertedPayload(~Reason, ~E, ~G, ~D, ~render, events, parent, model, state, request, toChatMessages(G, D, messages, Transform.imageCapability(J(), model), True{}), toFunctionTools(tools))

# Tool-call ids are normalized for Mistral while the transcript is replayed.
def prepared(~Reason: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, request: Request<Reason, E>, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> IO(Unit):
  match context:
    case T.TranscriptContext{+messages}:
      do IO<Unit>:
        agent : String <- IO.try(String, UserAgent.get())
        +maps : Ref.Ref<IdMaps> <- Ref.new(IdMaps, IdMaps{R.new(String), R.new(String)})
        +normalizer : Transform.Normalizer(V.Value, G, J(), Sampling.Error) <- C.create(~Ref.Ref<IdMaps>, ~Transform.NormalizeToolCallIdInput<V.Value, G, J()>, ~Result<&2, &2, Sampling.Error, String>, ~(normalizeBody(V.Value, G, J())), maps)
        result : Result<&2, &2, Sampling.Error, List<&2, T.Message<V.Value, V.Value, G, D>>> <- Transform.transformMessages(~V.Value, ~V.Value, ~G, ~D, ~J(), ~Sampling.Error, messages, model, Some{normalizer})
        C.dispose(Transform.NormalizeToolCallIdInput<V.Value, G, J()>, Result<&2, &2, Sampling.Error, String>, normalizer)
        previous : IdMaps <- Ref.dispose(IdMaps, maps)
        transformed(~Reason, ~E, ~G, ~D, ~render, events, parent, model, state, withRequest(Reason, E, request, agent), Transcript.getCurrentTools(V.Value, V.Value, G, D, messages), result)

def keyed(~Reason: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +state: State<G>, key: Maybe<&2, String>, request: String -> Request<Reason, E>, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> IO(Unit):
  match key:
    case None{}: failed(~Reason, ~G, events, parent, outputOf(G, state), missingKey(model))
    case Some{SNil{}}: failed(~Reason, ~G, events, parent, outputOf(G, state), missingKey(model))
    case Some{value}: prepared(~Reason, ~E, ~G, ~D, ~render, events, parent, model, state, request(value), context)

def started(~Reason: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, key: Maybe<&2, String>, request: String -> Request<Reason, E>, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> IO(Unit):
  do IO<Unit>:
    timestamp : F64 <- Date.now()
    keyed(~Reason, ~E, ~G, ~D, ~render, events, parent, model, createState(G, model, timestamp), key, request, context)

# upstream stream. The caller supplies the default fetch (upstream
# globalThis.fetch) and the request's abort signal; events go to `events`,
# which the terminal done/error event completes.
def stream(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options(Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), E)) -> IO(Unit):
  match options:
    case MistralOptions{T.StreamOptions{_, _, key, custom, _, onPayload, onResponse, headers, timeoutMs, _, _, temperature, _, maxTokens, _, retention, sessionId, _, _}, choice, promptMode, effort}:
      +resolved = Transcript.resolveTranscript(V.Value, V.Value, G, D, context, supportsMidConvoSystemMessages(model))
      started(~Reason, ~E, ~G, ~D, ~render, events, parent, model, key, value => Request{value, "", headers, onPayload, onResponse, Maybe.default(&2, Fetch.Fetch(Reason), custom, fetch), urlContext, requestTimeout(timeoutMs), temperature, maxTokens, choice, promptMode, effort, promptCacheKey(retention, sessionId)}, resolved)

# Tools
# -----

# Payload
# -------

# Wire format
# -----------

# Headers and URL
# ---------------

# Errors
# ------

# SSE framing
# -----------

# Stream fold
# -----------

# Tool calls
# ----------

# Usage and stop reasons
# ----------------------

# One chunk
# ---------

# Reading the stream
# ------------------

# Streaming
# ---------

def simpleStarted(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Result<&2, &2, String, Options(Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), E)>) -> IO(Result<&2, &2, String, Unit>):
  match options:
    case Fail{message}: IO.pure(Result<&2, &2, String, Unit>, Fail{message})
    case Done{selected}:
      do IO<Result<&2, &2, String, Unit>>:
        stream(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, events, fetch, urlContext, parent, model, context, selected)
        return Done{Unit{}}

# upstream streamSimple; its missing-key error is thrown before streaming.
def streamSimple(~Reason: Data, ~Telemetry: Data, ~E: Data, ~G: Data, ~D: Data, ~render: E -> String, +events: EventStream(G), fetch: Fetch.Fetch(Reason), urlContext: URL.Context, +parent: Abort.AbortSignal<Reason>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Maybe<&2, T.SimpleStreamOptions<J(), Abort.AbortSignal<Reason>, Telemetry, Fetch.Fetch(Reason), E>>) -> IO(Result<&2, &2, String, Unit>):
  simpleStarted(~Reason, ~Telemetry, ~E, ~G, ~D, ~render, events, fetch, urlContext, parent, model, context, streamSimpleOptions(~G, ~D, ~Abort.AbortSignal<Reason>, ~Telemetry, ~Fetch.Fetch(Reason), ~E, model, context, options))

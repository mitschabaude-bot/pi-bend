import Base
import ../types.bend as T
import ../utils/event-stream.bend as Events
import ../utils/json.bend as Wire
import ../utils/message-json.bend as MessageJson
import ../utils/schema-json.bend as Schema
import ../utils/text.bend as Text
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/random.bend as Random
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/timer.bend as Timer
import ../../../runtime/src/utf16.bend as Utf16
import ../../../runtime/src/u64.bend as W

# pi-mono packages/ai/src/providers/faux.ts: a scripted provider for tests.
# Upstream's closures over module state become one FauxCore record whose
# mutable parts (queued responses, state counters, the prompt cache) are Refs,
# so a core is shared by every stream it serves. Streams publish immutable
# snapshots as partials; upstream's snapshots share the block objects it later
# mutates, which is incidental aliasing and not reproduced.
#
# Not ported: deferred responses (fetchDeferred/cancelDeferred and the
# `deferred` stream option), and registration in a process-wide api registry
# (registerFauxProvider/unregister): the Bend ai package dispatches by api in
# the agent runtime, so callers use the core's stream directly.
def J() -> Data: T.JsonValue

def DEFAULT_API() -> String: "faux"
def DEFAULT_PROVIDER() -> String: "faux"
def DEFAULT_MODEL_ID() -> String: "faux-1"
def DEFAULT_MODEL_NAME() -> String: "Faux Model"
def DEFAULT_BASE_URL() -> String: "http://localhost:0"
def DEFAULT_MIN_TOKEN_SIZE() -> Nat: 3n
def DEFAULT_MAX_TOKEN_SIZE() -> Nat: 5n

def zero() -> F64: F.fromU32(0)

def DEFAULT_USAGE() -> T.Usage: T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}

# Message helpers
# ---------------
def fauxText(text: String) -> T.AssistantContent<V.Value>: T.AssistantText{T.TextContent{text, None{}}}

def fauxThinking(thinking: String) -> T.AssistantContent<V.Value>: T.AssistantThinking{T.ThinkingContent{thinking, None{}, None{}}}

def fauxToolCallWithId(name: String, arguments: V.Value, id: String) -> T.AssistantContent<V.Value>:
  T.AssistantToolCall{T.ToolCall{id, name, arguments, None{}, None{}}}

def digitText(index: Nat) -> String: String.take(String.drop("0123456789abcdefghijklmnopqrstuvwxyz", index), 1n)

# Math.random().toString(36).slice(2): ten base-36 digits of a fraction.
def base36(count: Nat, value: F64) -> String:
  match count:
    case 0n: ""
    case 1n+rest:
      +scaled = F.multiply(value, F.fromU32(36))
      +digit = F64.floor(scaled)
      digitText(U32.to_nat(F64.to_u32(digit))) ++ base36(rest, F.subtract(scaled, digit))

def randomIdAt(+prefix: String, now: F64, fraction: F64) -> String:
  prefix ++ ":" ++ Maybe.default(&2, String, Wire.stringify(T.JsonNumber{now}), "0") ++ ":" ++ base36(10n, fraction)

def randomId(generator: Random.Generator, prefix: String) -> IO(String):
  do IO<String>:
    now : F64 <- Date.now()
    fraction : F64 <- Random.random(generator)
    return randomIdAt(prefix, now, fraction)

type FauxMessageOptions is Data:
  FauxMessageOptions{stopReason: Maybe<&2, T.StopReason>, errorMessage: Maybe<&2, String>, responseId: Maybe<&2, String>, timestamp: Maybe<&2, F64>}

def noOptions() -> FauxMessageOptions: FauxMessageOptions{None{}, None{}, None{}, None{}}

# upstream fauxAssistantMessage at a given current time.
def fauxAssistantMessageAt(-G: Data, content: List<&2, T.AssistantContent<V.Value>>, options: FauxMessageOptions, now: F64) -> T.AssistantMessage<V.Value, G>:
  match options:
    case FauxMessageOptions{stop, error, responseId, timestamp}:
      T.AssistantMessage{content, DEFAULT_API(), DEFAULT_PROVIDER(), DEFAULT_MODEL_ID(), None{}, responseId, None{}, None{}, DEFAULT_USAGE(), Maybe.default(&2, T.StopReason, stop, T.Stop{}), None{}, error, None{}, None{}, Maybe.default(&2, F64, timestamp, now)}

def fauxAssistantMessage(-G: Data, content: List<&2, T.AssistantContent<V.Value>>, options: FauxMessageOptions) -> IO(T.AssistantMessage<V.Value, G>):
  do IO<T.AssistantMessage<V.Value, G>>:
    now : F64 <- Date.now()
    return fauxAssistantMessageAt(G, content, options, now)

# Configuration
# -------------
type FauxModelDefinition is Data:
  FauxModelDefinition{id: String, name: Maybe<&2, String>, reasoning: Maybe<&2, Bool>, input: Maybe<&2, List<&2, T.ModelInput>>, inputLimits: Maybe<&2, T.ModelInputLimits>, cost: Maybe<&2, T.ModelCost>, contextWindow: Maybe<&2, F64>, maxTokens: Maybe<&2, F64>}

type FauxTokenSize is Data:
  FauxTokenSize{min: Maybe<&2, F64>, max: Maybe<&2, F64>}

type RegisterFauxProviderOptions is Data:
  RegisterFauxProviderOptions{api: Maybe<&2, String>, provider: Maybe<&2, String>, models: List<&2, FauxModelDefinition>, tokensPerSecond: Maybe<&2, F64>, tokenSize: Maybe<&2, FauxTokenSize>}

def defaultOptions() -> RegisterFauxProviderOptions: RegisterFauxProviderOptions{None{}, None{}, Nil{}, None{}, None{}}

type FauxProviderState is Data:
  FauxProviderState{callCount: Nat, deferredFetchCount: Nat, cancelledDeferred: List<&2, T.DeferredHandle>}

def Options(-E: Data) -> Data: T.SimpleStreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Unit, E>

def Context(-G: Data, -D: Data) -> Data: T.TranscriptContext<V.Value, V.Value, G, D>

type FactoryInput<-G: Data, -D: Data, -E: Data> is Data:
  FactoryInput{context: Context(G, D), options: Maybe<&2, Options(E)>, state: FauxProviderState, model: T.Model<J()>}

# A queued response: a message, or a factory whose failure is the thrown error.
type FauxResponseStep<-G: Data, -D: Data, -E: Data> is Data:
  FauxReply{message: T.AssistantMessage<V.Value, G>}
  FauxFactory{factory: C.Callback<FactoryInput<G, D, E>, Result<&2, &2, String, T.AssistantMessage<V.Value, G>>>}

type FauxCore<-G: Data, -D: Data, -E: Data> is Data:
  FauxCore{api: String, provider: String, models: List<&2, T.Model<J()>>, minTokenSize: Nat, maxTokenSize: Nat, tokensPerSecond: Maybe<&2, F64>, pending: Ref.Ref<List<&2, FauxResponseStep<G, D, E>>>, state: Ref.Ref<FauxProviderState>, promptCache: Ref.Ref<R.Record<String>>, random: Random.Generator}

def modelApi(+api: String) -> T.ModelApi: T.CustomModelApi{api}

def modelOf(+api: String, +provider: String, definition: FauxModelDefinition) -> T.Model<J()>:
  match definition:
    case FauxModelDefinition{+id, name, reasoning, input, limits, cost, window, maxTokens}:
      T.Model{id, Maybe.default(&2, String, name, id), modelApi(api), provider, DEFAULT_BASE_URL(), Maybe.default(&2, Bool, reasoning, False{}), None{}, Maybe.default(&2, List<&2, T.ModelInput>, input, T.InputText{} <> T.InputImage{} <> Nil{}), limits, Maybe.default(&2, T.ModelCost, cost, T.ModelCost{zero(), zero(), zero(), zero(), None{}}), None{}, Maybe.default(&2, F64, window, F.fromU32(128000)), Maybe.default(&2, F64, maxTokens, F.fromU32(16384)), None{}, None{}, None{}}

def defaultDefinition() -> FauxModelDefinition:
  FauxModelDefinition{DEFAULT_MODEL_ID(), Some{DEFAULT_MODEL_NAME()}, Some{False{}}, Some{T.InputText{} <> T.InputImage{} <> Nil{}}, None{}, Some{T.ModelCost{zero(), zero(), zero(), zero(), None{}}}, Some{F.fromU32(128000)}, Some{F.fromU32(16384)}}

def mappedModels(definitions: List<&2, FauxModelDefinition>, +api: String, +provider: String) -> List<&2, T.Model<J()>>:
  match definitions:
    case Nil{}: Nil{}
    case definition <> rest: modelOf(api, provider, definition) <> mappedModels(rest, api, provider)

def modelsOf(+api: String, +provider: String, definitions: List<&2, FauxModelDefinition>) -> List<&2, T.Model<J()>>:
  match definitions:
    case Nil{}: modelOf(api, provider, defaultDefinition()) <> Nil{}
    case some: mappedModels(some, api, provider)

def tokenNat(value: Maybe<&2, F64>, fallback: Nat) -> F64:
  match value:
    case Some{number}: number
    case None{}: F.fromU32(U32.from_nat(fallback))

def natOf(+value: F64) -> Nat: U32.to_nat(F64.to_u32(F64.floor(F.maximum(F.fromU32(0), value))))

# upstream: min = max(1, min(tokenSize.min ?? 3, tokenSize.max ?? 5));
# max = max(min, tokenSize.max ?? 5).
def tokenSizes(size: Maybe<&2, FauxTokenSize>) -> Nat & Nat:
  match size:
    case None{}: (DEFAULT_MIN_TOKEN_SIZE(), DEFAULT_MAX_TOKEN_SIZE())
    case Some{FauxTokenSize{min, max}}:
      +upper = tokenNat(max, DEFAULT_MAX_TOKEN_SIZE())
      +lower = F.maximum(F.fromU32(1), F.minimum(tokenNat(min, DEFAULT_MIN_TOKEN_SIZE()), upper))
      (natOf(lower), natOf(F.maximum(lower, upper)))

def initialState() -> FauxProviderState: FauxProviderState{0n, 0n, Nil{}}

def coreWith(-G: Data, -D: Data, -E: Data, +api: String, +provider: String, models: List<&2, FauxModelDefinition>, tokensPerSecond: Maybe<&2, F64>, sizes: Nat & Nat, pending: Ref.Ref<List<&2, FauxResponseStep<G, D, E>>>, state: Ref.Ref<FauxProviderState>, cache: Ref.Ref<R.Record<String>>, random: Random.Generator) -> FauxCore<G, D, E>:
  match sizes:
    case (lower, upper): FauxCore{api, provider, modelsOf(api, provider, models), lower, upper, tokensPerSecond, pending, state, cache, random}

def seedOf(value: F64) -> W.U64:
  match value:
    case F64{high, low}: W.U64{high, low}

def apiOf(value: Maybe<&2, String>, generator: Random.Generator) -> IO(String):
  match value:
    case Some{api}: IO.pure(String, api)
    case None{}: randomId(generator, DEFAULT_API())

# upstream createFauxCore.
def createFauxCore(-G: Data, -D: Data, -E: Data, options: RegisterFauxProviderOptions) -> IO(FauxCore<G, D, E>):
  match options:
    case RegisterFauxProviderOptions{api, provider, models, tokensPerSecond, size}:
      do IO<FauxCore<G, D, E>>:
        seed : F64 <- Date.now()
        +random : Random.Generator <- Random.seeded(Random.mix(seedOf(seed)))
        +chosen : String <- apiOf(api, random)
        pending : Ref.Ref<List<&2, FauxResponseStep<G, D, E>>> <- Ref.new(List<&2, FauxResponseStep<G, D, E>>, Nil{})
        state : Ref.Ref<FauxProviderState> <- Ref.new(FauxProviderState, initialState())
        cache : Ref.Ref<R.Record<String>> <- Ref.new(R.Record<String>, R.new(String))
        return coreWith(G, D, E, chosen, Maybe.default(&2, String, provider, DEFAULT_PROVIDER()), models, tokensPerSecond, tokenSizes(size), pending, state, cache, random)

def coreModels(-G: Data, -D: Data, -E: Data, core: FauxCore<G, D, E>) -> List<&2, T.Model<J()>>:
  match core:
    case FauxCore{_, _, models, _, _, _, _, _, _, _}: models

def findModel(models: List<&2, T.Model<J()>>, +id: String) -> Maybe<&2, T.Model<J()>>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Maybe<&2, T.Model<J()>>, String.eq(T.modelId(model), id), Some{model}, findModel(rest, id))

# upstream getModel(): the first model; getModel(id): the model with that id.
def getModel(-G: Data, -D: Data, -E: Data, core: FauxCore<G, D, E>, id: Maybe<&2, String>) -> Maybe<&2, T.Model<J()>>:
  match id:
    case None{}: List.head(&2, T.Model<J()>, coreModels(G, D, E, core))
    case Some{wanted}: findModel(coreModels(G, D, E, core), wanted)

def setResponses(-G: Data, -D: Data, -E: Data, core: FauxCore<G, D, E>, responses: List<&2, FauxResponseStep<G, D, E>>) -> IO(Unit):
  match core:
    case FauxCore{_, _, _, _, _, _, pending, _, _, _}: Ref.write(List<&2, FauxResponseStep<G, D, E>>, pending, responses)

def appended(-G: Data, -D: Data, -E: Data, current: List<&2, FauxResponseStep<G, D, E>>, responses: List<&2, FauxResponseStep<G, D, E>>) -> List<&2, FauxResponseStep<G, D, E>> & Unit:
  (List.append(&2, FauxResponseStep<G, D, E>, current, responses), Unit{})

def appendResponses(-G: Data, -D: Data, -E: Data, core: FauxCore<G, D, E>, responses: List<&2, FauxResponseStep<G, D, E>>) -> IO(Unit):
  match core:
    case FauxCore{_, _, _, _, _, _, pending, _, _, _}: Ref.modify(List<&2, FauxResponseStep<G, D, E>>, Unit, pending, current => appended(G, D, E, current, responses))

def getPendingResponseCount(-G: Data, -D: Data, -E: Data, core: FauxCore<G, D, E>) -> IO(Nat):
  match core:
    case FauxCore{_, _, _, _, _, _, pending, _, _, _}:
      do IO<Nat>:
        current : List<&2, FauxResponseStep<G, D, E>> <- Ref.read(List<&2, FauxResponseStep<G, D, E>>, pending)
        return List.length(&2, FauxResponseStep<G, D, E>, current)

def getState(-G: Data, -D: Data, -E: Data, core: FauxCore<G, D, E>) -> IO(FauxProviderState):
  match core:
    case FauxCore{_, _, _, _, _, _, _, state, _, _}: Ref.read(FauxProviderState, state)

# Usage estimates
# ---------------
def ceilDiv4(count: Nat) -> Nat: Nat.div(count + 3n, 4n)

# upstream estimateTokens: ceil(text.length / 4) over UTF-16 code units.
def estimateTokens(text: String) -> Nat: ceilDiv4(Utf16.length(text))

def jsonText(value: V.Value) -> String: Maybe.default(&2, String, Wire.stringify(Schema.toJson(value)), "")

def imageText(image: T.ImageContent) -> String:
  match image:
    case T.ImageContent{data, mime}: "[image:" ++ mime ++ ":" ++ Nat.show(Utf16.length(data)) ++ "]"

def blockText(block: T.TextImageContent) -> String:
  match block:
    case T.TextImageText{T.TextContent{text, _}}: text
    case T.TextImageImage{image}: imageText(image)

def blockTexts(blocks: List<&2, T.TextImageContent>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case block <> rest: blockText(block) <> blockTexts(rest)

def assistantBlockText(block: T.AssistantContent<V.Value>) -> String:
  match block:
    case T.AssistantText{T.TextContent{text, _}}: text
    case T.AssistantThinking{T.ThinkingContent{thinking, _, _}}: thinking
    case T.AssistantToolCall{T.ToolCall{_, name, arguments, _, _}}: name ++ ":" ++ jsonText(arguments)

def assistantTexts(blocks: List<&2, T.AssistantContent<V.Value>>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case block <> rest: assistantBlockText(block) <> assistantTexts(rest)

def removedText(reference: T.ToolReference) -> String:
  match reference:
    case T.ToolReference{name}: "tool-:" ++ jsonText(V.ObjectValue{R.Record{R.Property{"name", V.Text{name}} <> Nil{}}})

def removedTexts(references: List<&2, T.ToolReference>) -> List<&2, String>:
  match references:
    case Nil{}: Nil{}
    case reference <> rest: removedText(reference) <> removedTexts(rest)

def addedText(tool: T.Tool<V.Value>) -> String: "tool+:" ++ jsonText(MessageJson.tool(tool))

def addedTexts(tools: List<&2, T.Tool<V.Value>>) -> List<&2, String>:
  match tools:
    case Nil{}: Nil{}
    case tool <> rest: addedText(tool) <> addedTexts(rest)

def contentToText(content: T.UserContent) -> String:
  match content:
    case T.UserText{text}: text
    case T.UserBlocks{blocks}: String.join(blockTexts(blocks), "\n")

def assistantContentToText(content: List<&2, T.AssistantContent<V.Value>>) -> String:
  String.join(assistantTexts(content), "\n")

def toolResultToText(-D: Data, message: T.ToolResultMessage<D>) -> String:
  match message:
    case T.ToolResultMessage{_, name, content, _, _, _, _}: String.join(name <> blockTexts(content), "\n")

def nonEmpty(parts: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case SNil{} <> rest: nonEmpty(rest)
    case part <> rest: part <> nonEmpty(rest)

def systemText(message: T.SystemMessage<V.Value>, text: String) -> String:
  match message:
    case T.SystemMessage{_, _, added, removed, _}:
      String.join(nonEmpty(text <> List.append(&2, String, removedTexts(Maybe.default(&2, List<&2, T.ToolReference>, removed, Nil{})), addedTexts(Maybe.default(&2, List<&2, T.Tool<V.Value>>, added, Nil{})))), "\n")

def messageToText(-G: Data, -D: Data, +message: T.Message<V.Value, V.Value, G, D>) -> IO(String):
  match message:
    case T.System{+system}:
      do IO<String>:
        text : String <- Text.getSystemMessageText(V.Value, system)
        return "system:" ++ systemText(system, text)
    case T.User{T.UserMessage{content, _}}: IO.pure(String, "user:" ++ contentToText(content))
    case T.Assistant{assistant}: IO.pure(String, "assistant:" ++ assistantContentToText(T.assistantContent(V.Value, G, assistant)))
    case T.ToolResult{result}: IO.pure(String, "toolResult:" ++ toolResultToText(D, result))

def messageTexts(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>) -> IO(List<&2, String>):
  match messages:
    case Nil{}: IO.pure(List<&2, String>, Nil{})
    case +message <> rest:
      do IO<List<&2, String>>:
        first : String <- messageToText(G, D, message)
        later : List<&2, String> <- messageTexts(G, D, rest)
        return first <> later

# upstream serializeContext: each message as `role:text`, joined by blank lines.
def serializeContext(-G: Data, -D: Data, context: Context(G, D)) -> IO(String):
  match context:
    case T.TranscriptContext{messages}:
      do IO<String>:
        texts : List<&2, String> <- messageTexts(G, D, messages)
        return String.join(texts, "\n\n")

# UTF-16 width of one scalar, and the first code unit it encodes to.
def unitWidth(+code: U32) -> Nat: Bool.pick(Nat, U32.is_gt(code, 65535), 2n, 1n)

def leadingUnit(+code: U32) -> U32: Bool.pick(U32, U32.is_gt(code, 65535), (55296 + (code - 65536) / 1024 : U32), code)

# upstream commonPrefixLength over UTF-16 code units, walked by scalar so no
# surrogate is materialized: equal scalars contribute their width, and a first
# difference inside a pair still shares its leading unit.
def prefixUnits(left: String, right: String, +count: Nat) -> Nat:
  match left right:
    case SCon{Chr{+a}, as} SCon{Chr{+b}, bs}:
      Bool.pick(Unit -> Nat, U32.is_eq(a, b), _ => prefixUnits(as, bs, count + unitWidth(a)), _ => count + Bool.pick(Nat, U32.is_eq(leadingUnit(a), leadingUnit(b)), 1n, 0n))(Unit{})
    case _ _: count

def commonPrefixLength(left: String, right: String) -> Nat: prefixUnits(left, right, 0n)

type Estimate is Data:
  Estimate{input: Nat, cacheRead: Nat, cacheWrite: Nat}

# estimateTokens(previous.slice(0, cached)) and estimateTokens(prompt.slice(cached))
# depend only on the unit counts of the slices.
def cachedEstimate(+previous: String, +prompt: String) -> Estimate:
  +cached = commonPrefixLength(previous, prompt)
  +read = ceilDiv4(cached)
  +promptTokens = estimateTokens(prompt)
  Estimate{Nat.sub(promptTokens, Nat.min(promptTokens, read)), read, ceilDiv4(Nat.sub(Utf16.length(prompt), cached))}

def sessionEstimate(previous: Maybe<&2, String>, +prompt: String) -> Estimate:
  match previous:
    case Some{SCon{c, cs}}: cachedEstimate(SCon{c, cs}, prompt)
    case _: Estimate{estimateTokens(prompt), 0n, estimateTokens(prompt)}

def cacheSession(-E: Data, options: Maybe<&2, Options(E)>) -> Maybe<&2, String>:
  match options:
    case Some{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, Some{T.CacheNone{}}, _, _, _, _, _, _, _}}: None{}
    case Some{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, Some{SCon{c, cs}}, _, _, _, _, _, _}}: Some{SCon{c, cs}}
    case _: None{}

def remembered(+cache: R.Record<String>, session: Maybe<&2, String>, +prompt: String) -> R.Record<String> & Estimate:
  match session:
    case None{}: (cache, Estimate{estimateTokens(prompt), 0n, 0n})
    case Some{+id}: (R.set(String, cache, id, prompt), sessionEstimate(R.get(String, cache, id), prompt))

def f64Of(value: Nat) -> F64: F.fromU32(U32.from_nat(value))

def withUsage(-G: Data, message: T.AssistantMessage<V.Value, G>, estimate: Estimate) -> T.AssistantMessage<V.Value, G>:
  match message estimate:
    case T.AssistantMessage{+content, api, provider, model, responseModel, responseId, thinking, diagnostics, _, reason, deferred, error, raw, endTurn, timestamp} Estimate{+input, +read, +write}:
      +output = estimateTokens(assistantContentToText(content))
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, T.Usage{f64Of(input), f64Of(output), f64Of(read), f64Of(write), None{}, None{}, f64Of(input + output + read + write), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}, reason, deferred, error, raw, endTurn, timestamp}

# upstream withUsageEstimate: prompt tokens from the serialized context, with
# a per-sessionId prompt cache unless cacheRetention is "none".
def withUsageEstimate(-G: Data, -D: Data, -E: Data, +message: T.AssistantMessage<V.Value, G>, context: Context(G, D), options: Maybe<&2, Options(E)>, cache: Ref.Ref<R.Record<String>>) -> IO(T.AssistantMessage<V.Value, G>):
  do IO<T.AssistantMessage<V.Value, G>>:
    +prompt : String <- serializeContext(G, D, context)
    estimate : Estimate <- Ref.modify(R.Record<String>, Estimate, cache, current => remembered(current, cacheSession(E, options), prompt))
    return withUsage(G, message, estimate)

# Messages
# --------
def cloned(-G: Data, message: T.AssistantMessage<V.Value, G>, +api: String, +provider: String, +modelId: String) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, _, _, _, responseModel, responseId, thinking, diagnostics, usage, reason, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, modelId, responseModel, responseId, thinking, diagnostics, usage, reason, deferred, error, raw, endTurn, timestamp}

def createErrorMessage(-G: Data, error: String, +api: String, +provider: String, +modelId: String, now: F64) -> T.AssistantMessage<V.Value, G>:
  T.AssistantMessage{Nil{}, api, provider, modelId, None{}, None{}, None{}, None{}, DEFAULT_USAGE(), T.Error{}, None{}, Some{error}, None{}, None{}, now}

def createAbortedMessage(-G: Data, partial: T.AssistantMessage<V.Value, G>, now: F64) -> T.AssistantMessage<V.Value, G>:
  match partial:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, _, deferred, _, raw, endTurn, _}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, T.Aborted{}, deferred, Some{"Request was aborted"}, raw, endTurn, now}

def withContent(-G: Data, message: T.AssistantMessage<V.Value, G>, content: List<&2, T.AssistantContent<V.Value>>, reason: T.StopReason) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{_, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, _, deferred, error, raw, endTurn, timestamp}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, reason, deferred, error, raw, endTurn, timestamp}

def contentOf(-G: Data, message: T.AssistantMessage<V.Value, G>) -> List<&2, T.AssistantContent<V.Value>>: T.assistantContent(V.Value, G, message)

# Chunking
# --------
def chunkChars(+tokenSize: Nat) -> Nat: Nat.max(1n, tokenSize * 4n)

def tokenSizeFor(+min: Nat, max: Nat, fraction: F64) -> Nat:
  min + natOf(F.multiply(fraction, f64Of(Nat.sub(max, min) + 1n)))

type Split is Data:
  Split{head: String, rest: String}

def headOf(split: Split) -> String:
  match split:
    case Split{head, _}: head

def restOf(split: Split) -> String:
  match split:
    case Split{_, rest}: rest

def consed(char: Char, split: Split) -> Split:
  match split:
    case Split{head, rest}: Split{SCon{char, head}, rest}

# text.slice(0, count) and text.slice(count) over UTF-16 units, walked by
# scalar; only a boundary inside a pair materializes its two lone surrogates.
def splitUnitsAt(text: String, count: Nat) -> Split:
  match text count:
    case SCon{Chr{+code}, +rest} 1n+ +n:
      Bool.pick(Unit -> Split, U32.is_gt(code, 65535) && Nat.is_eq(n, 0n), _ => Split{SCon{Chr{leadingUnit(code)}, SNil{}}, SCon{Chr{(56320 + (code - 65536) % 1024 : U32)}, rest}}, _ => consed(Chr{code}, splitUnitsAt(rest, Nat.sub(n, Nat.sub(unitWidth(code), 1n)))))(Unit{})
    case other _: Split{SNil{}, other}

# splitStringByTokenSize over UTF-16 code units: random token sizes between
# min and max, four characters per token; an empty text is one empty chunk.
@unsafe def chunkLoop(+text: String, +min: Nat, +max: Nat, +generator: Random.Generator, reversed: List<&2, String>) -> IO(List<&2, String>):
  match text:
    case SNil{}: IO.pure(List<&2, String>, List.reverse(&2, String, reversed))
    case _:
      do IO<List<&2, String>>:
        fraction : F64 <- Random.random(generator)
        +size : Nat <- IO.pure(Nat, chunkChars(tokenSizeFor(min, max, fraction)))
        +split : Split <- IO.pure(Split, splitUnitsAt(text, size))
        chunkLoop(restOf(split), min, max, generator, headOf(split) <> reversed)

def splitStringByTokenSize(text: String, min: Nat, max: Nat, generator: Random.Generator) -> IO(List<&2, String>):
  match text:
    case SNil{}: IO.pure(List<&2, String>, "" <> Nil{})
    case other: chunkLoop(other, min, max, generator, Nil{})

# streamWithDeltas
# ----------------
def EventStream(-G: Data) -> Data: Events.AssistantMessageEventStream(V.Value, G)

def push(-G: Data, events: EventStream(G), event: T.AssistantMessageEvent<V.Value, G>) -> IO(Unit):
  Events.push(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, event)

def finishWith(-G: Data, +events: EventStream(G), event: T.AssistantMessageEvent<V.Value, G>, message: T.AssistantMessage<V.Value, G>) -> IO(Unit):
  do IO<Unit>:
    push(G, events, event)
    Events.end(T.AssistantMessageEvent<V.Value, G>, T.AssistantMessage<V.Value, G>, events, Some{message})

def failWith(-G: Data, +events: EventStream(G), +message: T.AssistantMessage<V.Value, G>) -> IO(Unit):
  finishWith(G, events, T.StreamError{T.ErrorError{}, message}, message)

def abortWith(-G: Data, +events: EventStream(G), partial: T.AssistantMessage<V.Value, G>) -> IO(Unit):
  do IO<Unit>:
    now : F64 <- Date.now()
    +aborted : T.AssistantMessage<V.Value, G> <- IO.pure(T.AssistantMessage<V.Value, G>, createAbortedMessage(G, partial, now))
    finishWith(G, events, T.StreamError{T.ErrorAborted{}, aborted}, aborted)

# The block being streamed.
type Block is Data:
  ThinkingBlock{full: String}
  TextBlock{full: String}
  CallBlock{call: T.ToolCall<V.Value>}

type Work<-G: Data> is Data:
  Blocks{index: Nat, rest: List<&2, T.AssistantContent<V.Value>>, partial: T.AssistantMessage<V.Value, G>}
  Chunks{index: Nat, block: Block, chunks: List<&2, String>, rest: List<&2, T.AssistantContent<V.Value>>, partial: T.AssistantMessage<V.Value, G>}
  Stopped{}

type Pacing is Data:
  Pacing{min: Nat, max: Nat, tokensPerSecond: Maybe<&2, F64>, random: Random.Generator, signal: Maybe<&2, Abort.AbortSignal<Unit>>}

def isAborted(signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool, False{})
    case Some{value}: Abort.aborted(Unit, value)

def pacingSignal(pacing: Pacing) -> Maybe<&2, Abort.AbortSignal<Unit>>:
  match pacing:
    case Pacing{_, _, _, _, signal}: signal

def pacingRandom(pacing: Pacing) -> Random.Generator:
  match pacing:
    case Pacing{_, _, _, random, _}: random

def pacingSizes(pacing: Pacing) -> Nat & Nat:
  match pacing:
    case Pacing{min, max, _, _, _}: (min, max)

def delayMilliseconds(value: Result<&2, &2, Timer.Error, U32>) -> U32:
  match value:
    case Done{milliseconds}: milliseconds
    case Fail{_}: 0

def paced(+tokensPerSecond: F64, positive: Bool, chunk: String) -> IO(Unit):
  match positive:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: IO.sleep(delayMilliseconds(Timer.milliseconds(F.multiply(F.divide(f64Of(estimateTokens(chunk)), tokensPerSecond), F.fromU32(1000)))))

# upstream scheduleChunk: paced by tokensPerSecond, else a microtask turn.
def scheduleChunk(pacing: Pacing, chunk: String) -> IO(Unit):
  match pacing:
    case Pacing{_, _, Some{+rate}, _, _}: paced(rate, F.isGreater(F.compare(rate, F.fromU32(0))), chunk)
    case _: IO.pure(Unit, Unit{})

def appendedLast(content: List<&2, T.AssistantContent<V.Value>>, +chunk: String) -> List<&2, T.AssistantContent<V.Value>>:
  match content:
    case Nil{}: Nil{}
    case T.AssistantThinking{T.ThinkingContent{text, signature, redacted}} <> Nil{}: T.AssistantThinking{T.ThinkingContent{text ++ chunk, signature, redacted}} <> Nil{}
    case T.AssistantText{T.TextContent{text, signature}} <> Nil{}: T.AssistantText{T.TextContent{text ++ chunk, signature}} <> Nil{}
    case last <> Nil{}: last <> Nil{}
    case first <> rest: first <> appendedLast(rest, chunk)

def replacedLast(content: List<&2, T.AssistantContent<V.Value>>, +block: T.AssistantContent<V.Value>) -> List<&2, T.AssistantContent<V.Value>>:
  match content:
    case Nil{}: Nil{}
    case _ <> Nil{}: block <> Nil{}
    case first <> rest: first <> replacedLast(rest, block)

def withBlock(-G: Data, +partial: T.AssistantMessage<V.Value, G>, block: T.AssistantContent<V.Value>) -> T.AssistantMessage<V.Value, G>:
  withContent(G, partial, List.append(&2, T.AssistantContent<V.Value>, contentOf(G, partial), block <> Nil{}), T.Pending{})

def blockStart(block: T.AssistantContent<V.Value>) -> T.AssistantContent<V.Value>:
  match block:
    case T.AssistantThinking{_}: fauxThinking("")
    case T.AssistantText{_}: fauxText("")
    case T.AssistantToolCall{T.ToolCall{id, name, _, _, _}}: T.AssistantToolCall{T.ToolCall{id, name, V.ObjectValue{R.new(V.Value)}, None{}, None{}}}

def blockOf(block: T.AssistantContent<V.Value>) -> Block:
  match block:
    case T.AssistantThinking{T.ThinkingContent{thinking, _, _}}: ThinkingBlock{thinking}
    case T.AssistantText{T.TextContent{text, _}}: TextBlock{text}
    case T.AssistantToolCall{call}: CallBlock{call}

def blockSource(block: Block) -> String:
  match block:
    case ThinkingBlock{full}: full
    case TextBlock{full}: full
    case CallBlock{T.ToolCall{_, _, arguments, _, _}}: jsonText(arguments)

def startEvent(-G: Data, block: Block, index: F64, partial: T.AssistantMessage<V.Value, G>) -> T.AssistantMessageEvent<V.Value, G>:
  match block:
    case ThinkingBlock{_}: T.ThinkingStart{index, partial}
    case TextBlock{_}: T.TextStart{index, partial}
    case CallBlock{_}: T.ToolcallStart{index, partial}

def deltaPartial(-G: Data, block: Block, +partial: T.AssistantMessage<V.Value, G>, +chunk: String) -> T.AssistantMessage<V.Value, G>:
  match block:
    case CallBlock{_}: partial
    case _: withContent(G, partial, appendedLast(contentOf(G, partial), chunk), T.Pending{})

def deltaEvent(-G: Data, block: Block, index: F64, chunk: String, partial: T.AssistantMessage<V.Value, G>) -> T.AssistantMessageEvent<V.Value, G>:
  match block:
    case ThinkingBlock{_}: T.ThinkingDelta{index, chunk, partial}
    case TextBlock{_}: T.TextDelta{index, chunk, partial}
    case CallBlock{_}: T.ToolcallDelta{index, chunk, partial}

def endPartial(-G: Data, block: Block, +partial: T.AssistantMessage<V.Value, G>) -> T.AssistantMessage<V.Value, G>:
  match block:
    case CallBlock{call}: withContent(G, partial, replacedLast(contentOf(G, partial), T.AssistantToolCall{call}), T.Pending{})
    case _: partial

def endEvent(-G: Data, block: Block, index: F64, partial: T.AssistantMessage<V.Value, G>) -> T.AssistantMessageEvent<V.Value, G>:
  match block:
    case ThinkingBlock{full}: T.ThinkingEnd{index, full, partial}
    case TextBlock{full}: T.TextEnd{index, full, partial}
    case CallBlock{call}: T.ToolcallEnd{index, call, partial}

def doneReason(reason: T.StopReason) -> Maybe<&2, T.DoneReason>:
  match reason:
    case T.Stop{}: Some{T.DoneStop{}}
    case T.Length{}: Some{T.DoneLength{}}
    case T.ToolUse{}: Some{T.DoneToolUse{}}
    case T.Deferred{}: Some{T.DoneDeferred{}}
    case _: None{}

# After the blocks: a pending stop reason is thrown; error and aborted
# messages end as terminal errors; others are done.
def messageApi(-G: Data, message: T.AssistantMessage<V.Value, G>) -> String:
  match message:
    case T.AssistantMessage{_, api, _, _, _, _, _, _, _, _, _, _, _, _, _}: api

def finishedAs(-G: Data, reason: T.StopReason, +events: EventStream(G), +message: T.AssistantMessage<V.Value, G>, now: F64) -> IO(Unit):
  match reason:
    case T.Pending{}: failWith(G, events, createErrorMessage(G, "Faux response ended without a stop reason", messageApi(G, message), T.assistantProvider(V.Value, G, message), T.assistantModel(V.Value, G, message), now))
    case T.Error{}: finishWith(G, events, T.StreamError{T.ErrorError{}, message}, message)
    case T.Aborted{}: finishWith(G, events, T.StreamError{T.ErrorAborted{}, message}, message)
    case other: finishWith(G, events, T.StreamDone{Maybe.default(&2, T.DoneReason, doneReason(other), T.DoneStop{}), message}, message)

def finished(-G: Data, +events: EventStream(G), +message: T.AssistantMessage<V.Value, G>, now: F64) -> IO(Unit):
  finishedAs(G, T.assistantStopReason(V.Value, G, message), events, message, now)

def chunksOf(pacing: Pacing, block: Block) -> IO(List<&2, String>):
  match pacing:
    case Pacing{min, max, _, random, _}: splitStringByTokenSize(blockSource(block), min, max, random)

def started(-G: Data, +events: EventStream(G), +pacing: Pacing, aborted: Bool, +index: Nat, +block: T.AssistantContent<V.Value>, rest: List<&2, T.AssistantContent<V.Value>>, +partial: T.AssistantMessage<V.Value, G>) -> IO(Work<G>):
  match aborted:
    case True{}:
      do IO<Work<G>>:
        abortWith(G, events, partial)
        return Stopped{}
    case False{}:
      +kind = blockOf(block)
      +opened = withBlock(G, partial, blockStart(block))
      do IO<Work<G>>:
        push(G, events, startEvent(G, kind, f64Of(index), opened))
        chunks : List<&2, String> <- chunksOf(pacing, kind)
        return Chunks{index, kind, chunks, rest, opened}

def delta(-G: Data, +events: EventStream(G), aborted: Bool, +index: Nat, +block: Block, +chunk: String, more: List<&2, String>, rest: List<&2, T.AssistantContent<V.Value>>, +partial: T.AssistantMessage<V.Value, G>) -> IO(Work<G>):
  match aborted:
    case True{}:
      do IO<Work<G>>:
        abortWith(G, events, partial)
        return Stopped{}
    case False{}:
      +updated = deltaPartial(G, block, partial, chunk)
      do IO<Work<G>>:
        push(G, events, deltaEvent(G, block, f64Of(index), chunk, updated))
        return Chunks{index, block, more, rest, updated}

# One step of the delta stream: the next block starts, a chunk is published,
# or a block ends. Cancellation is checked before each block and after each
# scheduled chunk.
@unsafe def drive(-G: Data, +events: EventStream(G), +message: T.AssistantMessage<V.Value, G>, +pacing: Pacing, work: Work<G>) -> IO(Unit):
  match work:
    case Stopped{}: IO.pure(Unit, Unit{})
    case Blocks{_, Nil{}, _}:
      do IO<Unit>:
        now : F64 <- Date.now()
        finished(G, events, message, now)
    case Blocks{index, +block <> rest, +partial}:
      do IO<Unit>:
        aborted : Bool <- isAborted(pacingSignal(pacing))
        next : Work<G> <- started(G, events, pacing, aborted, index, block, rest, partial)
        drive(G, events, message, pacing, next)
    case Chunks{+index, +block, Nil{}, rest, +partial}:
      +ended = endPartial(G, block, partial)
      do IO<Unit>:
        push(G, events, endEvent(G, block, f64Of(index), ended))
        drive(G, events, message, pacing, Blocks{1n + index, rest, ended})
    case Chunks{index, +block, +chunk <> more, rest, +partial}:
      do IO<Unit>:
        scheduleChunk(pacing, chunk)
        aborted : Bool <- isAborted(pacingSignal(pacing))
        next : Work<G> <- delta(G, events, aborted, index, block, chunk, more, rest, partial)
        drive(G, events, message, pacing, next)

def beginning(-G: Data, +events: EventStream(G), +message: T.AssistantMessage<V.Value, G>, +pacing: Pacing, +partial: T.AssistantMessage<V.Value, G>, aborted: Bool) -> IO(Unit):
  match aborted:
    case True{}: abortWith(G, events, partial)
    case False{}:
      do IO<Unit>:
        push(G, events, T.Start{partial})
        drive(G, events, message, pacing, Blocks{0n, contentOf(G, message), partial})


# upstream streamWithDeltas.
def streamWithDeltas(-G: Data, +events: EventStream(G), +message: T.AssistantMessage<V.Value, G>, +pacing: Pacing) -> IO(Unit):
  +partial = withContent(G, message, Nil{}, T.Pending{})
  do IO<Unit>:
    aborted : Bool <- isAborted(pacingSignal(pacing))
    beginning(G, events, message, pacing, partial, aborted)


# The stream
# ----------
type FauxStream<-G: Data> is Type:
  FauxStream{events: EventStream(G), task: Chan(Unit)}

def borrowStream(-G: Data, owner: FauxStream<G>) -> FauxStream<G> & EventStream(G):
  match owner:
    case FauxStream{+events, task}: (FauxStream{events, task}, events)

# Waits for the producer, then disposes the event stream.
def disposeStream(-G: Data, owner: FauxStream<G>) -> IO(Unit):
  match owner:
    case FauxStream{events, task}:
      do IO<Unit>:
        done : Unit <- IO.join(Unit, task)
        Events.disposeAssistantMessageEventStream(V.Value, G, events)

def optionSignal(-E: Data, options: Maybe<&2, Options(E)>) -> Maybe<&2, Abort.AbortSignal<Unit>>:
  match options:
    case Some{T.SimpleStreamOptions{signal, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: signal
    case None{}: None{}

def optionResponse(-E: Data, options: Maybe<&2, Options(E)>) -> Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>:
  match options:
    case Some{T.SimpleStreamOptions{_, _, _, _, _, _, response, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: response
    case None{}: None{}

def rendered(~E: Data, ~render: E -> String, result: Result<&2, &2, E, Unit>) -> Result<&2, &2, String, Unit>:
  match result:
    case Done{value}: Done{value}
    case Fail{cause}: Fail{render(cause)}

def responseHook(~E: Data, ~render: E -> String, hook: Maybe<&2, T.ResponseCallback(T.Model<J()>, E)>, model: T.Model<J()>) -> IO(Result<&2, &2, String, Unit>):
  match hook:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Some{callback}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, E, Unit> <- C.call(T.ResponseInput<T.Model<J()>>, Result<&2, &2, E, Unit>, callback, T.ResponseInput{T.ProviderResponse{F.fromU32(200), R.new(String)}, model})
        return rendered(~E, ~render, result)

def pacingFor(-G: Data, -D: Data, -E: Data, core: FauxCore<G, D, E>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> Pacing:
  match core:
    case FauxCore{_, _, _, min, max, rate, _, _, _, random}: Pacing{min, max, rate, random, signal}

def resolved(-G: Data, -D: Data, -E: Data, step: FauxResponseStep<G, D, E>, input: FactoryInput<G, D, E>) -> IO(Result<&2, &2, String, T.AssistantMessage<V.Value, G>>):
  match step:
    case FauxReply{message}: IO.pure(Result<&2, &2, String, T.AssistantMessage<V.Value, G>>, Done{message})
    case FauxFactory{factory}: C.call(FactoryInput<G, D, E>, Result<&2, &2, String, T.AssistantMessage<V.Value, G>>, factory, input)

def failed(-G: Data, +events: EventStream(G), error: String, +api: String, +provider: String, +modelId: String) -> IO(Unit):
  do IO<Unit>:
    now : F64 <- Date.now()
    failWith(G, events, createErrorMessage(G, error, api, provider, modelId, now))

def respond(-G: Data, -D: Data, -E: Data, +core: FauxCore<G, D, E>, +events: EventStream(G), +model: T.Model<J()>, context: Context(G, D), +options: Maybe<&2, Options(E)>, result: Result<&2, &2, String, T.AssistantMessage<V.Value, G>>) -> IO(Unit):
  match core result:
    case FauxCore{api, provider, _, _, _, _, _, _, _, _} Fail{error}: failed(G, events, error, api, provider, T.modelId(model))
    case FauxCore{api, provider, _, _, _, _, _, _, cache, _} Done{message}:
      do IO<Unit>:
        +estimated : T.AssistantMessage<V.Value, G> <- withUsageEstimate(G, D, E, cloned(G, message, api, provider, T.modelId(model)), context, options, cache)
        streamWithDeltas(G, events, estimated, pacingFor(G, D, E, core, optionSignal(E, options)))

# No queued response: an error message with the usage estimate.
def exhausted(-G: Data, -D: Data, -E: Data, +core: FauxCore<G, D, E>, +events: EventStream(G), +model: T.Model<J()>, context: Context(G, D), options: Maybe<&2, Options(E)>) -> IO(Unit):
  match core:
    case FauxCore{api, provider, _, _, _, _, _, _, cache, _}:
      do IO<Unit>:
        now : F64 <- Date.now()
        +message : T.AssistantMessage<V.Value, G> <- withUsageEstimate(G, D, E, createErrorMessage(G, "No more faux responses queued", api, provider, T.modelId(model), now), context, options, cache)
        failWith(G, events, message)

def stepped(-G: Data, -D: Data, -E: Data, +core: FauxCore<G, D, E>, +events: EventStream(G), +model: T.Model<J()>, +context: Context(G, D), +options: Maybe<&2, Options(E)>, step: Maybe<&2, FauxResponseStep<G, D, E>>) -> IO(Unit):
  match core step:
    case _ None{}: exhausted(G, D, E, core, events, model, context, options)
    case FauxCore{_, _, _, _, _, _, _, state, _, _} Some{chosen}:
      do IO<Unit>:
        snapshot : FauxProviderState <- Ref.read(FauxProviderState, state)
        result : Result<&2, &2, String, T.AssistantMessage<V.Value, G>> <- resolved(G, D, E, chosen, FactoryInput{context, options, snapshot, model})
        respond(G, D, E, core, events, model, context, options, result)

def hooked(-G: Data, -D: Data, -E: Data, +core: FauxCore<G, D, E>, +events: EventStream(G), +model: T.Model<J()>, +context: Context(G, D), +options: Maybe<&2, Options(E)>, step: Maybe<&2, FauxResponseStep<G, D, E>>, hook: Result<&2, &2, String, Unit>) -> IO(Unit):
  match core hook:
    case FauxCore{api, provider, _, _, _, _, _, _, _, _} Fail{error}: failed(G, events, error, api, provider, T.modelId(model))
    case _ Done{_}: stepped(G, D, E, core, events, model, context, options, step)

def produce(~G: Data, ~D: Data, ~E: Data, ~render: E -> String, +core: FauxCore<G, D, E>, +events: EventStream(G), +model: T.Model<J()>, +context: Context(G, D), +options: Maybe<&2, Options(E)>, step: Maybe<&2, FauxResponseStep<G, D, E>>) -> IO(Unit):
  do IO<Unit>:
    hook : Result<&2, &2, String, Unit> <- responseHook(~E, ~render, optionResponse(E, options), model)
    hooked(G, D, E, core, events, model, context, options, step, hook)

def shifted(-G: Data, -D: Data, -E: Data, pending: List<&2, FauxResponseStep<G, D, E>>) -> List<&2, FauxResponseStep<G, D, E>> & Maybe<&2, FauxResponseStep<G, D, E>>:
  match pending:
    case Nil{}: (Nil{}, None{})
    case first <> rest: (rest, Some{first})

def counted(state: FauxProviderState) -> FauxProviderState & Unit:
  match state:
    case FauxProviderState{calls, fetches, cancelled}: (FauxProviderState{1n + calls, fetches, cancelled}, Unit{})

# upstream createFauxCore's stream (streamSimple is the same): take the next
# queued response and count the call now; the response streams from a task.
def stream(~G: Data, ~D: Data, ~E: Data, ~render: E -> String, +core: FauxCore<G, D, E>, +model: T.Model<J()>, +context: Context(G, D), +options: Maybe<&2, Options(E)>) -> IO(FauxStream<G>):
  match core:
    case FauxCore{api, provider, models, min, max, rate, +pending, +state, cache, random}:
      do IO<FauxStream<G>>:
        step : Maybe<&2, FauxResponseStep<G, D, E>> <- Ref.modify(List<&2, FauxResponseStep<G, D, E>>, Maybe<&2, FauxResponseStep<G, D, E>>, pending, current => shifted(G, D, E, current))
        Ref.modify(FauxProviderState, Unit, state, counted)
        +events : EventStream(G) <- Events.createAssistantMessageEventStream(~V.Value, ~G)
        task : Chan(Unit) <- IO.fork(Unit, produce(~G, ~D, ~E, ~render, FauxCore{api, provider, models, min, max, rate, pending, state, cache, random}, events, model, context, options, step))
        return FauxStream{events, task}

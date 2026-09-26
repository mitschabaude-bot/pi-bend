import Base
import ../types.bend as T
import ../utils/schema-json.bend as Schema
import ../utils/text.bend as Text
import ../utils/transcript.bend as Transcript
import ../utils/tool-declaration.bend as Declaration
import ../utils/thinking-levels.bend as Levels
import ../utils/provider-env.bend as Env
import ../utils/sanitize-unicode.bend as Unicode
import ../utils/headers.bend as HeaderUtils
import ./constrained-sampling.bend as Sampling
import ./simple-options.bend as Simple
import ./transform-messages.bend as Transform
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/case-map.bend as Case
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/text.bend as Space

# The Anthropic Messages request side (pi `anthropic-messages.ts`): options,
# compatibility resolution, cache control, Claude Code tool naming, message and
# tool conversion, beta features, buildParams and streamSimple's option
# mapping. Wire values are typed JSON values serialized once by the client
# (anthropic-messages-client.bend); SSE folding lives in
# anthropic-messages-stream.bend.
def J() -> Data: T.JsonValue

def Fields() -> Data: R.Record<J()>

def str(value: String) -> J(): T.JsonString{value}

def bool(value: Bool) -> J(): T.JsonBoolean{value}

def num(value: F64) -> J(): T.JsonNumber{value}

def obj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}

def field(name: String, value: J()) -> R.Property<J()>: R.Property{name, value}

def put(fields: Fields(), name: String, value: J()) -> Fields(): R.set(J(), fields, name, value)

def maybe(fields: Fields(), name: String, value: Maybe<&2, J()>) -> Fields():
  match value:
    case None{}: fields
    case Some{item}: put(fields, name, item)

def optionalBool(value: Maybe<&2, Bool>, default: Bool) -> Bool: Maybe.default(&2, Bool, value, default)

# Options
# -------
# upstream AnthropicEffort ("low" | "medium" | "high" | "xhigh" | "max"). A
# model's thinkingLevelMap may name any string, which upstream forwards as an
# effort, so efforts stay strings; isAnthropicEffort recognizes the five.
def isAnthropicEffort(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{"low"}: True{}
    case Some{"medium"}: True{}
    case Some{"high"}: True{}
    case Some{"xhigh"}: True{}
    case Some{"max"}: True{}
    case _: False{}

type AnthropicThinkingDisplay is Data:
  Summarized{}
  Omitted{}

def displayName(value: AnthropicThinkingDisplay) -> String:
  match value:
    case Summarized{}: "summarized"
    case Omitted{}: "omitted"

# The string choices map to Anthropic's built-in choices; ChoiceTool forces one.
type AnthropicToolChoice is Data:
  ChoiceAuto{}
  ChoiceAny{}
  ChoiceNone{}
  ChoiceTool{name: String}

# upstream AnthropicOptions extends StreamOptions; the shared options are one
# field. `client` is the injected client (anthropic-messages-client.bend).
type AnthropicOptions<-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, -Client: Data> is Data:
  AnthropicOptions{base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, thinkingEnabled: Maybe<&2, Bool>, thinkingBudgetTokens: Maybe<&2, F64>, effort: Maybe<&2, String>, thinkingDisplay: Maybe<&2, AnthropicThinkingDisplay>, interleavedThinking: Maybe<&2, Bool>, toolChoice: Maybe<&2, AnthropicToolChoice>, client: Maybe<&2, Client>}

def emptyStreamOptions(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data) -> T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>:
  T.StreamOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def withBase(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, -Client: Data, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>) -> AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>:
  AnthropicOptions{base, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

# Compatibility
# -------------
def rawCompat(model: T.Model<J()>) -> T.AnthropicMessagesCompat:
  match model:
    case T.Model{_, _, T.AnthropicMessagesApi{}, _, _, _, _, _, _, _, _, _, _, _, _, Some{value}}: value
    case _: T.AnthropicMessagesCompat{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def rawForce(compat: T.AnthropicMessagesCompat) -> Bool:
  match compat:
    case T.AnthropicMessagesCompat{_, _, _, _, _, _, value, _, _, _, _, _, _}: optionalBool(value, False{})

def rawMidConvoEffort(compat: T.AnthropicMessagesCompat) -> Bool:
  match compat:
    case T.AnthropicMessagesCompat{_, _, _, _, _, _, _, _, _, value, _, _, _}: optionalBool(value, False{})

def rawFallbacks(compat: T.AnthropicMessagesCompat) -> List<&2, T.AnthropicAllowedFallbackModel>:
  match compat:
    case T.AnthropicMessagesCompat{_, _, _, _, _, _, _, _, _, _, _, _, values}: Maybe.default(&2, List<&2, T.AnthropicAllowedFallbackModel>, values, Nil{})

def forceAdaptiveThinking(model: T.Model<J()>) -> Bool: rawForce(rawCompat(model))

def supportsMidConvoEffort(model: T.Model<J()>) -> Bool: rawMidConvoEffort(rawCompat(model))

def allowedFallbackModels(model: T.Model<J()>) -> List<&2, T.AnthropicAllowedFallbackModel>: rawFallbacks(rawCompat(model))

# upstream getAnthropicCompat: every flag after defaults. OpenRouter (by
# provider or base URL) sends session affinity in its own header format.
type AnthropicCompat is Data:
  AnthropicCompat{supportsEagerToolInputStreaming: Bool, supportsLongCacheRetention: Bool, sendSessionAffinityHeaders: Bool, sessionAffinityFormat: Maybe<&2, T.AnthropicSessionAffinityFormat>, supportsCacheControlOnTools: Bool, supportsTemperature: Bool, allowEmptySignature: Bool, supportsStrictTools: Bool, supportsMidConvoSystemMessages: Bool, supportsMidConvoToolChanges: Bool}

def isOpenRouter(model: T.Model<J()>) -> Bool:
  match model:
    case T.Model{_, _, _, provider, base, _, _, _, _, _, _, _, _, _, _, _}: String.eq(provider, "openrouter") || String.contains(base, "openrouter.ai")

def affinityFormat(value: Maybe<&2, T.AnthropicSessionAffinityFormat>, router: Bool) -> Maybe<&2, T.AnthropicSessionAffinityFormat>:
  match value:
    case Some{format}: Some{format}
    case None{}: Bool.pick(Maybe<&2, T.AnthropicSessionAffinityFormat>, router, Some{T.AnthropicOpenRouterSession{}}, None{})

def resolveCompat(raw: T.AnthropicMessagesCompat, +router: Bool) -> AnthropicCompat:
  match raw:
    case T.AnthropicMessagesCompat{eager, long, affinity, format, toolCache, temperature, _, empty, strict, _, midSystem, midTools, _}:
      AnthropicCompat{optionalBool(eager, True{}), optionalBool(long, True{}), optionalBool(affinity, router), affinityFormat(format, router), optionalBool(toolCache, True{}), optionalBool(temperature, True{}), optionalBool(empty, False{}), optionalBool(strict, False{}), optionalBool(midSystem, False{}), optionalBool(midTools, False{})}

def getAnthropicCompat(+model: T.Model<J()>) -> AnthropicCompat: resolveCompat(rawCompat(model), isOpenRouter(model))

def compatEager(compat: AnthropicCompat) -> Bool:
  match compat:
    case AnthropicCompat{value, _, _, _, _, _, _, _, _, _}: value

def compatLongCache(compat: AnthropicCompat) -> Bool:
  match compat:
    case AnthropicCompat{_, value, _, _, _, _, _, _, _, _}: value

def compatSendAffinity(compat: AnthropicCompat) -> Bool:
  match compat:
    case AnthropicCompat{_, _, value, _, _, _, _, _, _, _}: value

def compatAffinityFormat(compat: AnthropicCompat) -> Maybe<&2, T.AnthropicSessionAffinityFormat>:
  match compat:
    case AnthropicCompat{_, _, _, value, _, _, _, _, _, _}: value

def compatToolCache(compat: AnthropicCompat) -> Bool:
  match compat:
    case AnthropicCompat{_, _, _, _, value, _, _, _, _, _}: value

def compatTemperature(compat: AnthropicCompat) -> Bool:
  match compat:
    case AnthropicCompat{_, _, _, _, _, value, _, _, _, _}: value

def compatEmptySignature(compat: AnthropicCompat) -> Bool:
  match compat:
    case AnthropicCompat{_, _, _, _, _, _, value, _, _, _}: value

def compatStrictTools(compat: AnthropicCompat) -> Bool:
  match compat:
    case AnthropicCompat{_, _, _, _, _, _, _, value, _, _}: value

def compatMidSystem(compat: AnthropicCompat) -> Bool:
  match compat:
    case AnthropicCompat{_, _, _, _, _, _, _, _, value, _}: value

def compatMidTools(compat: AnthropicCompat) -> Bool:
  match compat:
    case AnthropicCompat{_, _, _, _, _, _, _, _, _, value}: value

# Cache control
# -------------
def environmentRetention(value: Maybe<&2, String>) -> T.CacheRetention:
  match value:
    case Some{"long"}: T.CacheLong{}
    case _: T.CacheShort{}

# upstream resolveCacheRetention: explicit retention, else PI_CACHE_RETENTION=long,
# else short.
def resolveCacheRetention(retention: Maybe<&2, T.CacheRetention>, env: Maybe<&2, T.ProviderEnv()>) -> IO(T.CacheRetention):
  match retention:
    case Some{value}: IO.pure(T.CacheRetention, value)
    case None{}:
      do IO<T.CacheRetention>:
        value : Maybe<&2, String> <- Env.getProviderEnvValue("PI_CACHE_RETENTION", env)
        return environmentRetention(value)

# upstream getCacheControl's ephemeral marker; a long ttl needs model support.
def cacheControlFor(retention: T.CacheRetention, longSupported: Bool) -> Maybe<&2, J()>:
  match retention:
    case T.CacheNone{}: None{}
    case T.CacheShort{}: Some{obj(field("type", str("ephemeral")) <> Nil{})}
    case T.CacheLong{}: Some{obj(field("type", str("ephemeral")) <> Bool.pick(List<&2, R.Property<J()>>, longSupported, field("ttl", str("1h")) <> Nil{}, Nil{}))}

def getCacheControl(+model: T.Model<J()>, retention: Maybe<&2, T.CacheRetention>, env: Maybe<&2, T.ProviderEnv()>) -> IO(Maybe<&2, J()>):
  do IO<Maybe<&2, J()>>:
    resolved : T.CacheRetention <- resolveCacheRetention(retention, env)
    return cacheControlFor(resolved, compatLongCache(getAnthropicCompat(model)))

# Claude Code tool names
# ----------------------
# Stealth mode mimics Claude Code 2.x tool names (canonical casing).
def claudeCodeVersion() -> String: "2.1.280"

def claudeCodeTools() -> List<&2, String>:
  ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "AskUserQuestion", "EnterPlanMode", "ExitPlanMode", "KillShell", "NotebookEdit", "Skill", "Task", "TaskOutput", "TodoWrite", "WebFetch", "WebSearch"]

def lookupClaudeCode(names: List<&2, String>, +lower: String, original: String) -> String:
  match names:
    case Nil{}: original
    case +name <> rest: Bool.pick(String, String.eq(Case.lower(name), lower), name, lookupClaudeCode(rest, lower, original))

# Convert a tool name to Claude Code's canonical casing when it matches one
# case-insensitively.
def toClaudeCodeName(+name: String) -> String: lookupClaudeCode(claudeCodeTools(), Case.lower(name), name)

def lookupTool(tools: List<&2, T.Tool<V.Value>>, +lower: String, original: String) -> String:
  match tools:
    case Nil{}: original
    case T.Tool{+toolName, _, _, _} <> rest: Bool.pick(String, String.eq(Case.lower(toolName), lower), toolName, lookupTool(rest, lower, original))

# Map a returned tool name back to the matching context tool's casing.
def fromClaudeCodeName(+name: String, tools: List<&2, T.Tool<V.Value>>) -> String: lookupTool(tools, Case.lower(name), name)

def wireToolName(+name: String, oauth: Bool) -> String: Bool.pick(String, oauth, toClaudeCodeName(name), name)

# Content conversion
# ------------------
def textBlock(value: String) -> J(): obj(field("type", str("text")) <> field("text", str(Unicode.sanitizeSurrogates(value))) <> Nil{})

def imageBlock(image: T.ImageContent) -> J():
  match image:
    case T.ImageContent{data, mime}: obj(field("type", str("image")) <> field("source", obj(field("type", str("base64")) <> field("media_type", str(mime)) <> field("data", str(data)) <> Nil{})) <> Nil{})

def contentBlock(item: T.TextImageContent) -> J():
  match item:
    case T.TextImageText{T.TextContent{value, _}}: textBlock(value)
    case T.TextImageImage{image}: imageBlock(image)

def contentBlocks(items: List<&2, T.TextImageContent>) -> List<&2, J()>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: contentBlock(item) <> contentBlocks(rest)

def hasImage(items: List<&2, T.TextImageContent>) -> Bool:
  match items:
    case Nil{}: False{}
    case T.TextImageImage{_} <> _: True{}
    case _ <> rest: hasImage(rest)

def hasText(items: List<&2, T.TextImageContent>) -> Bool:
  match items:
    case Nil{}: False{}
    case T.TextImageText{_} <> _: True{}
    case _ <> rest: hasText(rest)

def textParts(items: List<&2, T.TextImageContent>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{text, _}} <> rest: text <> textParts(rest)
    case _ <> rest: textParts(rest)

def blocksWithImages(+items: List<&2, T.TextImageContent>) -> J():
  T.JsonArray{Bool.pick(List<&2, J()>, hasText(items), contentBlocks(items), obj(field("type", str("text")) <> field("text", str("(see attached image)")) <> Nil{}) <> contentBlocks(items))}

# upstream convertContentBlocks: text-only content is one joined string.
def convertContentBlocks(+items: List<&2, T.TextImageContent>) -> J():
  Bool.pick(J(), hasImage(items), blocksWithImages(items), str(Unicode.sanitizeSurrogates(String.join(textParts(items), "\n"))))

def userBlock(item: T.TextImageContent) -> Maybe<&2, J()>:
  match item:
    case T.TextImageText{T.TextContent{+text, _}}: Bool.pick(Maybe<&2, J()>, Space.blank(text), None{}, Some{textBlock(text)})
    case T.TextImageImage{image}: Some{imageBlock(image)}

def prependOptional(value: Maybe<&2, J()>, values: List<&2, J()>) -> List<&2, J()>:
  match value:
    case None{}: values
    case Some{item}: item <> values

def userBlocks(items: List<&2, T.TextImageContent>) -> List<&2, J()>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: prependOptional(userBlock(item), userBlocks(rest))

def wireMessage(role: String, content: J()) -> J(): obj(field("role", str(role)) <> field("content", content) <> Nil{})

def nonemptyUser(blocks: List<&2, J()>) -> Maybe<&2, J()>:
  match blocks:
    case Nil{}: None{}
    case values: Some{wireMessage("user", T.JsonArray{values})}

# A user message without content after dropping blank text is omitted.
def userMessage(content: T.UserContent) -> Maybe<&2, J()>:
  match content:
    case T.UserText{+text}: Bool.pick(Maybe<&2, J()>, Space.blank(text), None{}, Some{wireMessage("user", str(Unicode.sanitizeSurrogates(text)))})
    case T.UserBlocks{items}: nonemptyUser(userBlocks(items))

def signed(signature: Maybe<&2, String>) -> Maybe<&2, String>:
  match signature:
    case Some{+value}: Bool.pick(Maybe<&2, String>, Space.blank(value), None{}, Some{value})
    case None{}: None{}

def unsignedThinking(text: String, allowEmptySignature: Bool) -> J():
  match allowEmptySignature:
    case True{}: obj(field("type", str("thinking")) <> field("thinking", str(Unicode.sanitizeSurrogates(text))) <> field("signature", str("")) <> Nil{})
    case False{}: textBlock(text)

def ordinaryThinking(+text: String, signature: Maybe<&2, String>, allowEmptySignature: Bool) -> Maybe<&2, J()>:
  match signature:
    case Some{value}: Some{obj(field("type", str("thinking")) <> field("thinking", str(Unicode.sanitizeSurrogates(text))) <> field("signature", str(value)) <> Nil{})}
    case None{}: Bool.pick(Maybe<&2, J()>, Space.blank(text), None{}, Some{unsignedThinking(text, allowEmptySignature)})

# Redacted thinking returns its opaque payload; an absent payload is omitted
# from the wire object, as JSON drops upstream's undefined `data`.
def redactedBlock(signature: Maybe<&2, String>) -> J():
  match signature:
    case Some{data}: obj(field("type", str("redacted_thinking")) <> field("data", str(data)) <> Nil{})
    case None{}: obj(field("type", str("redacted_thinking")) <> Nil{})

def thinkingBlock(text: String, signature: Maybe<&2, String>, redacted: Maybe<&2, Bool>, allowEmptySignature: Bool) -> Maybe<&2, J()>:
  match redacted:
    case Some{True{}}: Some{redactedBlock(signature)}
    case _: ordinaryThinking(text, signed(signature), allowEmptySignature)

def assistantBlock(block: T.AssistantContent<V.Value>, oauth: Bool, allowEmptySignature: Bool) -> Maybe<&2, J()>:
  match block:
    case T.AssistantText{T.TextContent{+text, _}}: Bool.pick(Maybe<&2, J()>, Space.blank(text), None{}, Some{textBlock(text)})
    case T.AssistantThinking{T.ThinkingContent{text, signature, redacted}}: thinkingBlock(text, signature, redacted, allowEmptySignature)
    case T.AssistantToolCall{T.ToolCall{id, name, arguments, _, _}}: Some{obj(field("type", str("tool_use")) <> field("id", str(id)) <> field("name", str(wireToolName(name, oauth))) <> field("input", Schema.toJson(arguments)) <> Nil{})}

def assistantBlocks(items: List<&2, T.AssistantContent<V.Value>>, +oauth: Bool, +allowEmptySignature: Bool) -> List<&2, J()>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: prependOptional(assistantBlock(item, oauth, allowEmptySignature), assistantBlocks(rest, oauth, allowEmptySignature))

def toolResult(-D: Data, result: T.ToolResultMessage<D>) -> J():
  match result:
    case T.ToolResultMessage{id, _, content, _, _, isError, _}:
      obj(field("type", str("tool_result")) <> field("tool_use_id", str(id)) <> field("content", convertContentBlocks(content)) <> field("is_error", bool(isError)) <> Nil{})

def toolReference(kind: String, name: String, oauth: Bool) -> J():
  obj(field("type", str(kind)) <> field("tool", obj(field("type", str("tool_reference")) <> field("name", str(wireToolName(name, oauth))) <> Nil{})) <> Nil{})

def removals(values: List<&2, T.ToolReference>, +oauth: Bool) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case T.ToolReference{name} <> rest: toolReference("tool_removal", name, oauth) <> removals(rest, oauth)

def additions(values: List<&2, T.Tool<V.Value>>, +oauth: Bool) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case T.Tool{name, _, _, _} <> rest: toolReference("tool_addition", name, oauth) <> additions(rest, oauth)

def listOf(-A: Data, value: Maybe<&2, List<&2, A>>) -> List<&2, A>: Maybe.default(&2, List<&2, A>, value, Nil{})

def toolChanges(system: T.SystemMessage<V.Value>, +oauth: Bool, native: Bool) -> List<&2, J()>:
  match native system:
    case False{} _: Nil{}
    case True{} T.SystemMessage{_, _, added, removed, _}: List.append(&2, J(), removals(listOf(T.ToolReference, removed), oauth), additions(listOf(T.Tool<V.Value>, added), oauth))

# A later system message: its rendered update and, with native tool changes,
# tool_removal/tool_addition blocks. Empty messages are dropped.
def systemMessage(+system: T.SystemMessage<V.Value>, oauth: Bool, native: Bool) -> Maybe<&2, J()>:
  +text = Text.renderUpdate(V.Value, system)
  +changes = toolChanges(system, oauth, native)
  +blocks = Bool.pick(List<&2, J()>, String.is_empty(text), changes, textBlock(text) <> changes)
  Bool.pick(Maybe<&2, J()>, List.is_empty(&2, J(), blocks), None{}, Some{wireMessage("system", T.JsonArray{blocks})})

# upstream convertMessages. Later system messages are held back until the next
# assistant message (or the end), since tool_result blocks must directly
# follow their tool_use. Consecutive tool results share one user message.
# Converted pairs each wire message with its historical effort, if any.
type Converted is Data:
  Converted{value: J(), level: Maybe<&2, String>}

type ConvertSettings is Data:
  ConvertSettings{oauth: Bool, allowEmptySignature: Bool, managedProvider: Maybe<&2, String>, native: Bool}

type ConvertState is Data:
  ConvertState{reversed: List<&2, Converted>, pending: List<&2, J()>, results: List<&2, J()>}

def plain(value: J()) -> Converted: Converted{value, None{}}

def flushResults(state: ConvertState) -> ConvertState:
  match state:
    case ConvertState{reversed, pending, Nil{}}: ConvertState{reversed, pending, Nil{}}
    case ConvertState{reversed, pending, results}: ConvertState{plain(wireMessage("user", T.JsonArray{results})) <> reversed, pending, Nil{}}

def pushAll(values: List<&2, J()>, reversed: List<&2, Converted>) -> List<&2, Converted>:
  match values:
    case Nil{}: reversed
    case value <> rest: pushAll(rest, plain(value) <> reversed)

def flushPending(state: ConvertState) -> ConvertState:
  match state:
    case ConvertState{reversed, pending, results}: ConvertState{pushAll(pending, reversed), Nil{}, results}

def pushConverted(state: ConvertState, value: Converted) -> ConvertState:
  match state:
    case ConvertState{reversed, pending, results}: ConvertState{value <> reversed, pending, results}

def pushOptional(state: ConvertState, value: Maybe<&2, J()>) -> ConvertState:
  match value:
    case None{}: state
    case Some{item}: pushConverted(state, plain(item))

def holdSystem(state: ConvertState, value: Maybe<&2, J()>) -> ConvertState:
  match state value:
    case current None{}: current
    case ConvertState{reversed, pending, results} Some{item}: ConvertState{reversed, List.append(&2, J(), pending, item <> Nil{}), results}

def appendResult(state: ConvertState, value: J()) -> ConvertState:
  match state:
    case ConvertState{reversed, pending, results}: ConvertState{reversed, pending, List.append(&2, J(), results, value <> Nil{})}

def managedLevel(managed: Maybe<&2, String>, +api: String, +provider: String, +level: Maybe<&2, String>) -> Maybe<&2, String>:
  match managed:
    case None{}: None{}
    case Some{name}: Bool.pick(Maybe<&2, String>, String.eq(api, "anthropic-messages") && String.eq(provider, name) && isAnthropicEffort(level), level, None{})

def assistantConverted(-G: Data, +message: T.AssistantMessage<V.Value, G>, settings: ConvertSettings) -> Maybe<&2, Converted>:
  match message settings:
    case T.AssistantMessage{content, api, provider, _, _, _, level, _, _, _, _, _, _, _, _} ConvertSettings{oauth, empty, managed, _}:
      +blocks = assistantBlocks(content, oauth, empty)
      Bool.pick(Maybe<&2, Converted>, List.is_empty(&2, J(), blocks), None{}, Some{Converted{obj(field("role", str("assistant")) <> field("content", T.JsonArray{blocks}) <> Nil{}), managedLevel(managed, api, provider, level)}})

def pushAssistant(state: ConvertState, value: Maybe<&2, Converted>) -> ConvertState:
  match value:
    case None{}: state
    case Some{item}: pushConverted(state, item)

def convertStep(-G: Data, -D: Data, state: ConvertState, message: T.Message<V.Value, V.Value, G, D>, +settings: ConvertSettings) -> ConvertState:
  match message settings:
    case T.ToolResult{result} _: appendResult(state, toolResult(D, result))
    case T.System{system} ConvertSettings{oauth, _, _, native}: holdSystem(flushResults(state), systemMessage(system, oauth, native))
    case T.User{T.UserMessage{content, _}} _: pushOptional(flushResults(state), userMessage(content))
    case T.Assistant{source} _: pushAssistant(flushPending(flushResults(state)), assistantConverted(G, source, settings))

def finishedConversion(state: ConvertState) -> List<&2, Converted>:
  match state:
    case ConvertState{reversed, _, _}: List.reverse(&2, Converted, reversed)

def convertLoop(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>, +settings: ConvertSettings, state: ConvertState) -> List<&2, Converted>:
  match messages:
    case Nil{}: finishedConversion(flushPending(flushResults(state)))
    case message <> rest: convertLoop(G, D, rest, settings, convertStep(G, D, state, message, settings))

# Cache the conversation: the last user or system message's last text, image,
# tool_result, tool_addition or tool_removal block; plain string content
# becomes one cached text block.
def cacheableBlock(+kind: Maybe<&2, J()>) -> Bool:
  match kind:
    case Some{T.JsonString{"text"}}: True{}
    case Some{T.JsonString{"image"}}: True{}
    case Some{T.JsonString{"tool_result"}}: True{}
    case Some{T.JsonString{"tool_addition"}}: True{}
    case Some{T.JsonString{"tool_removal"}}: True{}
    case _: False{}

def cacheBlock(value: J(), cache: J()) -> J():
  match value:
    case T.JsonObject{+fields}: Bool.pick(J(), cacheableBlock(R.get(J(), fields, "type")), T.JsonObject{put(fields, "cache_control", cache)}, T.JsonObject{fields})
    case other: other

def cacheLastBlock(values: List<&2, J()>, cache: J()) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case head <> Nil{}: cacheBlock(head, cache) <> Nil{}
    case head <> rest: head <> cacheLastBlock(rest, cache)

def cacheContent(value: Maybe<&2, J()>, cache: J()) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonString{text}}: Some{T.JsonArray{obj(field("type", str("text")) <> field("text", str(text)) <> field("cache_control", cache) <> Nil{}) <> Nil{}}}
    case Some{T.JsonArray{values}}: Some{T.JsonArray{cacheLastBlock(values, cache)}}
    case other: other

def cacheableRole(+role: Maybe<&2, J()>) -> Bool:
  match role:
    case Some{T.JsonString{"user"}}: True{}
    case Some{T.JsonString{"system"}}: True{}
    case _: False{}

def cacheMessage(value: J(), cache: J()) -> J():
  match value:
    case T.JsonObject{+fields}: Bool.pick(J(), cacheableRole(R.get(J(), fields, "role")), T.JsonObject{maybe(fields, "content", cacheContent(R.get(J(), fields, "content"), cache))}, T.JsonObject{fields})
    case other: other

def cacheConverted(value: Converted, cache: J()) -> Converted:
  match value:
    case Converted{wire, level}: Converted{cacheMessage(wire, cache), level}

def cacheLast(values: List<&2, Converted>, cache: Maybe<&2, J()>) -> List<&2, Converted>:
  match values cache:
    case items None{}: items
    case Nil{} _: Nil{}
    case head <> Nil{} Some{marker}: cacheConverted(head, marker) <> Nil{}
    case head <> rest Some{+marker}: head <> cacheLast(rest, Some{marker})

def convertMessages(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>, oauth: Bool, cache: Maybe<&2, J()>, allowEmptySignature: Bool, managedProvider: Maybe<&2, String>, native: Bool) -> List<&2, Converted>:
  cacheLast(convertLoop(G, D, messages, ConvertSettings{oauth, allowEmptySignature, managedProvider, native}, ConvertState{Nil{}, Nil{}, Nil{}}), cache)

def effortMarker(value: String) -> J():
  obj(field("role", str("system")) <> field("content", T.JsonArray{Nil{}}) <> field("output_config", obj(field("effort", str(value)) <> Nil{})) <> Nil{})

def wireMessages(values: List<&2, Converted>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case Converted{value, _} <> rest: value <> wireMessages(rest)

# Tools
# -----
def jsonField(value: J(), name: String) -> Maybe<&2, J()>:
  match value:
    case T.JsonObject{fields}: R.get(J(), fields, name)
    case _: None{}

def legacyInputSchema(+parameters: J()) -> Fields():
  R.Record{field("type", str("object")) <> field("properties", Maybe.default(&2, J(), jsonField(parameters, "properties"), obj(Nil{}))) <> field("required", Maybe.default(&2, J(), jsonField(parameters, "required"), T.JsonArray{Nil{}})) <> Nil{}}

def overlay(entries: List<&2, R.Property<J()>>, fields: Fields()) -> Fields():
  match entries:
    case Nil{}: fields
    case R.Property{name, value} <> rest: overlay(rest, put(fields, name, value))

def fieldsOf(value: J()) -> Fields():
  match value:
    case T.JsonObject{fields}: fields
    case _: R.new(J())

# Only strict tools send their full schema, spread under the legacy object
# schema's type/properties/required.
def inputSchema(+parameters: J(), strict: Bool) -> J():
  +legacy = legacyInputSchema(parameters)
  Bool.pick(J(), strict, T.JsonObject{overlay(R.entries(J(), legacy), fieldsOf(parameters))}, T.JsonObject{legacy})

def isTrue(value: Maybe<&2, Bool>) -> Bool:
  match value:
    case Some{True{}}: True{}
    case _: False{}

def toolWire(name: String, description: String, +strict: Bool, parameters: J(), oauth: Bool, eager: Bool, cache: Maybe<&2, J()>) -> J():
  +withEager = Bool.pick(List<&2, R.Property<J()>>, eager, field("eager_input_streaming", bool(True{})) <> Nil{}, Nil{})
  +withStrict = Bool.pick(List<&2, R.Property<J()>>, strict, field("strict", bool(True{})) <> Nil{}, Nil{})
  T.JsonObject{maybe(R.Record{List.concat(&2, R.Property<J()>, (field("name", str(wireToolName(name, oauth))) <> field("description", str(description)) <> Nil{}) <> withEager <> withStrict <> (field("input_schema", inputSchema(parameters, strict)) <> Nil{}) <> Nil{})}, "cache_control", cache)}

type ToolParameters is Data:
  ToolParameters{strict: Bool, parameters: J()}

def selectedParameters(strict: Bool, parameters: Result<&2, &2, Sampling.Error, V.Value>) -> Result<&2, &2, Sampling.Error, ToolParameters>:
  match parameters:
    case Fail{error}: Fail{error}
    case Done{value}: Done{ToolParameters{strict, Schema.toJson(value)}}

def toolParameters(+tool: T.Tool<V.Value>, strict: Result<&2, &2, Sampling.Error, Maybe<&2, Bool>>) -> Result<&2, &2, Sampling.Error, ToolParameters>:
  match strict:
    case Fail{error}: Fail{error}
    case Done{+selected}: selectedParameters(isTrue(selected), Sampling.getJsonSchemaToolParameters(tool, selected))

def wiredTool(tool: T.Tool<V.Value>, oauth: Bool, eager: Bool, cache: Maybe<&2, J()>, parameters: Result<&2, &2, Sampling.Error, ToolParameters>) -> Result<&2, &2, Sampling.Error, J()>:
  match parameters tool:
    case Fail{error} _: Fail{error}
    case Done{ToolParameters{strict, schema}} T.Tool{name, description, _, _}: Done{toolWire(name, description, strict, schema, oauth, eager, cache)}

def convertTool(+tool: T.Tool<V.Value>, oauth: Bool, eager: Bool, strictSupport: Bool, cache: Maybe<&2, J()>) -> Result<&2, &2, Sampling.Error, J()>:
  wiredTool(tool, oauth, eager, cache, toolParameters(tool, Sampling.resolveJsonSchemaStrictSampling(tool, strictSupport)))

def consTool(head: Result<&2, &2, Sampling.Error, J()>, rest: Result<&2, &2, Sampling.Error, List<&2, J()>>) -> Result<&2, &2, Sampling.Error, List<&2, J()>>:
  match head rest:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{value} Done{values}: Done{value <> values}

# upstream convertTools: the cache marker goes on the last tool.
def convertTools(tools: List<&2, T.Tool<V.Value>>, +oauth: Bool, +eager: Bool, +strictSupport: Bool, +cache: Maybe<&2, J()>) -> Result<&2, &2, Sampling.Error, List<&2, J()>>:
  match tools:
    case Nil{}: Done{Nil{}}
    case tool <> Nil{}: consTool(convertTool(tool, oauth, eager, strictSupport, cache), Done{Nil{}})
    case tool <> rest: consTool(convertTool(tool, oauth, eager, strictSupport, None{}), convertTools(rest, oauth, eager, strictSupport, cache))

def deferred(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case T.JsonObject{fields} <> rest: T.JsonObject{put(fields, "defer_loading", bool(True{}))} <> deferred(rest)
    case other <> rest: other <> deferred(rest)

# Anthropic adds hidden scaffolding once any tool defers loading; declaring
# this never-activated placeholder from the first request keeps it cached.
def deferredToolPlaceholder() -> J():
  obj(field("name", str("__pi_deferred_placeholder__")) <> field("description", str("Reserved placeholder. Never available. Never call this.")) <> field("input_schema", obj(field("type", str("object")) <> field("properties", obj(Nil{})) <> field("required", T.JsonArray{Nil{}}) <> Nil{})) <> field("defer_loading", bool(True{})) <> Nil{})

def named(-P: Data, tools: List<&2, T.Tool<P>>, +name: String) -> Bool:
  match tools:
    case Nil{}: False{}
    case T.Tool{toolName, _, _, _} <> rest: String.eq(toolName, name) || named(P, rest, name)

def laterTools(declared: List<&2, T.Tool<V.Value>>, +initial: List<&2, T.Tool<V.Value>>) -> List<&2, T.Tool<V.Value>>:
  match declared:
    case Nil{}: Nil{}
    case T.Tool{+name, description, parameters, sampling} <> rest:
      +tail = laterTools(rest, initial)
      Bool.pick(List<&2, T.Tool<V.Value>>, named(V.Value, initial, name), tail, T.Tool{name, description, parameters, sampling} <> tail)

def nativeTools(initial: Result<&2, &2, Sampling.Error, List<&2, J()>>, later: Result<&2, &2, Sampling.Error, List<&2, J()>>) -> Result<&2, &2, Sampling.Error, List<&2, J()>>:
  match initial later:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{first} Done{rest}: Done{List.append(&2, J(), first, deferredToolPlaceholder() <> deferred(rest))}

# Beta features
# -------------
def fineGrainedToolStreamingBeta() -> String: "fine-grained-tool-streaming-2025-05-14"

def interleavedThinkingBeta() -> String: "interleaved-thinking-2025-05-14"

def serverSideFallbackBeta() -> String: "server-side-fallback-2026-07-01"

def midConversationOutputConfigBeta() -> String: "mid-conversation-output-config-2026-07-01"

def thinkingBindingControlsBeta() -> String: "thinking-binding-controls-2026-08-01"

def midConversationToolChangesBeta() -> String: "mid-conversation-tool-changes-2026-07-01"

def member(values: List<&2, String>, +value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case item <> rest: String.eq(item, value) || member(rest, value)

def nonemptyFeatures(values: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest:
      +feature = Space.trim(value)
      +tail = nonemptyFeatures(rest)
      Bool.pick(List<&2, String>, String.is_empty(feature), tail, feature <> tail)

# The last anthropic-beta header among model then option headers configures
# the features: null disables them, a string replaces them.
def configuredIn(entries: List<&2, R.Property<T.Nullable<String>>>, found: Maybe<&2, T.Nullable<String>>) -> Maybe<&2, T.Nullable<String>>:
  match entries:
    case Nil{}: found
    case R.Property{name, value} <> rest: configuredIn(rest, Bool.pick(Maybe<&2, T.Nullable<String>>, String.eq(Case.lower(name), "anthropic-beta"), Some{value}, found))

def modelHeaders(model: T.Model<J()>) -> Maybe<&2, R.Record<String>>:
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, headers, _}: headers

def configuredFeatures(model: T.Model<J()>, headers: Maybe<&2, T.ProviderHeaders()>) -> Maybe<&2, T.Nullable<String>>:
  +fromModel = configuredIn(R.entries(T.Nullable<String>, HeaderUtils.fromRecord(Maybe.default(&2, R.Record<String>, modelHeaders(model), R.new(String)))), None{})
  configuredIn(R.entries(T.Nullable<String>, Maybe.default(&2, T.ProviderHeaders(), headers, R.new(T.Nullable<String>))), fromModel)

def when(condition: Bool, values: List<&2, String>) -> List<&2, String>: Bool.pick(List<&2, String>, condition, values, Nil{})

def defaultFeatures(+model: T.Model<J()>, +hasTools: Bool, oauth: Bool, native: Bool, thinkingEnabled: Maybe<&2, Bool>, interleaved: Maybe<&2, Bool>) -> List<&2, String>:
  +interleavedWanted = T.modelReasoning(model) && isTrue(thinkingEnabled) && optionalBool(interleaved, True{}) && Bool.not(forceAdaptiveThinking(model))
  List.concat(&2, String, when(oauth, "claude-code-20250219" <> "oauth-2025-04-20" <> Nil{}) <> when(hasTools && Bool.not(compatEager(getAnthropicCompat(model))), fineGrainedToolStreamingBeta() <> Nil{}) <> when(interleavedWanted, interleavedThinkingBeta() <> Nil{}) <> when(Bool.not(List.is_empty(&2, T.AnthropicAllowedFallbackModel, allowedFallbackModels(model))), serverSideFallbackBeta() <> Nil{}) <> when(supportsMidConvoEffort(model), midConversationOutputConfigBeta() <> thinkingBindingControlsBeta() <> Nil{}) <> when(native, midConversationToolChangesBeta() <> Nil{}) <> Nil{})

def within(+code: U32, low: U32, high: U32) -> Bool: U32.is_ge(code, low) && U32.is_le(code, high)

# buildParams
# -----------
def normalizeChar(+char: Char) -> Char:
  +code = Char.to_u32(char)
  +word = within(code, 97, 122) || within(code, 65, 90) || within(code, 48, 57) || U32.is_eq(code, 95) || U32.is_eq(code, 45)
  Bool.pick(Char, word, char, '_')

def normalizeChars(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{char, rest}: SCon{normalizeChar(char), normalizeChars(rest)}

# Anthropic's tool call id pattern and length. JavaScript slices UTF-16 code
# units; every surviving character is ASCII, and each replaced character
# (even a surrogate pair's two units) becomes one "_" per code unit.
def normalizeUnits(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{+char, rest}:
      +tail = normalizeUnits(rest)
      Bool.pick(String, U32.is_ge(Char.to_u32(char), 65536), SCon{'_', SCon{'_', tail}}, SCon{normalizeChar(char), tail})

def normalizeToolCallId(id: String) -> String: String.take(normalizeUnits(id), 64n)

def normalizeInput(-A: Data, -G: Data, -M: Data, unused: Unit, input: Transform.NormalizeToolCallIdInput<A, G, M>) -> IO(Result<&2, &2, Sampling.Error, String>):
  match input:
    case Transform.NormalizeToolCallIdInput{id, _, _}: IO.pure(Result<&2, &2, Sampling.Error, String>, Done{normalizeToolCallId(id)})

def dropInitial(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>, initial: Bool) -> List<&2, T.Message<V.Value, V.Value, G, D>>:
  match initial messages:
    case True{} _ <> rest: rest
    case _ values: values

def initialTools(initial: Maybe<&2, T.SystemMessage<V.Value>>) -> List<&2, T.Tool<V.Value>>:
  match initial:
    case Some{T.SystemMessage{_, _, Some{tools}, _, _}}: tools
    case _: Nil{}

def systemText(initial: Maybe<&2, T.SystemMessage<V.Value>>) -> String:
  match initial:
    case None{}: ""
    case Some{system}: Text.renderComplete(V.Value, system)

def systemBlock(text: String, cache: Maybe<&2, J()>) -> J():
  T.JsonObject{maybe(R.Record{field("type", str("text")) <> field("text", str(text)) <> Nil{}}, "cache_control", cache)}

# OAuth requests must lead with Claude Code's identity.
def systemPrompt(text: String, oauth: Bool, +cache: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match text oauth:
    case SNil{} False{}: None{}
    case SNil{} True{}: Some{T.JsonArray{systemBlock("You are Claude Code, Anthropic's official CLI for Claude.", cache) <> Nil{}}}
    case SCon{c, cs} False{}: Some{T.JsonArray{systemBlock(Unicode.sanitizeSurrogates(SCon{c, cs}), cache) <> Nil{}}}
    case SCon{c, cs} True{}: Some{T.JsonArray{systemBlock("You are Claude Code, Anthropic's official CLI for Claude.", cache) <> systemBlock(Unicode.sanitizeSurrogates(SCon{c, cs}), cache) <> Nil{}}}

def nullMapping(value: Maybe<&2, T.Nullable<String>>) -> Bool:
  match value:
    case Some{T.NullValue{}}: True{}
    case _: False{}

def offMapped(model: T.Model<J()>) -> Bool:
  match model:
    case T.Model{_, _, _, _, _, _, levels, _, _, _, _, _, _, _, _, _}: nullMapping(Levels.mapped(levels, T.Off{}))

def adaptive(display: String) -> J(): obj(field("type", str("adaptive")) <> field("display", str(display)) <> Nil{})

def effortConfig(value: String) -> J(): obj(field("effort", str(value)) <> Nil{})

def budget(value: Maybe<&2, F64>) -> F64:
  match value:
    case Some{+tokens}: Bool.pick(F64, F.isEqual(F.compare(tokens, F.fromU32(0))) || F.isNaN(tokens), F.fromU32(1024), tokens)
    case None{}: F.fromU32(1024)

type ThinkingFields is Data:
  ThinkingFields{thinking: Maybe<&2, J()>, outputConfig: Maybe<&2, J()>}

def noThinking() -> ThinkingFields: ThinkingFields{None{}, None{}}

def enabledKind(forced: Bool, display: String, effort: Maybe<&2, String>, tokens: Maybe<&2, F64>) -> ThinkingFields:
  match forced:
    case True{}: ThinkingFields{Some{adaptive(display)}, Maybe.map(&2, String, J(), effortConfig, effort)}
    case False{}: ThinkingFields{Some{obj(field("type", str("enabled")) <> field("budget_tokens", num(budget(tokens))) <> field("display", str(display)) <> Nil{})}, None{}}

def enabledThinking(+model: T.Model<J()>, display: String, effort: Maybe<&2, String>, tokens: Maybe<&2, F64>) -> ThinkingFields:
  enabledKind(forceAdaptiveThinking(model), display, effort, tokens)

def reasoningThinking(+model: T.Model<J()>, enabled: Maybe<&2, Bool>, display: String, effort: Maybe<&2, String>, tokens: Maybe<&2, F64>) -> ThinkingFields:
  match enabled:
    case Some{True{}}: enabledThinking(model, display, effort, tokens)
    case Some{False{}}: Bool.pick(ThinkingFields, offMapped(model), noThinking(), ThinkingFields{Some{obj(field("type", str("disabled")) <> Nil{})}, None{}})
    case None{}: noThinking()

def thinkingKind(model: T.Model<J()>, managed: Bool, reasoning: Bool, enabled: Maybe<&2, Bool>, +display: String, effort: Maybe<&2, String>, tokens: Maybe<&2, F64>) -> ThinkingFields:
  match managed reasoning:
    case True{} _: ThinkingFields{Some{obj(field("type", str("adaptive")) <> field("display", str(display)) <> field("block_binding", obj(field("prefix_mismatch_behavior", str("drop_block")) <> Nil{})) <> Nil{})}, Some{effortConfig("high")}}
    case False{} True{}: reasoningThinking(model, enabled, display, effort, tokens)
    case False{} False{}: noThinking()

# Managed-effort models always use adaptive thinking that drops mismatched
# prefix blocks; the conversation's effort markers carry the active effort.
def thinkingFields(+model: T.Model<J()>, enabled: Maybe<&2, Bool>, display: String, effort: Maybe<&2, String>, tokens: Maybe<&2, F64>) -> ThinkingFields:
  thinkingKind(model, supportsMidConvoEffort(model), T.modelReasoning(model), enabled, display, effort, tokens)

def choiceValue(value: AnthropicToolChoice) -> J():
  match value:
    case ChoiceAuto{}: obj(field("type", str("auto")) <> Nil{})
    case ChoiceAny{}: obj(field("type", str("any")) <> Nil{})
    case ChoiceNone{}: obj(field("type", str("none")) <> Nil{})
    case ChoiceTool{name}: obj(field("type", str("tool")) <> field("name", str(name)) <> Nil{})

def userId(value: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonString{id}}: Some{obj(field("user_id", str(id)) <> Nil{})}
    case _: None{}

def metadataValue(value: Maybe<&2, R.Record<J()>>) -> Maybe<&2, J()>:
  match value:
    case Some{fields}: userId(R.get(J(), fields, "user_id"))
    case None{}: None{}

def fallbackValues(values: List<&2, T.AnthropicAllowedFallbackModel>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case T.AnthropicAllowedFallbackModel{_, model, _} <> rest: obj(field("model", str(model)) <> Nil{}) <> fallbackValues(rest)

def optionalList(values: List<&2, J()>) -> Maybe<&2, J()>:
  match values:
    case Nil{}: None{}
    case items: Some{T.JsonArray{items}}

def strings(values: List<&2, String>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: str(value) <> strings(rest)

# Temperature is incompatible with extended thinking, managed effort and
# models that reject it.
def temperatureValue(value: Maybe<&2, F64>, enabled: Maybe<&2, Bool>, +managed: Bool, supported: Bool) -> Maybe<&2, J()>:
  Bool.pick(Maybe<&2, J()>, Bool.not(isTrue(enabled)) && Bool.not(managed) && supported, Maybe.map(&2, F64, J(), num, value), None{})

# What buildParams derives before assembling the payload.
type Plan is Data:
  Plan{cache: Maybe<&2, J()>, messages: List<&2, J()>, tools: Maybe<&2, J()>, betas: List<&2, String>}

def withThinkingFields(fields: Fields(), thought: ThinkingFields) -> Fields():
  match thought:
    case ThinkingFields{thinking, output}: maybe(maybe(fields, "thinking", thinking), "output_config", output)

def paramsFrom(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, -Client: Data, +model: T.Model<J()>, +initial: Maybe<&2, T.SystemMessage<V.Value>>, oauth: Bool, options: AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>, plan: Plan) -> J():
  match options plan:
    case AnthropicOptions{T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, temperature, _, maxTokens, _, _, _, _, metadata}, +enabled, tokens, effort, display, _, choice, _} Plan{+cache, messages, tools, betas}:
      +compat = getAnthropicCompat(model)
      +managed = supportsMidConvoEffort(model)
      +selectedDisplay = displayName(Maybe.default(&2, AnthropicThinkingDisplay, display, Summarized{}))
      +base = {R.Record{field("model", str(T.modelId(model))) <> field("messages", T.JsonArray{messages}) <> field("max_tokens", num(Maybe.default(&2, F64, maxTokens, T.modelMaxTokens(model)))) <> field("stream", bool(True{})) <> Nil{}} : Fields()}
      +withBetas = maybe(base, "betas", optionalList(strings(betas)))
      +withSystem = maybe(withBetas, "system", systemPrompt(systemText(initial), oauth, cache))
      +withTemperature = maybe(withSystem, "temperature", temperatureValue(temperature, enabled, managed, compatTemperature(compat)))
      +withTools = maybe(withTemperature, "tools", tools)
      +withThinking = withThinkingFields(withTools, thinkingFields(model, enabled, selectedDisplay, effort, tokens))
      +withMetadata = maybe(withThinking, "metadata", metadataValue(metadata))
      +withChoice = maybe(withMetadata, "tool_choice", Maybe.map(&2, AnthropicToolChoice, J(), choiceValue, choice))
      T.JsonObject{maybe(withChoice, "fallbacks", optionalList(fallbackValues(allowedFallbackModels(model))))}

def requestHeaders(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, -Client: Data, options: AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>) -> Maybe<&2, T.ProviderHeaders()>:
  match options:
    case AnthropicOptions{T.StreamOptions{_, _, _, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _}: headers

def thinkingOptions(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, -Client: Data, options: AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>) -> Maybe<&2, Bool> & Maybe<&2, Bool>:
  match options:
    case AnthropicOptions{_, enabled, _, _, _, interleaved, _, _}: (enabled, interleaved)

def activeEffort(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, -Client: Data, options: AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>) -> String:
  match options:
    case AnthropicOptions{_, _, _, effort, _, _, _, _}: Maybe.default(&2, String, effort, "high")

# upstream insertThinkingLevelMessages: each historical effort precedes its
# assistant message, and the active effort ends the list.
def insertThinkingLevelMessages(values: List<&2, Converted>, activeEffort: String) -> List<&2, J()>:
  match values:
    case Nil{}: effortMarker(activeEffort) <> Nil{}
    case Converted{value, None{}} <> rest: value <> insertThinkingLevelMessages(rest, activeEffort)
    case Converted{value, Some{level}} <> rest: effortMarker(level) <> value <> insertThinkingLevelMessages(rest, activeEffort)

def optionsRetention(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, -Client: Data, options: AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>) -> Maybe<&2, T.CacheRetention> & Maybe<&2, T.ProviderEnv()>:
  match options:
    case AnthropicOptions{T.StreamOptions{_, _, _, _, env, _, _, _, _, _, _, _, _, _, _, retention, _, _, _}, _, _, _, _, _, _, _}: (retention, env)

def modelProviderName(model: T.Model<J()>) -> String: T.modelProvider(model)

def redefinitionsOf(result: Declaration.DeclarationResult<Bool>) -> Result<&2, &2, String, Bool>:
  match result:
    case Declaration.Success{value}: Done{value}
    case Declaration.Failure{_}: Fail{"Could not compare tool declarations"}

def nativeList(result: Result<&2, &2, Sampling.Error, List<&2, J()>>) -> Result<&2, &2, Sampling.Error, Maybe<&2, J()>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{values}: Done{Some{T.JsonArray{values}}}

def currentList(result: Result<&2, &2, Sampling.Error, List<&2, J()>>) -> Result<&2, &2, Sampling.Error, Maybe<&2, J()>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{values}: Done{optionalList(values)}

def toolListWith(native: Bool, +initial: List<&2, T.Tool<V.Value>>, declared: List<&2, T.Tool<V.Value>>, current: List<&2, T.Tool<V.Value>>, +oauth: Bool, +compat: AnthropicCompat, +toolCache: Maybe<&2, J()>) -> Result<&2, &2, Sampling.Error, Maybe<&2, J()>>:
  match native:
    case True{}: nativeList(nativeTools(convertTools(initial, oauth, compatEager(compat), compatStrictTools(compat), toolCache), convertTools(laterTools(declared, initial), oauth, compatEager(compat), compatStrictTools(compat), None{})))
    case False{}: currentList(convertTools(current, oauth, compatEager(compat), compatStrictTools(compat), toolCache))

def toolList(native: Bool, +initial: List<&2, T.Tool<V.Value>>, declared: List<&2, T.Tool<V.Value>>, current: List<&2, T.Tool<V.Value>>, +oauth: Bool, +compat: AnthropicCompat, cache: Maybe<&2, J()>) -> Result<&2, &2, Sampling.Error, Maybe<&2, J()>>:
  toolListWith(native, initial, declared, current, oauth, compat, Bool.pick(Maybe<&2, J()>, compatToolCache(compat), cache, None{}))

def planned(+messages: List<&2, J()>, tools: Result<&2, &2, Sampling.Error, Maybe<&2, J()>>, cache: Maybe<&2, J()>, betas: List<&2, String>) -> Result<&2, &2, String, Plan>:
  match tools:
    case Fail{error}: Fail{Sampling.errorMessage(error)}
    case Done{value}: Done{Plan{cache, messages, value, betas}}

def withPlan(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, -Client: Data, model: T.Model<J()>, initial: Maybe<&2, T.SystemMessage<V.Value>>, oauth: Bool, options: AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>, plan: Result<&2, &2, String, Plan>) -> Result<&2, &2, String, J()>:
  match plan:
    case Fail{message}: Fail{message}
    case Done{value}: Done{paramsFrom(Signal, Telemetry, Fetch, Error, Client, model, initial, oauth, options, value)}

def contextMessages(-G: Data, -D: Data, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> List<&2, T.Message<V.Value, V.Value, G, D>>:
  match context:
    case T.TranscriptContext{messages}: messages

# streamSimple
# ------------
def levelName(level: T.ThinkingLevel) -> String:
  match level:
    case T.Minimal{}: "minimal"
    case T.Low{}: "low"
    case T.Medium{}: "medium"
    case T.High{}: "high"
    case T.XHigh{}: "xhigh"
    case T.Max{}: "max"

def defaultEffort(level: T.ThinkingLevel) -> String:
  match level:
    case T.Minimal{}: "low"
    case T.Low{}: "low"
    case T.Medium{}: "medium"
    case T.High{}: "high"
    case _: "high"

def mappedEffort(value: Maybe<&2, T.Nullable<String>>, level: T.ThinkingLevel) -> String:
  match value:
    case Some{T.PresentValue{effort}}: effort
    case _: defaultEffort(level)

# upstream mapThinkingLevelToEffort: a mapped string wins; otherwise the level
# maps to its effort, with xhigh and max falling back to high.
def mapThinkingLevelToEffort(model: T.Model<J()>, +level: T.ThinkingLevel) -> String:
  match model:
    case T.Model{_, _, _, _, _, _, levels, _, _, _, _, _, _, _, _, _}: mappedEffort(Levels.mapped(levels, T.Thinking{level}), level)

def simpleChoice(value: T.ToolChoice) -> AnthropicToolChoice:
  match value:
    case T.AutoTool{}: ChoiceAuto{}
    case T.NoTool{}: ChoiceNone{}

def baseMaxTokens(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>) -> Maybe<&2, F64>:
  match base:
    case T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, maxTokens, _, _, _, _, _}: maxTokens

def withMaxTokens(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, value: F64) -> T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>:
  match base:
    case T.StreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, _, transport, cache, session, ws, metadata}:
      T.StreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, Some{value}, transport, cache, session, ws, metadata}

def allocated(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, ~Client: Data, model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, AnthropicToolChoice>, allocation: Simple.ThinkingTokenAllocation) -> AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>:
  match allocation:
    case Simple.ThinkingTokenAllocation{adjusted, thinkingBudget}:
      +maxTokens = Simple.clampMaxTokensToContext(~G, ~D, ~J(), model, context, adjusted)
      AnthropicOptions{withMaxTokens(Signal, Telemetry, Fetch, Error, base, maxTokens), Some{True{}}, Some{F.minimum(thinkingBudget, F.maximum(F.fromU32(0), F.subtract(maxTokens, F.fromU32(1024))))}, None{}, None{}, None{}, choice, None{}}

def budgeted(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, ~Client: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, AnthropicToolChoice>, level: T.ThinkingLevel, budgets: Maybe<&2, T.ThinkingBudgets>) -> AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>:
  allocated(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, ~Client, model, context, base, choice, Simple.adjustMaxTokensForThinking(baseMaxTokens(Signal, Telemetry, Fetch, Error, base), T.modelMaxTokens(model), level, budgets))

def leveled(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, ~Client: Data, forced: Bool, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, AnthropicToolChoice>, level: T.ThinkingLevel, budgets: Maybe<&2, T.ThinkingBudgets>) -> AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>:
  match forced:
    case True{}: AnthropicOptions{base, Some{True{}}, None{}, Some{mapThinkingLevelToEffort(model, level)}, None{}, None{}, choice, None{}}
    case False{}: budgeted(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, ~Client, model, context, base, choice, level, budgets)

def simpleThinking(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, ~Client: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, AnthropicToolChoice>, reasoning: Maybe<&2, T.ThinkingLevel>, budgets: Maybe<&2, T.ThinkingBudgets>) -> AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>:
  match reasoning:
    case None{}: AnthropicOptions{base, Some{False{}}, None{}, None{}, None{}, None{}, choice, None{}}
    case Some{level}: leveled(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, ~Client, forceAdaptiveThinking(model), model, context, base, choice, level, budgets)

def simpleKey(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Maybe<&2, String>:
  match options:
    case None{}: None{}
    case Some{T.SimpleStreamOptions{_, _, key, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: key

def simpleOptionsWith(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, ~Client: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>:
  match options:
    case None{}: simpleThinking(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, ~Client, model, context, base, None{}, None{}, None{})
    case Some{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, choice, reasoning, _, budgets}}:
      simpleThinking(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, ~Client, model, context, base, Maybe.map(&2, T.ToolChoice, AnthropicToolChoice, simpleChoice, choice), reasoning, budgets)

def simpleHeaders(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Maybe<&2, T.ProviderHeaders()>:
  match options:
    case None{}: None{}
    case Some{T.SimpleStreamOptions{_, _, _, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: headers

def authorizedOptions(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, ~Client: Data, authorized: Bool, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Result<&2, &2, String, AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>>:
  match authorized:
    case False{}: Fail{"No API key for provider: " ++ T.modelProvider(model)}
    case True{}: Done{simpleOptionsWith(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, ~Client, model, context, Simple.buildBaseOptions(~G, ~D, ~J(), ~Signal, ~Telemetry, ~Fetch, ~Error, model, context, options, simpleKey(Signal, Telemetry, Fetch, Error, options)), options)}

# upstream mapStopReason; an unknown reason is an error message.
type StopMapping is Data:
  StopMapping{stopReason: T.StopReason, errorMessage: Maybe<&2, String>}

def refusal(explanation: Maybe<&2, String>) -> Maybe<&2, String>:
  match explanation:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: Some{"The model refused to complete the request"}

def mapStopReason(reason: String, explanation: Maybe<&2, String>) -> Result<&2, &2, String, StopMapping>:
  match reason:
    case "end_turn": Done{StopMapping{T.Stop{}, None{}}}
    case "max_tokens": Done{StopMapping{T.Length{}, None{}}}
    case "tool_use": Done{StopMapping{T.ToolUse{}, None{}}}
    case "refusal": Done{StopMapping{T.Error{}, refusal(explanation)}}
    case "pause_turn": Done{StopMapping{T.Stop{}, None{}}}
    case "stop_sequence": Done{StopMapping{T.Stop{}, None{}}}
    case "sensitive": Done{StopMapping{T.Error{}, Some{"Provider stopped with: sensitive"}}}
    case other: Fail{"Unhandled stop reason: " ++ other}

# createClient
# ------------
def isOAuthToken(key: String) -> Bool: String.contains(key, "sk-ant-oat")

type ClientAuth is Data:
  ApiKeyAuth{key: Maybe<&2, String>}
  BearerAuth{token: Maybe<&2, String>}

# upstream createClient: the client's authentication, its default headers (the
# pi User-Agent first, later sources overriding), and whether OAuth shaping
# applies. Copilot uses bearer auth; an OAuth token adds Claude Code identity;
# other keys send session affinity when the model asks for it.
type CreatedClient is Data:
  CreatedClient{auth: ClientAuth, headers: T.ProviderHeaders(), isOAuthToken: Bool}

def presentFields(fields: List<&2, R.Property<String>>) -> T.ProviderHeaders(): HeaderUtils.fromRecord(R.Record{fields})

def mergeHeaders(sources: List<&2, Maybe<&2, T.ProviderHeaders()>>, merged: T.ProviderHeaders()) -> T.ProviderHeaders():
  match sources:
    case Nil{}: merged
    case source <> rest: mergeHeaders(rest, HeaderUtils.overlay(merged, source))

def mergeClientHeaders(agent: String, sources: List<&2, Maybe<&2, T.ProviderHeaders()>>) -> T.ProviderHeaders():
  mergeHeaders(sources, presentFields(R.Property{"User-Agent", agent} <> Nil{}))

def browserHeaders() -> List<&2, R.Property<String>>:
  R.Property{"accept", "application/json"} <> R.Property{"anthropic-dangerous-direct-browser-access", "true"} <> Nil{}

def fromStrings(value: Maybe<&2, R.Record<String>>) -> Maybe<&2, T.ProviderHeaders()>: Maybe.map(&2, R.Record<String>, T.ProviderHeaders(), HeaderUtils.fromRecord, value)

def affinityHeaderName(format: Maybe<&2, T.AnthropicSessionAffinityFormat>) -> String:
  match format:
    case Some{T.AnthropicOpenRouterSession{}}: "x-session-id"
    case None{}: "x-session-affinity"

def affinityFor(header: String, sessionId: Maybe<&2, String>, send: Bool) -> T.ProviderHeaders():
  match sessionId send:
    case Some{SCon{c, cs}} True{}: presentFields(R.Property{header, SCon{c, cs}} <> Nil{})
    case _ _: R.new(T.Nullable<String>)

def affinityHeaders(+compat: AnthropicCompat, sessionId: Maybe<&2, String>) -> T.ProviderHeaders():
  affinityFor(affinityHeaderName(compatAffinityFormat(compat)), sessionId, compatSendAffinity(compat))

def oauthKey(apiKey: Maybe<&2, String>) -> Bool:
  match apiKey:
    case Some{key}: isOAuthToken(key)
    case None{}: False{}

def clientFor(+model: T.Model<J()>, agent: String, apiKey: Maybe<&2, String>, optionsHeaders: Maybe<&2, T.ProviderHeaders()>, dynamicHeaders: Maybe<&2, R.Record<String>>, sessionId: Maybe<&2, String>, copilot: Bool, oauth: Bool) -> CreatedClient:
  match copilot oauth:
    case True{} _: CreatedClient{BearerAuth{apiKey}, mergeClientHeaders(agent, Some{presentFields(browserHeaders())} <> fromStrings(modelHeaders(model)) <> fromStrings(dynamicHeaders) <> optionsHeaders <> Nil{}), False{}}
    case False{} True{}: CreatedClient{BearerAuth{apiKey}, mergeClientHeaders(agent, Some{presentFields(List.append(&2, R.Property<String>, browserHeaders(), R.Property{"user-agent", "claude-cli/" ++ claudeCodeVersion()} <> R.Property{"x-app", "cli"} <> Nil{}))} <> fromStrings(modelHeaders(model)) <> optionsHeaders <> Nil{}), True{}}
    case False{} False{}: CreatedClient{ApiKeyAuth{apiKey}, mergeClientHeaders(agent, Some{presentFields(browserHeaders())} <> Some{affinityHeaders(getAnthropicCompat(model), sessionId)} <> fromStrings(modelHeaders(model)) <> optionsHeaders <> Nil{}), False{}}

def createClient(+model: T.Model<J()>, agent: String, +apiKey: Maybe<&2, String>, optionsHeaders: Maybe<&2, T.ProviderHeaders()>, dynamicHeaders: Maybe<&2, R.Record<String>>, sessionId: Maybe<&2, String>) -> CreatedClient:
  clientFor(model, agent, apiKey, optionsHeaders, dynamicHeaders, sessionId, String.eq(T.modelProvider(model), "github-copilot"), oauthKey(apiKey))

# upstream assertRequestAuth: an API key, or a nonblank authorization,
# x-api-key or cf-aig-authorization header.
def hasRequestAuth(apiKey: Maybe<&2, String>, +headers: Maybe<&2, T.ProviderHeaders()>) -> Bool:
  match apiKey:
    case Some{SCon{_, _}}: True{}
    case _: HeaderUtils.hasHeader(headers, "authorization") || HeaderUtils.hasHeader(headers, "x-api-key") || HeaderUtils.hasHeader(headers, "cf-aig-authorization")

# upstream streamSimple's AnthropicOptions: missing auth fails before a stream
# exists (upstream throws synchronously); otherwise the shared base options
# and tool choice; without a reasoning level thinking is disabled;
# forced-adaptive models get an effort; others a budget fitted under the
# response ceiling.
def streamSimpleOptions(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, ~Client: Data, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Result<&2, &2, String, AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>>:
  authorizedOptions(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, ~Client, hasRequestAuth(simpleKey(Signal, Telemetry, Fetch, Error, options), simpleHeaders(Signal, Telemetry, Fetch, Error, options)), model, context, options)

def remember(duplicate: Bool, value: String, seen: List<&2, String>) -> List<&2, String>:
  match duplicate:
    case True{}: seen
    case False{}: value <> seen

# Distinct values in first-occurrence order (a JavaScript Set's order);
# `seen` holds the kept values in reverse.
def distinct(values: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: List.reverse(&2, String, seen)
    case +value <> rest: distinct(rest, remember(member(seen, value), value, seen))

def getBetaFeaturesWith(configured: Maybe<&2, T.Nullable<String>>, defaults: List<&2, String>) -> List<&2, String>:
  match configured:
    case Some{T.NullValue{}}: Nil{}
    case Some{T.PresentValue{value}}: distinct(nonemptyFeatures(String.split(value, ',')), Nil{})
    case None{}: distinct(defaults, Nil{})

# upstream getBetaFeatures.
def betaFeatures(+model: T.Model<J()>, headers: Maybe<&2, T.ProviderHeaders()>, hasTools: Bool, oauth: Bool, native: Bool, thinking: Maybe<&2, Bool> & Maybe<&2, Bool>) -> List<&2, String>:
  match thinking:
    case (enabled, interleaved): getBetaFeaturesWith(configuredFeatures(model, headers), defaultFeatures(model, hasTools, oauth, native, enabled, interleaved))

def assembled(-G: Data, -D: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, -Client: Data, +model: T.Model<J()>, +messages: List<&2, T.Message<V.Value, V.Value, G, D>>, +oauth: Bool, +options: AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>, +cache: Maybe<&2, J()>, transformed: Result<&2, &2, Sampling.Error, List<&2, T.Message<V.Value, V.Value, G, D>>>, redefinitions: Result<&2, &2, String, Bool>) -> Result<&2, &2, String, J()>:
  match transformed redefinitions:
    case Fail{error} _: Fail{Sampling.errorMessage(error)}
    case _ Fail{message}: Fail{message}
    case Done{converted} Done{redefined}:
      +compat = getAnthropicCompat(model)
      +initial = Transcript.getInitialSystemMessage(V.Value, V.Value, G, D, messages)
      +startTools = initialTools(initial)
      +native = compatMidSystem(compat) && compatMidTools(compat) && Bool.not(List.is_empty(&2, T.Tool<V.Value>, startTools)) && Bool.not(redefined)
      +managed = supportsMidConvoEffort(model)
      +conversation = convertMessages(G, D, dropInitial(G, D, converted, Maybe.is_some(&2, T.SystemMessage<V.Value>, initial)), oauth, cache, compatEmptySignature(compat), Bool.pick(Maybe<&2, String>, managed, Some{modelProviderName(model)}, None{}), native)
      +wire = Bool.pick(List<&2, J()>, managed, insertThinkingLevelMessages(conversation, activeEffort(Signal, Telemetry, Fetch, Error, Client, options)), wireMessages(conversation))
      +current = Transcript.getCurrentTools(V.Value, V.Value, G, D, messages)
      +features = betaFeatures(model, requestHeaders(Signal, Telemetry, Fetch, Error, Client, options), Bool.not(List.is_empty(&2, T.Tool<V.Value>, current)), oauth, native, thinkingOptions(Signal, Telemetry, Fetch, Error, Client, options))
      withPlan(Signal, Telemetry, Fetch, Error, Client, model, initial, oauth, options, planned(wire, toolList(native, startTools, Transcript.getDeclaredTools(V.Value, V.Value, G, D, messages), current, oauth, compat, cache), cache, features))

def buildMessages(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, ~Client: Data, +model: T.Model<J()>, +messages: List<&2, T.Message<V.Value, V.Value, G, D>>, +oauth: Bool, +options: AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>, retention: Maybe<&2, T.CacheRetention> & Maybe<&2, T.ProviderEnv()>) -> IO(Result<&2, &2, String, J()>):
  match retention:
    case (selected, env):
      do IO<Result<&2, &2, String, J()>>:
        +cache : Maybe<&2, J()> <- getCacheControl(model, selected, env)
        +normalizer : Transform.Normalizer(V.Value, G, J(), Sampling.Error) <- C.create(~Unit, ~Transform.NormalizeToolCallIdInput<V.Value, G, J()>, ~Result<&2, &2, Sampling.Error, String>, ~(normalizeInput(V.Value, G, J())), Unit{})
        transformed : Result<&2, &2, Sampling.Error, List<&2, T.Message<V.Value, V.Value, G, D>>> <- Transform.transformMessages(~V.Value, ~V.Value, ~G, ~D, ~J(), ~Sampling.Error, messages, model, Some{normalizer})
        C.dispose(Transform.NormalizeToolCallIdInput<V.Value, G, J()>, Result<&2, &2, Sampling.Error, String>, normalizer)
        return assembled(G, D, Signal, Telemetry, Fetch, Error, Client, model, messages, oauth, options, cache, transformed, redefinitionsOf(Transcript.hasToolRedefinitions(V.Value, G, D, messages)))

# upstream buildParams over a resolved transcript. Tool schemas that cannot be
# made strict and declarations that cannot be compared are the errors upstream
# throws while building.
def buildParams(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, ~Client: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +oauth: Bool, +options: AnthropicOptions<Signal, Telemetry, Fetch, Error, Client>) -> IO(Result<&2, &2, String, J()>):
  buildMessages(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, ~Client, model, contextMessages(G, D, context), oauth, options, optionsRetention(Signal, Telemetry, Fetch, Error, Client, options))

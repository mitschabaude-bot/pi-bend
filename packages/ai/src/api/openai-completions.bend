import Base
import ../types.bend as T
import ../models.bend as Models
import ../utils/json.bend as Wire
import ../utils/schema-json.bend as Schema
import ../utils/model-json.bend as ModelJson
import ../utils/text.bend as Text
import ../utils/transcript.bend as Transcript
import ../utils/thinking-levels.bend as Levels
import ../utils/provider-env.bend as Env
import ../utils/hash.bend as Hash
import ../utils/sanitize-unicode.bend as Unicode
import ../utils/headers.bend as Headers
import ./simple-options.bend as Simple
import ./constrained-sampling.bend as Sampling
import ./transform-messages.bend as Transform
import ./openai-prompt-cache.bend as CacheKey
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/case-map.bend as Case
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/json.bend as Parse
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/utf16.bend as Utf16

# The OpenAI Chat Completions request side (pi `openai-completions.ts`):
# compatibility resolution, message and tool conversion, Anthropic-style cache
# markers and buildParams. Wire messages are typed values serialized once at
# the request boundary. Transport lives in openai-completions-client.bend and
# SSE folding in openai-completions-stream.bend.

def J() -> Data: T.JsonValue
def Fields() -> Data: R.Record<J()>
def str(value: String) -> J(): T.JsonString{value}
def obj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}
def field(name: String, value: J()) -> R.Property<J()>: R.Property{name, value}
def put(fields: Fields(), name: String, value: J()) -> Fields(): R.set(J(), fields, name, value)
def maybe(fields: Fields(), name: String, value: Maybe<&2, J()>) -> Fields():
  match value:
    case None{}: fields
    case Some{item}: put(fields, name, item)
def optionalField(name: String, value: Maybe<&2, J()>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match value:
    case None{}: rest
    case Some{item}: field(name, item) <> rest
def contains(+text: String, needle: String) -> Bool: String.contains(text, needle)

# Options
# -------

# upstream OpenAICompletionsOptions extends StreamOptions; here the shared
# options are one field. toolChoice is the SDK's ChatCompletionToolChoiceOption
# kept as its wire value ("auto", "none", "required" or a function object).
type OpenAICompletionsOptions<-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data> is Data:
  OpenAICompletionsOptions{base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, toolChoice: Maybe<&2, J()>, reasoningEffort: Maybe<&2, T.ThinkingLevel>, thinkingBudgets: Maybe<&2, T.ThinkingBudgets>}

def Options(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data) -> Data: OpenAICompletionsOptions<Signal, Telemetry, Fetch, Error>

def baseOf(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: Options(Signal, Telemetry, Fetch, Error)) -> T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>:
  match options:
    case OpenAICompletionsOptions{base, _, _, _}: base

def choiceValue(value: T.ToolChoice) -> J():
  match value:
    case T.AutoTool{}: str("auto")
    case T.NoTool{}: str("none")

# upstream streamSimple's reasoningEffort: the requested level clamped to the
# model's supported levels, where "off" requests no reasoning.
def requestedLevel(level: T.ModelThinkingLevel) -> Maybe<&2, T.ThinkingLevel>:
  match level:
    case T.Off{}: None{}
    case T.Thinking{selected}: Some{selected}

def clampedEffort(-Value: Data, model: T.Model<Value>, reasoning: Maybe<&2, T.ThinkingLevel>) -> Maybe<&2, T.ThinkingLevel>:
  match reasoning:
    case None{}: None{}
    case Some{level}: requestedLevel(Models.clampThinkingLevel(Value, model, T.Thinking{level}))

def simpleSettings(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, +model: T.Model<J()>, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Options(Signal, Telemetry, Fetch, Error):
  match options:
    case None{}: OpenAICompletionsOptions{base, None{}, None{}, None{}}
    case Some{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, choice, reasoning, _, budgets}}:
      OpenAICompletionsOptions{base, Maybe.map(&2, T.ToolChoice, J(), choiceValue, choice), clampedEffort(J(), model, reasoning), budgets}

def simpleKey(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Maybe<&2, String>:
  match options:
    case None{}: None{}
    case Some{T.SimpleStreamOptions{_, _, key, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: key

# upstream streamSimple: shared base options (context-clamped maxTokens, merged
# sampling parameters), the tool choice and the clamped reasoning level.
def streamSimpleOptions(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Options(Signal, Telemetry, Fetch, Error):
  +base = Simple.buildBaseOptions(~G, ~D, ~J(), ~Signal, ~Telemetry, ~Fetch, ~Error, model, context, options, simpleKey(Signal, Telemetry, Fetch, Error, options))
  simpleSettings(Signal, Telemetry, Fetch, Error, model, base, options)

# Compatibility
# -------------

# upstream ResolvedOpenAICompletionsCompat: every OpenAICompletionsCompat field
# after detection. Detection always supplies supportsThinkingTokenBudget and the
# two mid-conversation flags, so they are plain booleans here; the three fields
# detection can leave unset stay optional.
type ResolvedOpenAICompletionsCompat is Data:
  ResolvedOpenAICompletionsCompat{supportsStore: Bool, supportsDeveloperRole: Bool, supportsReasoningEffort: Bool, supportsUsageInStreaming: Bool, supportsFinishReason: Bool, maxTokensField: T.MaxTokensField, requiresToolResultName: Bool, requiresAssistantAfterToolResult: Bool, requiresThinkingAsText: Bool, requiresReasoningContentOnAssistantMessages: Bool, thinkingFormat: T.ThinkingFormat, chatTemplateKwargs: R.Record<T.ChatTemplateKwargValue>, chatTemplateArgs: R.Record<T.ChatTemplateKwargValue>, openRouterRouting: T.OpenRouterRouting, vercelGatewayRouting: T.VercelGatewayRouting, zaiToolStream: Bool, thinkingTokenBudgetField: Maybe<&2, T.ThinkingTokenBudgetField>, supportsThinkingTokenBudget: Bool, supportsOpenAIGrammarTools: Bool, supportsMidConvoSystemMessages: Bool, supportsMidConvoToolAdditions: Bool, supportsStrictMode: Bool, cacheControlFormat: Maybe<&2, T.CacheControlFormat>, sendSessionAffinityHeaders: Bool, sessionAffinityFormat: T.SessionAffinityFormat, supportsLongCacheRetention: Bool, vllmPriority: Maybe<&2, F64>}

def Compat() -> Data: ResolvedOpenAICompletionsCompat
def supportsStore(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def supportsDeveloperRole(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def supportsReasoningEffort(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def supportsUsageInStreaming(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def supportsFinishReason(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def maxTokensField(compat: Compat()) -> T.MaxTokensField:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def requiresToolResultName(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def requiresAssistantAfterToolResult(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def requiresThinkingAsText(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def requiresReasoningContentOnAssistantMessages(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def thinkingFormat(compat: Compat()) -> T.ThinkingFormat:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def chatTemplateKwargs(compat: Compat()) -> R.Record<T.ChatTemplateKwargValue>:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def chatTemplateArgs(compat: Compat()) -> R.Record<T.ChatTemplateKwargValue>:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def openRouterRouting(compat: Compat()) -> T.OpenRouterRouting:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _, _}: value
def vercelGatewayRouting(compat: Compat()) -> T.VercelGatewayRouting:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _, _}: value
def zaiToolStream(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _, _}: value
def thinkingTokenBudgetField(compat: Compat()) -> Maybe<&2, T.ThinkingTokenBudgetField>:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _, _}: value
def supportsThinkingTokenBudget(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _, _}: value
def supportsOpenAIGrammarTools(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _, _}: value
def supportsMidConvoSystemMessages(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _, _}: value
def supportsMidConvoToolAdditions(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _, _}: value
def supportsStrictMode(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _, _}: value
def cacheControlFormat(compat: Compat()) -> Maybe<&2, T.CacheControlFormat>:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _, _}: value
def sendSessionAffinityHeaders(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _, _}: value
def sessionAffinityFormat(compat: Compat()) -> T.SessionAffinityFormat:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _, _}: value
def supportsLongCacheRetention(compat: Compat()) -> Bool:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value, _}: value
def vllmPriority(compat: Compat()) -> Maybe<&2, F64>:
  match compat:
    case ResolvedOpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, value}: value

def emptyRouting() -> T.OpenRouterRouting:
  T.OpenRouterRouting{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def selectedFormat(deepseek: Bool, zai: Bool, together: Bool, antLing: Bool, openRouter: Bool) -> T.ThinkingFormat:
  Bool.pick(T.ThinkingFormat, deepseek, T.DeepSeekThinking{}, Bool.pick(T.ThinkingFormat, zai, T.ZaiThinking{}, Bool.pick(T.ThinkingFormat, together, T.TogetherThinking{}, Bool.pick(T.ThinkingFormat, antLing, T.AntLingThinking{}, Bool.pick(T.ThinkingFormat, openRouter, T.OpenRouterThinking{}, T.OpenAIThinking{})))))

# upstream detectCompat: provider and base-URL heuristics.
def detectFor(+provider: String, +baseUrl: String, +id: String) -> Compat():
  +isZai = String.eq(provider, "zai") || String.eq(provider, "zai-coding-cn") || contains(baseUrl, "api.z.ai") || contains(baseUrl, "open.bigmodel.cn")
  +isTogether = String.eq(provider, "together") || contains(baseUrl, "api.together.ai") || contains(baseUrl, "api.together.xyz")
  +isMoonshot = String.eq(provider, "moonshotai") || String.eq(provider, "moonshotai-cn") || contains(baseUrl, "api.moonshot.")
  +isOpenRouter = String.eq(provider, "openrouter") || contains(baseUrl, "openrouter.ai")
  +isCloudflareWorkersAI = String.eq(provider, "cloudflare-workers-ai") || contains(baseUrl, "api.cloudflare.com")
  +isCloudflareAiGateway = String.eq(provider, "cloudflare-ai-gateway") || contains(baseUrl, "gateway.ai.cloudflare.com")
  +isNvidia = String.eq(provider, "nvidia") || contains(baseUrl, "integrate.api.nvidia.com")
  +isAntLing = String.eq(provider, "ant-ling") || contains(baseUrl, "api.ant-ling.com")
  +isCerebras = String.eq(provider, "cerebras") || contains(baseUrl, "cerebras.ai")
  +isDeepSeek = String.eq(provider, "deepseek") || contains(Case.lower(baseUrl), "deepseek.com")
  +isGrok = String.eq(provider, "xai") || contains(baseUrl, "api.x.ai")
  +chutes = contains(baseUrl, "chutes.ai")
  +isNonStandard = isNvidia || isCerebras || isGrok || isTogether || chutes || isDeepSeek || isZai || isMoonshot || String.eq(provider, "opencode") || contains(baseUrl, "opencode.ai") || isCloudflareWorkersAI || isCloudflareAiGateway || isAntLing
  +useMaxTokens = chutes || isDeepSeek || isMoonshot || isCloudflareAiGateway || isTogether || isNvidia || isAntLing || isZai
  +isOpenRouterDeveloperRoleModel = isOpenRouter && (String.starts_with(id, "anthropic/") || String.starts_with(id, "openai/"))
  +cacheControlFormat = Bool.pick(Maybe<&2, T.CacheControlFormat>, String.eq(provider, "openrouter") && String.starts_with(id, "anthropic/"), Some{T.AnthropicCacheControl{}}, None{})
  +supportsReasoningEffort = Bool.not(isGrok || isZai || isMoonshot || isTogether || isCloudflareAiGateway || isNvidia || isAntLing)
  +maxTokensField = Bool.pick(T.MaxTokensField, useMaxTokens, T.MaxTokens{}, T.MaxCompletionTokens{})
  +affinityFormat = Bool.pick(T.SessionAffinityFormat, isOpenRouter, T.OpenRouterSession{}, T.OpenAISession{})
  +longRetention = Bool.not(isTogether || isCloudflareWorkersAI || isCloudflareAiGateway || isNvidia || isAntLing)
  ResolvedOpenAICompletionsCompat{Bool.not(isNonStandard), isOpenRouterDeveloperRoleModel || (Bool.not(isNonStandard) && Bool.not(isOpenRouter)), supportsReasoningEffort, True{}, True{}, maxTokensField, False{}, False{}, False{}, isDeepSeek, selectedFormat(isDeepSeek, isZai, isTogether, isAntLing, isOpenRouter), R.new(T.ChatTemplateKwargValue), R.new(T.ChatTemplateKwargValue), emptyRouting(), T.VercelGatewayRouting{None{}, None{}}, False{}, None{}, False{}, False{}, False{}, False{}, False{}, cacheControlFormat, isOpenRouter, affinityFormat, longRetention, None{}}

def detectCompat(model: T.Model<J()>) -> Compat():
  match model:
    case T.Model{id, _, _, provider, baseUrl, _, _, _, _, _, _, _, _, _, _, _}: detectFor(provider, baseUrl, id)

# upstream getCompat: detection overridden field by field by model.compat.
def overrideCompat(api: T.ModelApi, compat: Maybe<&2, T.ModelCompatibility(api)>, detected: Compat()) -> Compat():
  match api compat detected:
    case T.OpenAICompletionsApi{} Some{T.OpenAICompletionsCompat{o0, o1, o2, o3, o4, o5, o6, o7, o8, o9, o10, o11, o12, o13, o14, o15, o16, o17, o18, o19, o20, o21, o22, o23, o24, o25, o26}} ResolvedOpenAICompletionsCompat{d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, d14, d15, d16, d17, d18, d19, d20, d21, d22, d23, d24, d25, d26}:
      ResolvedOpenAICompletionsCompat{Maybe.default(&2, Bool, o0, d0), Maybe.default(&2, Bool, o1, d1), Maybe.default(&2, Bool, o2, d2), Maybe.default(&2, Bool, o3, d3), Maybe.default(&2, Bool, o4, d4), Maybe.default(&2, T.MaxTokensField, o5, d5), Maybe.default(&2, Bool, o6, d6), Maybe.default(&2, Bool, o7, d7), Maybe.default(&2, Bool, o8, d8), Maybe.default(&2, Bool, o9, d9), Maybe.default(&2, T.ThinkingFormat, o10, d10), Maybe.default(&2, R.Record<T.ChatTemplateKwargValue>, o11, d11), Maybe.default(&2, R.Record<T.ChatTemplateKwargValue>, o12, d12), Maybe.default(&2, T.OpenRouterRouting, o13, d13), Maybe.default(&2, T.VercelGatewayRouting, o14, d14), Maybe.default(&2, Bool, o15, d15), Maybe.or(&2, T.ThinkingTokenBudgetField, o16, d16), Maybe.default(&2, Bool, o17, d17), Maybe.default(&2, Bool, o18, d18), Maybe.default(&2, Bool, o19, d19), Maybe.default(&2, Bool, o20, d20), Maybe.default(&2, Bool, o21, d21), Maybe.or(&2, T.CacheControlFormat, o22, d22), Maybe.default(&2, Bool, o23, d23), Maybe.default(&2, T.SessionAffinityFormat, o24, d24), Maybe.default(&2, Bool, o25, d25), Maybe.or(&2, F64, o26, d26)}
    case _ _ fallback: fallback

def getCompat(model: T.Model<J()>) -> Compat():
  match model:
    case T.Model{id, _, api, provider, baseUrl, _, _, _, _, _, _, _, _, _, _, compat}: overrideCompat(api, compat, detectFor(provider, baseUrl, id))

# Wire messages
# -------------

# The Chat Completions message params pi sends. Anthropic cache markers can
# only occur where upstream places them: text parts and tools.
type CacheControl is Data:
  CacheControl{ttl: Maybe<&2, String>}

type ContentPart is Data:
  TextPart{text: String, cacheControl: Maybe<&2, CacheControl>}
  ImagePart{url: String}

type MessageContent is Data:
  StringContent{text: String}
  PartsContent{parts: List<&2, ContentPart>}

type InstructionRole is Data:
  SystemRole{}
  DeveloperRole{}

# OPENAI_COMPLETIONS_REASONING_FIELDS
type ReasoningField is Data:
  ReasoningFieldReasoning{}
  ReasoningFieldContent{}
  ReasoningFieldText{}

type ReasoningText is Data:
  ReasoningText{field: ReasoningField, text: String}

type ChatToolCall is Data:
  FunctionToolCall{id: String, name: String, arguments: String}
  CustomToolCall{id: String, name: String, input: String}

type ChatTool is Data:
  FunctionTool{name: String, description: String, parameters: V.Value, strict: Maybe<&2, Bool>, cacheControl: Maybe<&2, CacheControl>}
  CustomTool{name: String, description: String, syntax: T.GrammarFormat, definition: String, cacheControl: Maybe<&2, CacheControl>}

# Assistant content None is JSON null. reasoningContentPlaceholder is the empty
# reasoning_content some providers require on replayed assistant messages.
type ChatMessage is Data:
  InstructionMessage{role: InstructionRole, content: MessageContent}
  KimiToolSystemMessage{tools: List<&2, ChatTool>}
  UserChatMessage{content: MessageContent}
  AssistantChatMessage{content: Maybe<&2, MessageContent>, reasoning: Maybe<&2, ReasoningText>, toolCalls: Maybe<&2, List<&2, ChatToolCall>>, reasoningDetails: Maybe<&2, List<&2, J()>>, reasoningContentPlaceholder: Bool}
  ToolChatMessage{content: MessageContent, toolCallId: String, name: Maybe<&2, String>}

def reasoningFieldName(value: ReasoningField) -> String:
  match value:
    case ReasoningFieldReasoning{}: "reasoning"
    case ReasoningFieldContent{}: "reasoning_content"
    case ReasoningFieldText{}: "reasoning_text"

def reasoningFieldOf(name: String) -> Maybe<&2, ReasoningField>:
  match name:
    case "reasoning": Some{ReasoningFieldReasoning{}}
    case "reasoning_content": Some{ReasoningFieldContent{}}
    case "reasoning_text": Some{ReasoningFieldText{}}
    case _: None{}

def cacheControlJson(value: CacheControl) -> J():
  match value:
    case CacheControl{ttl}: obj(field("type", str("ephemeral")) <> optionalField("ttl", Maybe.map(&2, String, J(), str, ttl), Nil{}))

def cacheField(value: Maybe<&2, CacheControl>) -> List<&2, R.Property<J()>>:
  optionalField("cache_control", Maybe.map(&2, CacheControl, J(), cacheControlJson, value), Nil{})

def partJson(part: ContentPart) -> J():
  match part:
    case TextPart{text, cache}: obj(field("type", str("text")) <> field("text", str(text)) <> cacheField(cache))
    case ImagePart{url}: obj(field("type", str("image_url")) <> field("image_url", obj(field("url", str(url)) <> Nil{})) <> Nil{})

def partsJson(parts: List<&2, ContentPart>) -> List<&2, J()>:
  match parts:
    case Nil{}: Nil{}
    case first <> rest: partJson(first) <> partsJson(rest)

def contentJson(content: MessageContent) -> J():
  match content:
    case StringContent{text}: str(text)
    case PartsContent{parts}: T.JsonArray{partsJson(parts)}

def roleName(role: InstructionRole) -> String:
  match role:
    case SystemRole{}: "system"
    case DeveloperRole{}: "developer"

def grammarSyntax(syntax: T.GrammarFormat) -> String:
  match syntax:
    case T.OpenAILark{}: "lark"
    case T.OpenAIRegex{}: "regex"

def boolean(value: Bool) -> J(): T.JsonBoolean{value}

def functionFields(name: String, description: String, parameters: V.Value, strict: Maybe<&2, Bool>) -> List<&2, R.Property<J()>>:
  field("name", str(name)) <> field("description", str(description)) <> field("parameters", Schema.toJson(parameters)) <> optionalField("strict", Maybe.map(&2, Bool, J(), boolean, strict), Nil{})

def toolJson(tool: ChatTool) -> J():
  match tool:
    case FunctionTool{name, description, parameters, strict, cache}:
      obj(field("type", str("function")) <> field("function", obj(functionFields(name, description, parameters, strict))) <> cacheField(cache))
    case CustomTool{name, description, syntax, definition, cache}:
      +grammar = obj(field("syntax", str(grammarSyntax(syntax))) <> field("definition", str(definition)) <> Nil{})
      +format = obj(field("type", str("grammar")) <> field("grammar", grammar) <> Nil{})
      obj(field("type", str("custom")) <> field("custom", obj(field("name", str(name)) <> field("description", str(description)) <> field("format", format) <> Nil{})) <> cacheField(cache))

def toolValues(tools: List<&2, ChatTool>) -> List<&2, J()>:
  match tools:
    case Nil{}: Nil{}
    case first <> rest: toolJson(first) <> toolValues(rest)

def toolsJson(tools: List<&2, ChatTool>) -> J(): T.JsonArray{toolValues(tools)}

def toolCallJson(call: ChatToolCall) -> J():
  match call:
    case FunctionToolCall{id, name, arguments}: obj(field("id", str(id)) <> field("type", str("function")) <> field("function", obj(field("name", str(name)) <> field("arguments", str(arguments)) <> Nil{})) <> Nil{})
    case CustomToolCall{id, name, input}: obj(field("id", str(id)) <> field("type", str("custom")) <> field("custom", obj(field("name", str(name)) <> field("input", str(input)) <> Nil{})) <> Nil{})

def reasoningFields(value: Maybe<&2, ReasoningText>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match value:
    case None{}: rest
    case Some{ReasoningText{name, text}}: field(reasoningFieldName(name), str(text)) <> rest

def placeholderField(enabled: Bool) -> List<&2, R.Property<J()>>:
  Bool.pick(List<&2, R.Property<J()>>, enabled, field("reasoning_content", str("")) <> Nil{}, Nil{})

def callValues(calls: List<&2, ChatToolCall>) -> List<&2, J()>:
  match calls:
    case Nil{}: Nil{}
    case first <> rest: toolCallJson(first) <> callValues(rest)

def callsJson(calls: List<&2, ChatToolCall>) -> J(): T.JsonArray{callValues(calls)}
def detailsJson(details: List<&2, J()>) -> J(): T.JsonArray{details}
def messageJson(message: ChatMessage) -> J():
  match message:
    case InstructionMessage{role, content}: obj(field("role", str(roleName(role))) <> field("content", contentJson(content)) <> Nil{})
    case KimiToolSystemMessage{tools}: obj(field("role", str("system")) <> field("tools", toolsJson(tools)) <> Nil{})
    case UserChatMessage{content}: obj(field("role", str("user")) <> field("content", contentJson(content)) <> Nil{})
    case AssistantChatMessage{content, reasoning, calls, details, placeholder}:
      +encodedContent = Maybe.default(&2, J(), Maybe.map(&2, MessageContent, J(), contentJson, content), T.JsonNull{})
      +encodedCalls = Maybe.map(&2, List<&2, ChatToolCall>, J(), callsJson, calls)
      +encodedDetails = Maybe.map(&2, List<&2, J()>, J(), detailsJson, details)
      obj(field("role", str("assistant")) <> field("content", encodedContent) <> reasoningFields(reasoning, optionalField("tool_calls", encodedCalls, optionalField("reasoning_details", encodedDetails, placeholderField(placeholder)))))
    case ToolChatMessage{content, id, name}:
      obj(field("role", str("tool")) <> field("content", contentJson(content)) <> field("tool_call_id", str(id)) <> optionalField("name", Maybe.map(&2, String, J(), str, name), Nil{}))

def messageValues(messages: List<&2, ChatMessage>) -> List<&2, J()>:
  match messages:
    case Nil{}: Nil{}
    case first <> rest: messageJson(first) <> messageValues(rest)

def messagesJson(messages: List<&2, ChatMessage>) -> J(): T.JsonArray{messageValues(messages)}

# Reasoning details
# -----------------

# upstream isOpenAIReasoningDetail over the parsed signature JSON.
def optionalText(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case None{}: True{}
    case Some{V.Text{_}}: True{}
    case _: False{}

def nullableText(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Null{}}: True{}
    case other: optionalText(other)

def optionalNumber(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case None{}: True{}
    case Some{V.Number{_}}: True{}
    case _: False{}

def isText(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Text{_}}: True{}
    case _: False{}

def typedDetail(kind: Maybe<&2, V.Value>, +fields: R.Record<V.Value>) -> Bool:
  match kind:
    case Some{V.Text{"reasoning.summary"}}: isText(R.get(V.Value, fields, "summary"))
    case Some{V.Text{"reasoning.encrypted"}}: isText(R.get(V.Value, fields, "data"))
    case Some{V.Text{"reasoning.text"}}: isText(R.get(V.Value, fields, "text")) && nullableText(R.get(V.Value, fields, "signature"))
    case _: False{}

def isOpenAIReasoningDetail(value: V.Value) -> Bool:
  match value:
    case V.ObjectValue{+fields}: nullableText(R.get(V.Value, fields, "id")) && optionalText(R.get(V.Value, fields, "format")) && optionalNumber(R.get(V.Value, fields, "index")) && typedDetail(R.get(V.Value, fields, "type"), fields)
    case _: False{}

def allDetails(values: List<&2, V.Value>) -> Bool:
  match values:
    case Nil{}: True{}
    case +first <> rest: isOpenAIReasoningDetail(first) && allDetails(rest)

def parsedValue(result: Result<&2, &2, Parse.ParseError, V.Value>) -> Maybe<&2, V.Value>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

def parsedSignature(signature: Maybe<&2, String>) -> Maybe<&2, V.Value>:
  match signature:
    case None{}: None{}
    case Some{SNil{}}: None{}
    case Some{text}: parsedValue(Parse.parse(text))

def jsonValues(values: List<&2, V.Value>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case first <> rest: Schema.toJson(first) <> jsonValues(rest)

def detailList(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, J()>>:
  match value:
    case Some{V.ArrayValue{+first <> +rest}}: Bool.pick(Maybe<&2, List<&2, J()>>, allDetails(first <> rest), Some{jsonValues(first <> rest)}, None{})
    case _: None{}

def parseOpenAIReasoningDetails(signature: Maybe<&2, String>) -> Maybe<&2, List<&2, J()>>:
  detailList(parsedSignature(signature))

def nonemptyText(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Text{SCon{_, _}}}: True{}
    case _: False{}

def textIs(value: Maybe<&2, V.Value>, expected: String) -> Bool:
  match value:
    case Some{V.Text{text}}: String.eq(text, expected)
    case _: False{}

def encryptedWithId(value: V.Value) -> Bool:
  match value:
    case V.ObjectValue{+fields}: textIs(R.get(V.Value, fields, "type"), "reasoning.encrypted") && nonemptyText(R.get(V.Value, fields, "id")) && nonemptyText(R.get(V.Value, fields, "data"))
    case _: False{}

def legacyDetail(value: Maybe<&2, V.Value>) -> Maybe<&2, J()>:
  match value:
    case Some{+detail}: Bool.pick(Maybe<&2, J()>, isOpenAIReasoningDetail(detail) && encryptedWithId(detail), Some{Schema.toJson(detail)}, None{})
    case None{}: None{}

def parseLegacyEncryptedReasoningDetail(signature: Maybe<&2, String>) -> Maybe<&2, J()>:
  legacyDetail(parsedSignature(signature))

# Tools
# -----

def ToolResult() -> Data: Result<&2, &2, Sampling.Error, ChatTool>
def ToolsResult() -> Data: Result<&2, &2, Sampling.Error, List<&2, ChatTool>>

def strictFlag(supported: Bool, strict: Maybe<&2, Bool>) -> Maybe<&2, Bool>:
  Bool.pick(Maybe<&2, Bool>, supported, Some{Maybe.default(&2, Bool, strict, False{})}, None{})

def functionTool(tool: T.Tool<V.Value>, supported: Bool, strict: Maybe<&2, Bool>, parameters: Result<&2, &2, Sampling.Error, V.Value>) -> ToolResult():
  match tool parameters:
    case _ Fail{error}: Fail{error}
    case T.Tool{name, description, _, _} Done{schema}: Done{FunctionTool{name, description, schema, strictFlag(supported, strict), None{}}}

def strictTool(+tool: T.Tool<V.Value>, supported: Bool, resolved: Result<&2, &2, Sampling.Error, Maybe<&2, Bool>>) -> ToolResult():
  match resolved:
    case Fail{error}: Fail{error}
    case Done{+strict}: functionTool(tool, supported, strict, Sampling.getJsonSchemaToolParameters(tool, strict))

def customTool(tool: T.Tool<V.Value>, syntax: T.GrammarFormat, definition: String) -> ToolResult():
  match tool:
    case T.Tool{name, description, _, _}: Done{CustomTool{name, description, syntax, definition, None{}}}

def grammarTool(+tool: T.Tool<V.Value>, +strictSupported: Bool, grammar: Result<&2, &2, Sampling.Error, Maybe<&2, Sampling.GrammarConstrainedSampling>>) -> ToolResult():
  match grammar:
    case Fail{error}: Fail{error}
    case Done{Some{Sampling.GrammarConstrainedSampling{syntax, definition, _}}}: customTool(tool, syntax, definition)
    case Done{None{}}: strictTool(tool, strictSupported, Sampling.resolveJsonSchemaStrictSampling(tool, strictSupported))

def convertTool(+tool: T.Tool<V.Value>, +compat: Compat()) -> ToolResult():
  grammarTool(tool, supportsStrictMode(compat), Sampling.resolveGrammarConstrainedSampling(tool, supportsOpenAIGrammarTools(compat)))

def collectTool(value: ToolResult(), reversed: List<&2, ChatTool>) -> ToolsResult():
  match value:
    case Fail{error}: Fail{error}
    case Done{converted}: Done{converted <> reversed}

def convertFrom(tools: List<&2, T.Tool<V.Value>>, +compat: Compat(), result: ToolsResult()) -> ToolsResult():
  match tools result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{List.reverse(&2, ChatTool, reversed)}
    case first <> rest Done{reversed}: convertFrom(rest, compat, collectTool(convertTool(first, compat), reversed))

# upstream convertTools: grammar tools become custom tools when supported;
# the first tool the model cannot honor fails the request.
def convertTools(tools: List<&2, T.Tool<V.Value>>, compat: Compat()) -> ToolsResult():
  convertFrom(tools, compat, Done{Nil{}})

# Tool call ids
# -------------

def allowedIdChar(+code: U32) -> Bool:
  (U32.is_ge(code, 97) && U32.is_le(code, 122)) || (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 48) && U32.is_le(code, 57)) || U32.is_eq(code, 95) || U32.is_eq(code, 45)

# /[^a-zA-Z0-9_-]/g over UTF-16 units: a supplementary scalar is two units.
def sanitizedChar(+code: U32) -> String:
  Bool.pick(String, allowedIdChar(code), SCon{Chr{code}, SNil{}}, Bool.pick(String, U32.is_gt(code, 65535), "__", "_"))

def sanitizeIdPart(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{code}, rest}: sanitizedChar(code) ++ sanitizeIdPart(rest)

def utf16Units(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{Chr{code}, rest}: Bool.pick(Nat, U32.is_gt(code, 65535), 2n, 1n) + utf16Units(rest)

# String.prototype.slice(0, count) over UTF-16 units; a split pair keeps its
# lone high surrogate, as in JavaScript.
def codeUnits(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{+code}, rest}: Bool.pick(String, U32.is_gt(code, 65535), SCon{Chr{(55296 + (code - 65536) / 1024 : U32)}, SCon{Chr{(56320 + (code - 65536) % 1024 : U32)}, SNil{}}}, SCon{Chr{code}, SNil{}}) ++ codeUnits(rest)

def takeUnits(text: String, count: Nat) -> String:
  Utf16.normalize(String.take(codeUnits(text), count))

type IdParts is Data:
  IdParts{call: String, item: String}

def splitId(text: String, reversed: String) -> Maybe<&2, IdParts>:
  match text:
    case SNil{}: None{}
    case SCon{'|', rest}: Some{IdParts{String.reverse(reversed), rest}}
    case SCon{char, rest}: splitId(rest, SCon{char, reversed})

def hashedId(+callId: String, +hash: String) -> String:
  String.take(callId, Nat.max(1n, Nat.sub(Nat.sub(40n, String.length(hash)), 1n))) ++ "_" ++ hash

def combinedId(+callId: String, +itemId: String, +original: String) -> String:
  +combined = Bool.pick(String, String.is_empty(itemId), callId, callId ++ "_" ++ itemId)
  Bool.pick(String, Nat.is_le(utf16Units(combined), 40n), combined, hashedId(callId, String.take(Hash.shortHash(original), 8n)))

def normalizedParts(split: Maybe<&2, IdParts>, +provider: String, +id: String) -> String:
  match split:
    case Some{IdParts{call, item}}: combinedId(sanitizeIdPart(call), sanitizeIdPart(item), id)
    case None{}: Bool.pick(String, String.eq(provider, "openai") && Nat.is_gt(utf16Units(id), 40n), takeUnits(id, 40n), id)

# upstream convertMessages' normalizeToolCallId: Responses-style composite
# ids keep item-level uniqueness within the 40-character limit.
def normalizeToolCallId(+provider: String, +id: String) -> String:
  normalizedParts(splitId(id, ""), provider, id)

# Messages
# --------

def Message(-G: Data, -D: Data) -> Data: T.Message<V.Value, V.Value, G, D>
def Converted() -> Data: Result<&2, &2, Sampling.Error, List<&2, ChatMessage>>

type ConvertConfig is Data:
  ConvertConfig{compat: Compat(), provider: String, reasoning: Bool, images: Bool, role: InstructionRole, anchorsAdditions: Bool, grammarToolInputProperties: R.Record<String>}

def configCompat(config: ConvertConfig) -> Compat():
  match config:
    case ConvertConfig{compat, _, _, _, _, _, _}: compat

def prependAll(prefix: List<&2, ChatMessage>, rest: Converted()) -> Converted():
  match rest:
    case Fail{error}: Fail{error}
    case Done{tail}: Done{List.append(&2, ChatMessage, prefix, tail)}

def prependResult(prefix: Converted(), rest: Converted()) -> Converted():
  match prefix:
    case Fail{error}: Fail{error}
    case Done{messages}: prependAll(messages, rest)

def syntheticAssistant() -> ChatMessage:
  AssistantChatMessage{Some{StringContent{"I have processed the tool results."}}, None{}, None{}, None{}, False{}}

def bridgeFor(-G: Data, -D: Data, +config: ConvertConfig, afterToolResult: Bool, message: Message(G, D)) -> List<&2, ChatMessage>:
  match message:
    case T.User{_}: Bool.pick(List<&2, ChatMessage>, requiresAssistantAfterToolResult(configCompat(config)) && afterToolResult, syntheticAssistant() <> Nil{}, Nil{})
    case _: Nil{}

# System messages

def addedTools(message: T.SystemMessage<V.Value>, +index: Nat, anchors: Bool) -> List<&2, T.Tool<V.Value>>:
  match message:
    case T.SystemMessage{_, _, added, _, _}: Bool.pick(List<&2, T.Tool<V.Value>>, Nat.is_gt(index, 0n) && anchors, Maybe.default(&2, List<&2, T.Tool<V.Value>>, added, Nil{}), Nil{})

def kimiMessage(tools: ToolsResult()) -> Converted():
  match tools:
    case Fail{error}: Fail{error}
    case Done{converted}: Done{KimiToolSystemMessage{converted} <> Nil{}}

def kimiTools(added: List<&2, T.Tool<V.Value>>, compat: Compat()) -> Converted():
  match added:
    case Nil{}: Done{Nil{}}
    case tools: kimiMessage(convertTools(tools, compat))

def instruction(role: InstructionRole, +text: String) -> List<&2, ChatMessage>:
  Bool.pick(List<&2, ChatMessage>, String.is_empty(text), Nil{}, InstructionMessage{role, StringContent{Unicode.sanitizeSurrogates(text)}} <> Nil{})

def systemText(+message: T.SystemMessage<V.Value>, index: Nat) -> String:
  match index:
    case 0n: Text.renderComplete(V.Value, message)
    case _: Text.renderUpdate(V.Value, message)

def systemMessages(+message: T.SystemMessage<V.Value>, +index: Nat, config: ConvertConfig) -> Converted():
  match config:
    case ConvertConfig{compat, _, _, _, role, anchors, _}:
      prependResult(kimiTools(addedTools(message, index, anchors), compat), Done{instruction(role, systemText(message, index))})

# User messages

def userPart(part: T.TextImageContent) -> ContentPart:
  match part:
    case T.TextImageText{T.TextContent{text, _}}: TextPart{Unicode.sanitizeSurrogates(text), None{}}
    case T.TextImageImage{T.ImageContent{data, mime}}: ImagePart{"data:" ++ mime ++ ";base64," ++ data}

def userParts(parts: List<&2, T.TextImageContent>) -> List<&2, ContentPart>:
  match parts:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{SNil{}, _}} <> rest: userParts(rest)
    case first <> rest: userPart(first) <> userParts(rest)

def userBlocks(parts: List<&2, ContentPart>) -> Maybe<&2, ChatMessage>:
  match parts:
    case Nil{}: None{}
    case content: Some{UserChatMessage{PartsContent{content}}}

def userMessage(value: T.UserContent) -> Maybe<&2, ChatMessage>:
  match value:
    case T.UserText{text}: Some{UserChatMessage{StringContent{Unicode.sanitizeSurrogates(text)}}}
    case T.UserBlocks{parts}: userBlocks(userParts(parts))

# Assistant messages

def assistantTexts(parts: List<&2, T.AssistantContent<V.Value>>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case T.AssistantText{T.TextContent{+text, _}} <> rest:
      +tail = assistantTexts(rest)
      Bool.pick(List<&2, String>, Space.blank(text), tail, Unicode.sanitizeSurrogates(text) <> tail)
    case _ <> rest: assistantTexts(rest)

def thinkingBlocks(parts: List<&2, T.AssistantContent<V.Value>>) -> List<&2, T.ThinkingContent>:
  match parts:
    case Nil{}: Nil{}
    case T.AssistantThinking{block} <> rest: block <> thinkingBlocks(rest)
    case _ <> rest: thinkingBlocks(rest)

def toolCalls(parts: List<&2, T.AssistantContent<V.Value>>) -> List<&2, T.ToolCall<V.Value>>:
  match parts:
    case Nil{}: Nil{}
    case T.AssistantToolCall{call} <> rest: call <> toolCalls(rest)
    case _ <> rest: toolCalls(rest)

def nonEmptyThinking(blocks: List<&2, T.ThinkingContent>) -> List<&2, T.ThinkingContent>:
  match blocks:
    case Nil{}: Nil{}
    case T.ThinkingContent{+thinking, signature, redacted} <> rest:
      +tail = nonEmptyThinking(rest)
      Bool.pick(List<&2, T.ThinkingContent>, Space.blank(thinking), tail, T.ThinkingContent{thinking, signature, redacted} <> tail)

def signedDetails(blocks: List<&2, T.ThinkingContent>) -> Maybe<&2, List<&2, J()>>:
  match blocks:
    case Nil{}: None{}
    case T.ThinkingContent{_, signature, _} <> rest: Maybe.or(&2, List<&2, J()>, parseOpenAIReasoningDetails(signature), signedDetails(rest))

def prependMaybe(value: Maybe<&2, J()>, rest: List<&2, J()>) -> List<&2, J()>:
  match value:
    case None{}: rest
    case Some{item}: item <> rest

def legacyDetails(calls: List<&2, T.ToolCall<V.Value>>) -> List<&2, J()>:
  match calls:
    case Nil{}: Nil{}
    case T.ToolCall{_, _, _, signature, _} <> rest: prependMaybe(parseLegacyEncryptedReasoningDetail(signature), legacyDetails(rest))

def nonemptyDetails(details: List<&2, J()>) -> Maybe<&2, List<&2, J()>>:
  match details:
    case Nil{}: None{}
    case values: Some{values}

def thinkingTexts(blocks: List<&2, T.ThinkingContent>, +sanitize: Bool) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case T.ThinkingContent{+thinking, _, _} <> rest: Bool.pick(String, sanitize, Unicode.sanitizeSurrogates(thinking), thinking) <> thinkingTexts(rest, sanitize)

def textParts(texts: List<&2, String>) -> List<&2, ContentPart>:
  match texts:
    case Nil{}: Nil{}
    case text <> rest: TextPart{text, None{}} <> textParts(rest)

def firstSignature(blocks: List<&2, T.ThinkingContent>) -> Maybe<&2, String>:
  match blocks:
    case T.ThinkingContent{_, signature, _} <> _: signature
    case Nil{}: None{}

# llama.cpp and gpt-oss keep reasoning in the field its signature names;
# OpenCode Go replays "reasoning" as reasoning_content.
def replaySignature(+provider: String, signature: Maybe<&2, String>) -> Maybe<&2, String>:
  match signature:
    case Some{"reasoning"}: Some{Bool.pick(String, String.eq(provider, "opencode-go"), "reasoning_content", "reasoning")}
    case other: other

def reasoningText(field: Maybe<&2, ReasoningField>, text: String) -> Maybe<&2, ReasoningText>:
  match field:
    case None{}: None{}
    case Some{name}: Some{ReasoningText{name, text}}

def reasoningFor(signature: Maybe<&2, String>, blocks: List<&2, T.ThinkingContent>) -> Maybe<&2, ReasoningText>:
  match signature:
    case None{}: None{}
    case Some{name}: reasoningText(reasoningFieldOf(name), String.join(thinkingTexts(blocks, False{}), "\n"))

def rawReasoning(+provider: String, +blocks: List<&2, T.ThinkingContent>) -> Maybe<&2, ReasoningText>:
  reasoningFor(replaySignature(provider, firstSignature(blocks)), blocks)

def textContent(+text: String, fallback: Maybe<&2, MessageContent>) -> Maybe<&2, MessageContent>:
  Bool.pick(Maybe<&2, MessageContent>, String.is_empty(text), fallback, Some{StringContent{text}})

type AssistantParts is Data:
  AssistantParts{content: Maybe<&2, MessageContent>, reasoning: Maybe<&2, ReasoningText>}

def withThinking(+asText: Bool, +texts: List<&2, String>, +fallback: Maybe<&2, MessageContent>, +preserved: Bool, +provider: String, blocks: List<&2, T.ThinkingContent>) -> AssistantParts:
  match blocks:
    case Nil{}: AssistantParts{textContent(String.join(texts, ""), fallback), None{}}
    case +nonempty:
      Bool.pick(AssistantParts, asText,
        AssistantParts{Some{PartsContent{TextPart{String.join(thinkingTexts(nonempty, True{}), "\n\n"), None{}} <> textParts(texts)}}, None{}},
        AssistantParts{textContent(String.join(texts, ""), fallback), Bool.pick(Maybe<&2, ReasoningText>, preserved, None{}, rawReasoning(provider, nonempty))})

def grammarArguments(name: String, arguments: V.Value, property: String) -> Result<&2, &2, Sampling.Error, String>:
  match arguments:
    case V.ObjectValue{fields}: Sampling.getGrammarToolInput(name, fields, property)
    case _: Fail{Sampling.GrammarArgumentNotString{name, property}}

def customCall(id: String, name: String, input: Result<&2, &2, Sampling.Error, String>) -> Result<&2, &2, Sampling.Error, ChatToolCall>:
  match input:
    case Fail{error}: Fail{error}
    case Done{text}: Done{CustomToolCall{id, name, Unicode.sanitizeSurrogates(text)}}

def chatToolCall(call: T.ToolCall<V.Value>, property: Maybe<&2, String>) -> Result<&2, &2, Sampling.Error, ChatToolCall>:
  match call property:
    case T.ToolCall{id, +name, arguments, _, _} Some{selected}: customCall(id, name, grammarArguments(name, arguments, selected))
    case T.ToolCall{id, name, arguments, _, _} None{}: Done{FunctionToolCall{id, name, Maybe.default(&2, String, Wire.stringify(Schema.toJson(arguments)), "{}")}}

def callName(call: T.ToolCall<V.Value>) -> String:
  match call:
    case T.ToolCall{_, name, _, _, _}: name

def collectCall(value: Result<&2, &2, Sampling.Error, ChatToolCall>, rest: Result<&2, &2, Sampling.Error, List<&2, ChatToolCall>>) -> Result<&2, &2, Sampling.Error, List<&2, ChatToolCall>>:
  match value rest:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{call} Done{calls}: Done{call <> calls}

def chatToolCalls(calls: List<&2, T.ToolCall<V.Value>>, +grammar: R.Record<String>) -> Result<&2, &2, Sampling.Error, List<&2, ChatToolCall>>:
  match calls:
    case Nil{}: Done{Nil{}}
    case +call <> rest: collectCall(chatToolCall(call, R.get(String, grammar, callName(call))), chatToolCalls(rest, grammar))

def optionalCalls(calls: Result<&2, &2, Sampling.Error, List<&2, ChatToolCall>>) -> Result<&2, &2, Sampling.Error, Maybe<&2, List<&2, ChatToolCall>>>:
  match calls:
    case Fail{error}: Fail{error}
    case Done{Nil{}}: Done{None{}}
    case Done{values}: Done{Some{values}}

def hasContent(content: Maybe<&2, MessageContent>) -> Bool:
  match content:
    case Some{StringContent{SCon{_, _}}}: True{}
    case Some{PartsContent{_ <> _}}: True{}
    case _: False{}

def placeholderNeeded(+required: Bool, reasoning: Maybe<&2, ReasoningText>) -> Bool:
  match reasoning:
    case Some{ReasoningText{ReasoningFieldContent{}, _}}: False{}
    case _: required

# Messages with neither content nor tool calls (for example aborted
# responses) are skipped.
def assistantResult(parts: AssistantParts, details: Maybe<&2, List<&2, J()>>, +placeholder: Bool, calls: Result<&2, &2, Sampling.Error, Maybe<&2, List<&2, ChatToolCall>>>) -> Result<&2, &2, Sampling.Error, Maybe<&2, ChatMessage>>:
  match parts calls:
    case _ Fail{error}: Fail{error}
    case AssistantParts{+content, +reasoning} Done{None{}}: Bool.pick(Result<&2, &2, Sampling.Error, Maybe<&2, ChatMessage>>, hasContent(content), Done{Some{AssistantChatMessage{content, reasoning, None{}, details, placeholderNeeded(placeholder, reasoning)}}}, Done{None{}})
    case AssistantParts{content, +reasoning} Done{Some{values}}: Done{Some{AssistantChatMessage{content, reasoning, Some{values}, details, placeholderNeeded(placeholder, reasoning)}}}

def assistantMessage(+parts: List<&2, T.AssistantContent<V.Value>>, config: ConvertConfig) -> Result<&2, &2, Sampling.Error, Maybe<&2, ChatMessage>>:
  match config:
    case ConvertConfig{+compat, provider, reasoning, _, _, _, grammar}:
      +calls = toolCalls(parts)
      +details = Maybe.or(&2, List<&2, J()>, signedDetails(thinkingBlocks(parts)), nonemptyDetails(legacyDetails(calls)))
      +fallback = Bool.pick(Maybe<&2, MessageContent>, requiresAssistantAfterToolResult(compat), Some{StringContent{""}}, None{})
      +assembled = withThinking(requiresThinkingAsText(compat), assistantTexts(parts), fallback, Maybe.is_some(&2, List<&2, J()>, details), provider, nonEmptyThinking(thinkingBlocks(parts)))
      assistantResult(assembled, details, requiresReasoningContentOnAssistantMessages(compat) && reasoning, optionalCalls(chatToolCalls(calls, grammar)))

# Tool results

def resultTexts(parts: List<&2, T.TextImageContent>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{text, _}} <> rest: text <> resultTexts(rest)
    case _ <> rest: resultTexts(rest)

def hasImage(parts: List<&2, T.TextImageContent>) -> Bool:
  match parts:
    case Nil{}: False{}
    case T.TextImageImage{_} <> _: True{}
    case _ <> rest: hasImage(rest)

def imageParts(parts: List<&2, T.TextImageContent>) -> List<&2, ContentPart>:
  match parts:
    case Nil{}: Nil{}
    case T.TextImageImage{T.ImageContent{data, mime}} <> rest: ImagePart{"data:" ++ mime ++ ";base64," ++ data} <> imageParts(rest)
    case _ <> rest: imageParts(rest)

def resultName(+required: Bool, +name: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, required && Bool.not(String.is_empty(name)), Some{name}, None{})

def toolMessage(-D: Data, result: T.ToolResultMessage<D>, +compat: Compat()) -> ChatMessage:
  match result:
    case T.ToolResultMessage{id, name, +content, _, _, _, _}:
      +text = String.join(resultTexts(content), "\n")
      +rendered = Bool.pick(String, String.is_empty(text), Bool.pick(String, hasImage(content), "(see attached image)", "(no tool output)"), text)
      ToolChatMessage{StringContent{Unicode.sanitizeSurrogates(rendered)}, id, resultName(requiresToolResultName(compat), name)}

def resultImages(-D: Data, result: T.ToolResultMessage<D>, images: Bool) -> List<&2, ContentPart>:
  match result:
    case T.ToolResultMessage{_, _, content, _, _, _, _}: Bool.pick(List<&2, ContentPart>, images, imageParts(content), Nil{})

def imageMessages(+compat: Compat(), images: List<&2, ContentPart>) -> List<&2, ChatMessage>:
  match images:
    case Nil{}: Nil{}
    case parts:
      +attachment = {UserChatMessage{PartsContent{TextPart{"Attached image(s) from tool result:", None{}} <> parts}} : ChatMessage}
      Bool.pick(List<&2, ChatMessage>, requiresAssistantAfterToolResult(compat), syntheticAssistant() <> attachment <> Nil{}, attachment <> Nil{})

# The conversion loop

def configImages(config: ConvertConfig) -> Bool:
  match config:
    case ConvertConfig{_, _, _, images, _, _, _}: images

def userBridge(+config: ConvertConfig, afterToolResult: Bool) -> List<&2, ChatMessage>:
  Bool.pick(List<&2, ChatMessage>, requiresAssistantAfterToolResult(configCompat(config)) && afterToolResult, syntheticAssistant() <> Nil{}, Nil{})

def maybeList(value: Maybe<&2, ChatMessage>) -> List<&2, ChatMessage>:
  match value:
    case None{}: Nil{}
    case Some{message}: message <> Nil{}

def maybeResult(value: Result<&2, &2, Sampling.Error, Maybe<&2, ChatMessage>>) -> Converted():
  match value:
    case Fail{error}: Fail{error}
    case Done{message}: Done{maybeList(message)}

# A skipped message leaves upstream's lastRole unchanged.
def afterUser(converted: Maybe<&2, ChatMessage>, afterToolResult: Bool) -> Bool:
  match converted:
    case None{}: afterToolResult
    case Some{_}: False{}

def afterAssistant(converted: Result<&2, &2, Sampling.Error, Maybe<&2, ChatMessage>>, afterToolResult: Bool) -> Bool:
  match converted:
    case Done{Some{_}}: False{}
    case _: afterToolResult

def startsWithToolResult(-G: Data, -D: Data, messages: List<&2, Message(G, D)>) -> Bool:
  match messages:
    case T.ToolResult{_} <> _: True{}
    case _: False{}

# `index` is the position in the transformed transcript. `pending` collects
# the images of a run of consecutive tool results; they follow the run as one
# user message.
def convertLoop(-G: Data, -D: Data, messages: List<&2, Message(G, D)>, +index: Nat, +afterToolResult: Bool, pending: List<&2, ContentPart>, +config: ConvertConfig) -> Converted():
  match messages:
    case Nil{}: Done{Nil{}}
    case T.ToolResult{+result} <> +rest:
      +images = List.append(&2, ContentPart, pending, resultImages(D, result, configImages(config)))
      +last = Bool.not(startsWithToolResult(G, D, rest))
      +flushed = Bool.pick(List<&2, ChatMessage>, last, imageMessages(configCompat(config), images), Nil{})
      prependAll(toolMessage(D, result, configCompat(config)) <> flushed, convertLoop(G, D, rest, index + 1n, Bool.pick(Bool, last, List.is_empty(&2, ContentPart, images), afterToolResult), Bool.pick(List<&2, ContentPart>, last, Nil{}, images), config))
    case T.System{+system} <> rest:
      prependResult(systemMessages(system, index, config), convertLoop(G, D, rest, index + 1n, False{}, Nil{}, config))
    case T.User{T.UserMessage{content, _}} <> rest:
      +converted = userMessage(content)
      prependAll(List.append(&2, ChatMessage, userBridge(config, afterToolResult), maybeList(converted)), convertLoop(G, D, rest, index + 1n, afterUser(converted, afterToolResult), Nil{}, config))
    case T.Assistant{T.AssistantMessage{parts, _, _, _, _, _, _, _, _, _, _, _, _, _, _}} <> rest:
      +converted = assistantMessage(parts, config)
      prependResult(maybeResult(converted), convertLoop(G, D, rest, index + 1n, afterAssistant(converted, afterToolResult), Nil{}, config))

def normalizeInput(-A: Data, -G: Data, -M: Data, provider: String, input: Transform.NormalizeToolCallIdInput<A, G, M>) -> IO(Result<&2, &2, Sampling.Error, String>):
  match input:
    case Transform.NormalizeToolCallIdInput{id, _, _}: IO.pure(Result<&2, &2, Sampling.Error, String>, Done{normalizeToolCallId(provider, id)})

def normalizeBody(-A: Data, -G: Data, -M: Data, provider: String) -> Transform.NormalizeToolCallIdInput<A, G, M> -> IO(Result<&2, &2, Sampling.Error, String>):
  input => normalizeInput(A, G, M, provider, input)

def convertTransformed(-G: Data, -D: Data, result: Result<&2, &2, Sampling.Error, List<&2, Message(G, D)>>, config: ConvertConfig) -> Converted():
  match result:
    case Fail{error}: Fail{error}
    case Done{messages}: convertLoop(G, D, messages, 0n, False{}, Nil{}, config)

def toolAdditions(+compat: Compat()) -> Bool:
  supportsMidConvoSystemMessages(compat) && supportsMidConvoToolAdditions(compat)

def anchorsOf(tools: Transcript.TranscriptTools<V.Value>) -> Bool:
  match tools:
    case Transcript.TranscriptTools{_, anchors}: anchors

def anchorsAdditions(-G: Data, -D: Data, messages: List<&2, Message(G, D)>, compat: Compat()) -> Bool:
  anchorsOf(Transcript.resolveTranscriptTools(V.Value, V.Value, G, D, messages, toolAdditions(compat)))

def instructionRole(+reasoning: Bool, +compat: Compat()) -> InstructionRole:
  Bool.pick(InstructionRole, reasoning && supportsDeveloperRole(compat), DeveloperRole{}, SystemRole{})

def convertResolved(~G: Data, ~D: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +compat: Compat(), grammar: R.Record<String>) -> IO(Converted()):
  match context:
    case T.TranscriptContext{+messages}:
      +provider = T.modelProvider(model)
      +reasoning = T.modelReasoning(model)
      do IO<Converted()>:
        +normalizer : Transform.Normalizer(V.Value, G, J(), Sampling.Error) <- C.create(~String, ~Transform.NormalizeToolCallIdInput<V.Value, G, J()>, ~Result<&2, &2, Sampling.Error, String>, ~(normalizeBody(V.Value, G, J())), provider)
        transformed : Result<&2, &2, Sampling.Error, List<&2, Message(G, D)>> <- Transform.transformMessages(~V.Value, ~V.Value, ~G, ~D, ~J(), ~Sampling.Error, messages, model, Some{normalizer})
        C.dispose(Transform.NormalizeToolCallIdInput<V.Value, G, J()>, Result<&2, &2, Sampling.Error, String>, normalizer)
        return convertTransformed(G, D, transformed, ConvertConfig{compat, provider, reasoning, Transform.imageCapability(J(), model), instructionRole(reasoning, compat), anchorsAdditions(G, D, messages, compat), grammar})

# upstream convertMessages. The only failures are tool conversions for
# mid-conversation tool additions and grammar tool calls whose input
# property is not a string.
def convertMessages(~G: Data, ~D: Data, model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +compat: Compat(), grammarToolInputProperties: R.Record<String>) -> IO(Converted()):
  convertResolved(~G, ~D, model, Transcript.resolveTranscript(V.Value, V.Value, G, D, context, Some{supportsMidConvoSystemMessages(compat)}), compat, grammarToolInputProperties)

# Anthropic cache markers
# -----------------------

def isNoRetention(retention: T.CacheRetention) -> Bool:
  match retention:
    case T.CacheNone{}: True{}
    case _: False{}

def isLongRetention(retention: T.CacheRetention) -> Bool:
  match retention:
    case T.CacheLong{}: True{}
    case _: False{}

def anthropicFormat(format: Maybe<&2, T.CacheControlFormat>) -> Bool:
  match format:
    case Some{T.AnthropicCacheControl{}}: True{}
    case None{}: False{}

def getCompatCacheControl(+compat: Compat(), +retention: T.CacheRetention) -> Maybe<&2, CacheControl>:
  Bool.pick(Maybe<&2, CacheControl>, anthropicFormat(cacheControlFormat(compat)) && Bool.not(isNoRetention(retention)), Some{CacheControl{Bool.pick(Maybe<&2, String>, isLongRetention(retention) && supportsLongCacheRetention(compat), Some{"1h"}, None{})}}, None{})

def markHere(first: ContentPart, rest: List<&2, ContentPart>, cache: CacheControl) -> Maybe<&2, List<&2, ContentPart>>:
  match first:
    case TextPart{text, _}: Some{TextPart{text, Some{cache}} <> rest}
    case ImagePart{_}: None{}

def markedTail(first: ContentPart, marked: Maybe<&2, List<&2, ContentPart>>, rest: List<&2, ContentPart>, cache: CacheControl) -> Maybe<&2, List<&2, ContentPart>>:
  match marked:
    case Some{tail}: Some{first <> tail}
    case None{}: markHere(first, rest, cache)

# The last text part carries the marker.
def markLastText(parts: List<&2, ContentPart>, +cache: CacheControl) -> Maybe<&2, List<&2, ContentPart>>:
  match parts:
    case Nil{}: None{}
    case +first <> +rest: markedTail(first, markLastText(rest, cache), rest, cache)

def partsContent(parts: Maybe<&2, List<&2, ContentPart>>) -> Maybe<&2, MessageContent>:
  match parts:
    case None{}: None{}
    case Some{marked}: Some{PartsContent{marked}}

# upstream addCacheControlToTextContent: None when no text part can carry it.
def addCacheControl(content: MessageContent, cache: CacheControl) -> Maybe<&2, MessageContent>:
  match content:
    case StringContent{SNil{}}: None{}
    case StringContent{text}: Some{PartsContent{TextPart{text, Some{cache}} <> Nil{}}}
    case PartsContent{parts}: partsContent(markLastText(parts, cache))

def userMarked(marked: Maybe<&2, MessageContent>) -> Maybe<&2, ChatMessage>:
  match marked:
    case None{}: None{}
    case Some{content}: Some{UserChatMessage{content}}

def assistantMarked(marked: Maybe<&2, MessageContent>, reasoning: Maybe<&2, ReasoningText>, calls: Maybe<&2, List<&2, ChatToolCall>>, details: Maybe<&2, List<&2, J()>>, placeholder: Bool) -> Maybe<&2, ChatMessage>:
  match marked:
    case None{}: None{}
    case Some{content}: Some{AssistantChatMessage{Some{content}, reasoning, calls, details, placeholder}}

def toolMarked(marked: Maybe<&2, MessageContent>, id: String, name: Maybe<&2, String>) -> Maybe<&2, ChatMessage>:
  match marked:
    case None{}: None{}
    case Some{content}: Some{ToolChatMessage{content, id, name}}

def markConversationMessage(message: ChatMessage, cache: CacheControl) -> Maybe<&2, ChatMessage>:
  match message:
    case UserChatMessage{content}: userMarked(addCacheControl(content, cache))
    case AssistantChatMessage{Some{content}, reasoning, calls, details, placeholder}: assistantMarked(addCacheControl(content, cache), reasoning, calls, details, placeholder)
    case ToolChatMessage{content, id, name}: toolMarked(addCacheControl(content, cache), id, name)
    case _: None{}

# Newest first: the latest user, assistant or tool message that has text.
def markNewest(reversed: List<&2, ChatMessage>, +cache: CacheControl) -> List<&2, ChatMessage>:
  match reversed:
    case Nil{}: Nil{}
    case +first <> +rest:
      +marked = markConversationMessage(first, cache)
      Bool.pick(List<&2, ChatMessage>, Maybe.is_some(&2, ChatMessage, marked), Maybe.default(&2, ChatMessage, marked, first) <> rest, first <> markNewest(rest, cache))

def markInstruction(role: InstructionRole, +content: MessageContent, cache: CacheControl) -> ChatMessage:
  InstructionMessage{role, Maybe.default(&2, MessageContent, addCacheControl(content, cache), content)}

# Only the first system or developer message is considered, including a
# mid-conversation tool message, which has no text.
def markSystemPrompt(messages: List<&2, ChatMessage>, +cache: CacheControl) -> List<&2, ChatMessage>:
  match messages:
    case Nil{}: Nil{}
    case InstructionMessage{role, content} <> rest: markInstruction(role, content, cache) <> rest
    case KimiToolSystemMessage{tools} <> rest: KimiToolSystemMessage{tools} <> rest
    case first <> rest: first <> markSystemPrompt(rest, cache)

def toolWithCache(tool: ChatTool, cache: CacheControl) -> ChatTool:
  match tool:
    case FunctionTool{name, description, parameters, strict, _}: FunctionTool{name, description, parameters, strict, Some{cache}}
    case CustomTool{name, description, syntax, definition, _}: CustomTool{name, description, syntax, definition, Some{cache}}

def markLastTool(tools: List<&2, ChatTool>, +cache: CacheControl) -> List<&2, ChatTool>:
  match tools:
    case Nil{}: Nil{}
    case tool <> Nil{}: toolWithCache(tool, cache) <> Nil{}
    case tool <> rest: tool <> markLastTool(rest, cache)

def applyAnthropicCacheControlToMessages(messages: List<&2, ChatMessage>, +cache: CacheControl) -> List<&2, ChatMessage>:
  List.reverse(&2, ChatMessage, markNewest(List.reverse(&2, ChatMessage, markSystemPrompt(messages, cache)), cache))

# Request parameters
# ------------------

# upstream resolveCacheRetention: explicit retention, else PI_CACHE_RETENTION=long.
def environmentRetention(value: Maybe<&2, String>) -> T.CacheRetention:
  match value:
    case Some{"long"}: T.CacheLong{}
    case _: T.CacheShort{}

def resolveCacheRetention(retention: Maybe<&2, T.CacheRetention>, env: Maybe<&2, T.ProviderEnv()>) -> IO(T.CacheRetention):
  match retention:
    case Some{value}: IO.pure(T.CacheRetention, value)
    case None{}:
      do IO<T.CacheRetention>:
        value : Maybe<&2, String> <- Env.getProviderEnvValue("PI_CACHE_RETENTION", env)
        return environmentRetention(value)

# The session id used for caching and affinity; none when caching is off.
def cacheSessionId(retention: T.CacheRetention, sessionId: Maybe<&2, String>) -> Maybe<&2, String>:
  match retention:
    case T.CacheNone{}: None{}
    case _: sessionId

type RequestTools is Data:
  NoTools{}
  HistoryTools{}
  DeclaredTools{tools: List<&2, ChatTool>}

def hasToolCall(parts: List<&2, T.AssistantContent<V.Value>>) -> Bool:
  match parts:
    case Nil{}: False{}
    case T.AssistantToolCall{_} <> _: True{}
    case _ <> rest: hasToolCall(rest)

# Anthropic via LiteLLM-style proxies requires `tools` whenever the
# conversation has tool calls or results.
def hasToolHistory(-G: Data, -D: Data, messages: List<&2, Message(G, D)>) -> Bool:
  match messages:
    case Nil{}: False{}
    case T.ToolResult{_} <> _: True{}
    case T.Assistant{T.AssistantMessage{parts, _, _, _, _, _, _, _, _, _, _, _, _, _, _}} <> rest: hasToolCall(parts) || hasToolHistory(G, D, rest)
    case _ <> rest: hasToolHistory(G, D, rest)

def declaredTools(result: ToolsResult()) -> Result<&2, &2, Sampling.Error, RequestTools>:
  match result:
    case Fail{error}: Fail{error}
    case Done{tools}: Done{DeclaredTools{tools}}

def requestTools(values: List<&2, T.Tool<V.Value>>, history: Bool, compat: Compat()) -> Result<&2, &2, Sampling.Error, RequestTools>:
  match values:
    case Nil{}: Done{Bool.pick(RequestTools, history, HistoryTools{}, NoTools{})}
    case tools: declaredTools(convertTools(tools, compat))

def markedTools(tools: RequestTools, cache: CacheControl) -> RequestTools:
  match tools:
    case DeclaredTools{values}: DeclaredTools{markLastTool(values, cache)}
    case other: other

type Marked is Data:
  Marked{messages: List<&2, ChatMessage>, tools: RequestTools}

# upstream applyAnthropicCacheControl: system prompt, last tool and the last
# conversation message with text.
def applyAnthropicCacheControl(messages: List<&2, ChatMessage>, tools: RequestTools, cache: Maybe<&2, CacheControl>) -> Marked:
  match cache:
    case None{}: Marked{messages, tools}
    case Some{+control}: Marked{applyAnthropicCacheControlToMessages(messages, control), markedTools(tools, control)}

def truthyNumber(value: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match value:
    case None{}: None{}
    case Some{+number}: Bool.pick(Maybe<&2, F64>, Bool.not(F.isNaN(number)) && Bool.not(F.isEqual(F.compare(number, F.fromU32(0)))), Some{number}, None{})

def withPromptCache(+fields: Fields(), +baseUrl: String, +retention: T.CacheRetention, +compat: Compat(), sessionId: Maybe<&2, String>) -> Fields():
  +long = isLongRetention(retention) && supportsLongCacheRetention(compat)
  +keyed = Bool.pick(Fields(), (contains(baseUrl, "api.openai.com") && Bool.not(isNoRetention(retention))) || long, maybe(fields, "prompt_cache_key", Maybe.map(&2, String, J(), str, CacheKey.clampOpenAIPromptCacheKey(sessionId))), fields)
  Bool.pick(Fields(), long, put(keyed, "prompt_cache_retention", str("24h")), keyed)

def maxTokensName(field: T.MaxTokensField) -> String:
  match field:
    case T.MaxTokens{}: "max_tokens"
    case T.MaxCompletionTokens{}: "max_completion_tokens"

def withTools(+fields: Fields(), tools: RequestTools, +zaiStream: Bool) -> Fields():
  match tools:
    case NoTools{}: fields
    case HistoryTools{}: put(fields, "tools", T.JsonArray{Nil{}})
    case DeclaredTools{values}:
      +listed = put(fields, "tools", toolsJson(values))
      Bool.pick(Fields(), zaiStream, put(listed, "tool_stream", T.JsonBoolean{True{}}), listed)

# Thinking formats

def mappedLevel(mapping: Maybe<&2, T.ThinkingLevelMap>, level: T.ThinkingLevel) -> Maybe<&2, T.Nullable<String>>:
  Levels.mapped(mapping, T.Thinking{level})

def levelName(level: T.ThinkingLevel) -> String: Levels.name(T.Thinking{level})

# `thinkingLevelMap?.[level] ?? level`
def mappedOrLevel(value: Maybe<&2, T.Nullable<String>>, +level: T.ThinkingLevel) -> String:
  match value:
    case Some{T.PresentValue{text}}: text
    case _: levelName(level)

def effortValue(mapping: Maybe<&2, T.ThinkingLevelMap>, +level: T.ThinkingLevel) -> String:
  mappedOrLevel(mappedLevel(mapping, level), level)

# `mapped === undefined ? fallback : mapped`, kept only when it is a string.
def undefinedOr(value: Maybe<&2, T.Nullable<String>>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case None{}: fallback
    case Some{T.PresentValue{text}}: Some{text}
    case Some{T.NullValue{}}: None{}

def offMapping(mapping: Maybe<&2, T.ThinkingLevelMap>) -> Maybe<&2, T.Nullable<String>>: Levels.mapped(mapping, T.Off{})

# `thinkingLevelMap?.off !== null`
def offNotNull(value: Maybe<&2, T.Nullable<String>>) -> Bool:
  match value:
    case Some{T.NullValue{}}: False{}
    case _: True{}

# `thinkingLevelMap?.off ?? "none"`
def offOrNone(value: Maybe<&2, T.Nullable<String>>) -> String:
  match value:
    case Some{T.PresentValue{text}}: text
    case _: "none"

# The requested level's mapping, or the off mapping when reasoning is off.
def requestedMapping(mapping: Maybe<&2, T.ThinkingLevelMap>, effort: Maybe<&2, T.ThinkingLevel>) -> Maybe<&2, T.Nullable<String>>:
  match effort:
    case None{}: offMapping(mapping)
    case Some{level}: mappedLevel(mapping, level)

def effortName(effort: Maybe<&2, T.ThinkingLevel>) -> Maybe<&2, String>:
  Maybe.map(&2, T.ThinkingLevel, String, levelName, effort)

def effortObject(value: String) -> J(): obj(field("effort", str(value)) <> Nil{})
def typeObject(value: String) -> J(): obj(field("type", str(value)) <> Nil{})

def genericEffort(+fields: Fields(), effort: Maybe<&2, T.ThinkingLevel>, +mapping: Maybe<&2, T.ThinkingLevelMap>) -> Fields():
  match effort:
    case Some{level}: put(fields, "reasoning_effort", str(effortValue(mapping, level)))
    case None{}: maybe(fields, "reasoning_effort", Maybe.map(&2, String, J(), str, undefinedOr(offMapping(mapping), None{})))

def genericReasoning(+fields: Fields(), effort: Maybe<&2, T.ThinkingLevel>, mapping: Maybe<&2, T.ThinkingLevelMap>, supportsEffort: Bool) -> Fields():
  Bool.pick(Fields(), supportsEffort, genericEffort(fields, effort, mapping), fields)

def zaiReasoning(+fields: Fields(), effort: Maybe<&2, T.ThinkingLevel>, +mapping: Maybe<&2, T.ThinkingLevelMap>, +supported: Bool) -> Fields():
  match effort:
    case None{}: put(fields, "thinking", typeObject("disabled"))
    case Some{+level}:
      +enabled = put(fields, "thinking", obj(field("type", str("enabled")) <> field("clear_thinking", T.JsonBoolean{False{}}) <> Nil{}))
      Bool.pick(Fields(), supported, maybe(enabled, "reasoning_effort", Maybe.map(&2, String, J(), str, undefinedOr(mappedLevel(mapping, level), Some{levelName(level)}))), enabled)

def effortWhenSupported(+fields: Fields(), effort: Maybe<&2, T.ThinkingLevel>, +mapping: Maybe<&2, T.ThinkingLevelMap>, supportsEffort: Bool) -> Fields():
  match effort supportsEffort:
    case Some{level} True{}: put(fields, "reasoning_effort", str(effortValue(mapping, level)))
    case _ _: fields

def qwenReasoning(fields: Fields(), +effort: Maybe<&2, T.ThinkingLevel>, mapping: Maybe<&2, T.ThinkingLevelMap>, supported: Bool) -> Fields():
  effortWhenSupported(put(fields, "enable_thinking", T.JsonBoolean{Maybe.is_some(&2, T.ThinkingLevel, effort)}), effort, mapping, supported)

def budgetValue(budget: Maybe<&2, F64>) -> Maybe<&2, J()>:
  match budget:
    case None{}: None{}
    case Some{value}: Some{T.JsonNumber{value}}

def templateVariable(variable: T.ThinkingVariable, +effort: Maybe<&2, T.ThinkingLevel>, mapping: Maybe<&2, T.ThinkingLevelMap>, budget: Maybe<&2, F64>) -> Maybe<&2, J()>:
  match variable:
    case T.ThinkingEnabled{}: Some{T.JsonBoolean{Maybe.is_some(&2, T.ThinkingLevel, effort)}}
    case T.ThinkingBudget{}: budgetValue(budget)
    case T.ThinkingEffort{}: Maybe.map(&2, String, J(), str, undefinedOr(requestedMapping(mapping, effort), effortName(effort)))

def omitted(omitWhenOff: Maybe<&2, Bool>, effort: Maybe<&2, T.ThinkingLevel>) -> Bool:
  match omitWhenOff effort:
    case Some{True{}} None{}: True{}
    case _ _: False{}

# upstream resolveChatTemplateKwargValue; None omits the key.
def templateValue(value: T.ChatTemplateKwargValue, +effort: Maybe<&2, T.ThinkingLevel>, mapping: Maybe<&2, T.ThinkingLevelMap>, budget: Maybe<&2, F64>) -> Maybe<&2, J()>:
  match value:
    case T.TemplateString{text}: Some{str(text)}
    case T.TemplateNumber{number}: Some{T.JsonNumber{number}}
    case T.TemplateBoolean{flag}: Some{T.JsonBoolean{flag}}
    case T.TemplateNull{}: Some{T.JsonNull{}}
    case T.TemplateVariable{variable, omitWhenOff}: Bool.pick(Maybe<&2, J()>, omitted(omitWhenOff, effort), None{}, templateVariable(variable, effort, mapping, budget))

def templateEntries(entries: List<&2, R.Property<T.ChatTemplateKwargValue>>, +effort: Maybe<&2, T.ThinkingLevel>, +mapping: Maybe<&2, T.ThinkingLevelMap>, +budget: Maybe<&2, F64>) -> List<&2, R.Property<J()>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: optionalField(key, templateValue(value, effort, mapping, budget), templateEntries(rest, effort, mapping, budget))

def nonemptyObject(fields: List<&2, R.Property<J()>>) -> Maybe<&2, J()>:
  match fields:
    case Nil{}: None{}
    case values: Some{obj(values)}

# upstream buildChatTemplateValues: omitted when every value is omitted.
def buildChatTemplateValues(values: R.Record<T.ChatTemplateKwargValue>, effort: Maybe<&2, T.ThinkingLevel>, mapping: Maybe<&2, T.ThinkingLevelMap>, budget: Maybe<&2, F64>) -> Maybe<&2, J()>:
  nonemptyObject(templateEntries(R.entries(T.ChatTemplateKwargValue, values), effort, mapping, budget))

def basetenReasoning(fields: Fields(), +effort: Maybe<&2, T.ThinkingLevel>, +mapping: Maybe<&2, T.ThinkingLevelMap>, supported: Bool, args: R.Record<T.ChatTemplateKwargValue>, budget: Maybe<&2, F64>) -> Fields():
  +withArgs = maybe(fields, "chat_template_args", buildChatTemplateValues(args, effort, mapping, budget))
  Bool.pick(Fields(), supported, maybe(withArgs, "reasoning_effort", Maybe.map(&2, String, J(), str, undefinedOr(requestedMapping(mapping, effort), effortName(effort)))), withArgs)

def deepseekReasoning(+fields: Fields(), effort: Maybe<&2, T.ThinkingLevel>, +mapping: Maybe<&2, T.ThinkingLevelMap>, supported: Bool) -> Fields():
  match effort:
    case Some{+level}: effortWhenSupported(put(fields, "thinking", typeObject("enabled")), Some{level}, mapping, supported)
    case None{}: Bool.pick(Fields(), offNotNull(offMapping(mapping)), put(fields, "thinking", typeObject("disabled")), fields)

def openRouterReasoning(+fields: Fields(), effort: Maybe<&2, T.ThinkingLevel>, +mapping: Maybe<&2, T.ThinkingLevelMap>) -> Fields():
  match effort:
    case Some{level}: put(fields, "reasoning", effortObject(effortValue(mapping, level)))
    case None{}:
      +off = offMapping(mapping)
      Bool.pick(Fields(), offNotNull(off), put(fields, "reasoning", effortObject(offOrNone(off))), fields)

def antLingEffort(fields: Fields(), value: Maybe<&2, T.Nullable<String>>) -> Fields():
  match value:
    case Some{T.PresentValue{effort}}: put(fields, "reasoning", effortObject(effort))
    case _: fields

# Without a requested effort, Ant Ling falls through to the OpenAI branch.
def antLingReasoning(+fields: Fields(), effort: Maybe<&2, T.ThinkingLevel>, +mapping: Maybe<&2, T.ThinkingLevelMap>, supported: Bool) -> Fields():
  match effort:
    case Some{level}: antLingEffort(fields, mappedLevel(mapping, level))
    case None{}: genericReasoning(fields, None{}, mapping, supported)

def togetherReasoning(fields: Fields(), +effort: Maybe<&2, T.ThinkingLevel>, mapping: Maybe<&2, T.ThinkingLevelMap>, supported: Bool) -> Fields():
  effortWhenSupported(put(fields, "reasoning", obj(field("enabled", T.JsonBoolean{Maybe.is_some(&2, T.ThinkingLevel, effort)}) <> Nil{})), effort, mapping, supported)

def stringThinking(+fields: Fields(), effort: Maybe<&2, T.ThinkingLevel>, +mapping: Maybe<&2, T.ThinkingLevelMap>) -> Fields():
  match effort:
    case Some{level}: put(fields, "thinking", str(effortValue(mapping, level)))
    case None{}:
      +off = offMapping(mapping)
      Bool.pick(Fields(), offNotNull(off), put(fields, "thinking", str(offOrNone(off))), fields)

# upstream buildParams' thinkingFormat branches, for reasoning models.
def formatReasoning(fields: Fields(), format: T.ThinkingFormat, effort: Maybe<&2, T.ThinkingLevel>, mapping: Maybe<&2, T.ThinkingLevelMap>, +compat: Compat(), budget: Maybe<&2, F64>) -> Fields():
  match format:
    case T.ZaiThinking{}: zaiReasoning(fields, effort, mapping, supportsReasoningEffort(compat))
    case T.QwenThinking{}: qwenReasoning(fields, effort, mapping, supportsReasoningEffort(compat))
    case T.QwenChatTemplateThinking{}: put(fields, "chat_template_kwargs", obj(field("enable_thinking", T.JsonBoolean{Maybe.is_some(&2, T.ThinkingLevel, effort)}) <> field("preserve_thinking", T.JsonBoolean{True{}}) <> Nil{}))
    case T.ChatTemplateThinking{}: maybe(fields, "chat_template_kwargs", buildChatTemplateValues(chatTemplateKwargs(compat), effort, mapping, budget))
    case T.BasetenThinking{}: basetenReasoning(fields, effort, mapping, supportsReasoningEffort(compat), chatTemplateArgs(compat), budget)
    case T.DeepSeekThinking{}: deepseekReasoning(fields, effort, mapping, supportsReasoningEffort(compat))
    case T.OpenRouterThinking{}: openRouterReasoning(fields, effort, mapping)
    case T.AntLingThinking{}: antLingReasoning(fields, effort, mapping, supportsReasoningEffort(compat))
    case T.TogetherThinking{}: togetherReasoning(fields, effort, mapping, supportsReasoningEffort(compat))
    case T.StringThinking{}: stringThinking(fields, effort, mapping)
    case T.OpenAIThinking{}: genericReasoning(fields, effort, mapping, supportsReasoningEffort(compat))

def withReasoning(+fields: Fields(), reasoning: Bool, effort: Maybe<&2, T.ThinkingLevel>, mapping: Maybe<&2, T.ThinkingLevelMap>, +compat: Compat(), budget: Maybe<&2, F64>) -> Fields():
  Bool.pick(Fields(), reasoning, formatReasoning(fields, thinkingFormat(compat), effort, mapping, compat, budget), fields)

def budgetFieldName(field: T.ThinkingTokenBudgetField) -> String:
  match field:
    case T.ThinkingTokenBudget{}: "thinking_token_budget"
    case T.ThinkingBudgetField{}: "thinking_budget"
    case T.ThinkingBudgetTokens{}: "thinking_budget_tokens"

def resolveThinkingTokenBudgetField(+compat: Compat()) -> Maybe<&2, T.ThinkingTokenBudgetField>:
  Maybe.or(&2, T.ThinkingTokenBudgetField, thinkingTokenBudgetField(compat), Bool.pick(Maybe<&2, T.ThinkingTokenBudgetField>, supportsThinkingTokenBudget(compat), Some{T.ThinkingTokenBudget{}}, None{}))

def positiveBudget(+budget: F64) -> Maybe<&2, F64>:
  Bool.pick(Maybe<&2, F64>, F.isGreater(F.compare(budget, F.fromU32(0))), Some{budget}, None{})

# upstream resolveClampedThinkingBudget: the level's budget, leaving
# MIN_ANSWER_TOKENS of the response ceiling for the answer.
def resolveClampedThinkingBudget(reasoning: Bool, modelMaxTokens: F64, effort: Maybe<&2, T.ThinkingLevel>, budgets: Maybe<&2, T.ThinkingBudgets>, maxTokens: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match reasoning effort:
    case True{} Some{level}: positiveBudget(Simple.clampThinkingBudgetToAnswerRoom(Simple.thinkingBudgetForLevel(level, budgets), Maybe.default(&2, F64, maxTokens, modelMaxTokens)))
    case _ _: None{}

def withBudget(+fields: Fields(), field: Maybe<&2, T.ThinkingTokenBudgetField>, budget: Maybe<&2, F64>) -> Fields():
  match field budget:
    case Some{name} Some{value}: put(fields, budgetFieldName(name), T.JsonNumber{value})
    case _ _: fields

def jsonStrings(values: List<&2, String>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case first <> rest: str(first) <> jsonStrings(rest)

def stringsJson(values: List<&2, String>) -> J():
  T.JsonArray{jsonStrings(values)}

def withOpenRouterRouting(fields: Fields(), routing: Maybe<&2, T.OpenRouterRouting>) -> Fields():
  match routing:
    case None{}: fields
    case Some{value}: put(fields, "provider", Schema.toJson(ModelJson.openRouterRouting(value)))

def withVercelRouting(+fields: Fields(), routing: Maybe<&2, T.VercelGatewayRouting>) -> Fields():
  match routing:
    case Some{T.VercelGatewayRouting{+only, +order}}:
      +gateway = obj(optionalField("only", Maybe.map(&2, List<&2, String>, J(), stringsJson, only), optionalField("order", Maybe.map(&2, List<&2, String>, J(), stringsJson, order), Nil{})))
      Bool.pick(Fields(), Maybe.is_some(&2, List<&2, String>, only) || Maybe.is_some(&2, List<&2, String>, order), put(fields, "providerOptions", obj(field("gateway", gateway) <> Nil{})), fields)
    case _: fields

# Provider routing comes from the model's own compat, not the resolved one.
def withRouting(fields: Fields(), api: T.ModelApi, compat: Maybe<&2, T.ModelCompatibility(api)>) -> Fields():
  match api compat:
    case T.OpenAICompletionsApi{} Some{T.OpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, _, _, _, openRouter, vercel, _, _, _, _, _, _, _, _, _, _, _, _}}: withVercelRouting(withOpenRouterRouting(fields, openRouter), vercel)
    case _ _: fields

def withSampling(fields: Fields(), sampling: Maybe<&2, R.Record<J()>>) -> Fields():
  match sampling:
    case None{}: fields
    case Some{selected}: Simple.mergeFields(J(), R.entries(J(), selected), fields)

def withChoice(fields: Fields(), choice: Maybe<&2, J()>) -> Fields(): maybe(fields, "tool_choice", choice)

def withPriority(fields: Fields(), priority: Maybe<&2, F64>) -> Fields():
  maybe(fields, "priority", budgetValue(priority))

def ParamsResult() -> Data: Result<&2, &2, Sampling.Error, J()>

def assembleParams(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, +model: T.Model<J()>, options: Options(Signal, Telemetry, Fetch, Error), +compat: Compat(), +retention: T.CacheRetention, marked: Marked) -> J():
  match model options marked:
    case T.Model{id, _, api, _, baseUrl, reasoning, mapping, _, _, _, _, _, modelMax, _, _, modelCompat} OpenAICompletionsOptions{T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, temperature, sampling, maxTokens, _, _, sessionId, _, _}, choice, +effort, budgets} Marked{messages, tools}:
      +selectedMax = truthyNumber(maxTokens)
      +base = {R.Record{field("model", str(id)) <> field("messages", messagesJson(messages)) <> field("stream", T.JsonBoolean{True{}}) <> Nil{}} : Fields()}
      +cached = withPromptCache(base, baseUrl, retention, compat, sessionId)
      +usage = Bool.pick(Fields(), supportsUsageInStreaming(compat), put(cached, "stream_options", obj(field("include_usage", T.JsonBoolean{True{}}) <> Nil{})), cached)
      +stored = Bool.pick(Fields(), supportsStore(compat), put(usage, "store", T.JsonBoolean{False{}}), usage)
      +limited = maybe(stored, maxTokensName(maxTokensField(compat)), budgetValue(selectedMax))
      +sampled = maybe(limited, "temperature", budgetValue(temperature))
      +budget = resolveClampedThinkingBudget(reasoning, modelMax, effort, budgets, selectedMax)
      +reasoned = withReasoning(withPriority(withChoice(withTools(sampled, tools, zaiToolStream(compat)), choice), vllmPriority(compat)), reasoning, effort, mapping, compat, budget)
      obj(R.entries(J(), withSampling(withRouting(withBudget(reasoned, resolveThinkingTokenBudgetField(compat), budget), api, modelCompat), sampling)))

def paramsWithTools(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, +model: T.Model<J()>, options: Options(Signal, Telemetry, Fetch, Error), +compat: Compat(), +retention: T.CacheRetention, messages: List<&2, ChatMessage>, tools: Result<&2, &2, Sampling.Error, RequestTools>) -> ParamsResult():
  match tools:
    case Fail{error}: Fail{error}
    case Done{selected}: Done{assembleParams(Signal, Telemetry, Fetch, Error, model, options, compat, retention, applyAnthropicCacheControl(messages, selected, getCompatCacheControl(compat, retention)))}

def transcriptToolValues(tools: Transcript.TranscriptTools<V.Value>) -> List<&2, T.Tool<V.Value>>:
  match tools:
    case Transcript.TranscriptTools{values, _}: values

def transcriptMessages(-G: Data, -D: Data, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> List<&2, Message(G, D)>:
  match context:
    case T.TranscriptContext{messages}: messages

def paramsFor(-G: Data, -D: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, model: T.Model<J()>, +transcript: List<&2, Message(G, D)>, options: Options(Signal, Telemetry, Fetch, Error), +compat: Compat(), retention: T.CacheRetention, chat: List<&2, ChatMessage>) -> ParamsResult():
  paramsWithTools(Signal, Telemetry, Fetch, Error, model, options, compat, retention, chat, requestTools(transcriptToolValues(Transcript.resolveTranscriptTools(V.Value, V.Value, G, D, transcript, toolAdditions(compat))), hasToolHistory(G, D, transcript), compat))

def paramsWithMessages(-G: Data, -D: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options(Signal, Telemetry, Fetch, Error), compat: Compat(), retention: T.CacheRetention, converted: Converted()) -> ParamsResult():
  match converted:
    case Fail{failure}: Fail{failure}
    case Done{chat}: paramsFor(G, D, Signal, Telemetry, Fetch, Error, model, transcriptMessages(G, D, context), options, compat, retention, chat)

# upstream buildParams, in upstream field order: sampling parameters are
# merged last so custom keys override the named request fields. Fails with
# the first tool the model cannot honor (upstream throws).
def buildParams(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options(Signal, Telemetry, Fetch, Error), +compat: Compat(), retention: T.CacheRetention, grammarToolInputProperties: R.Record<String>) -> IO(ParamsResult()):
  do IO<ParamsResult()>:
    converted : Converted() <- convertMessages(~G, ~D, model, context, compat, grammarToolInputProperties)
    return paramsWithMessages(G, D, Signal, Telemetry, Fetch, Error, model, context, options, compat, retention, converted)

# Client headers
# --------------

# upstream createClient's session-affinity headers.
def affinityFor(format: T.SessionAffinityFormat, +sessionId: String) -> R.Record<String>:
  match format:
    case T.OpenRouterSession{}: R.Record{[R.Property{"x-session-id", sessionId}]}
    case T.OpenAISession{}: R.Record{[R.Property{"session_id", sessionId}, R.Property{"x-client-request-id", sessionId}, R.Property{"x-session-affinity", sessionId}]}
    case T.OpenAINoSession{}: R.Record{[R.Property{"x-client-request-id", sessionId}, R.Property{"x-session-affinity", sessionId}]}

def affinityWhen(enabled: Bool, format: T.SessionAffinityFormat, sessionId: Maybe<&2, String>) -> R.Record<String>:
  match enabled sessionId:
    case True{} Some{SCon{c, cs}}: affinityFor(format, SCon{c, cs})
    case _ _: R.new(String)

def sessionAffinityHeaders(+compat: Compat(), sessionId: Maybe<&2, String>) -> R.Record<String>:
  affinityWhen(sendSessionAffinityHeaders(compat), sessionAffinityFormat(compat), sessionId)

# The request headers applied after the model's: session affinity for the
# caching session id, then the options' headers, which override them.
def clientHeaders(compat: Compat(), sessionId: Maybe<&2, String>, custom: Maybe<&2, T.ProviderHeaders()>) -> Maybe<&2, T.ProviderHeaders()>:
  Some{Headers.overlay(Headers.fromRecord(sessionAffinityHeaders(compat, sessionId)), custom)}

# Unported behavior
# -----------------

# The stream fold still requires a finish_reason (upstream's fallback for
# providers without one is stream-side work), so such models are refused
# before any request is sent.
def modelIssue(model: T.Model<J()>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, supportsFinishReason(getCompat(model)), None{}, Some{"missing finish_reason fallback"})

# Grammar tools are sent as custom tools, whose streamed custom tool-call
# deltas the stream fold does not parse yet.
def grammarIssue(properties: R.Record<String>) -> Maybe<&2, String>:
  match properties:
    case R.Record{Nil{}}: None{}
    case _: Some{"grammar tools"}

import Base
import ../../../ai/src/types.bend as T
import ../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../ai/src/utils/validation-errors.bend as Errors
import ../../../runtime/src/schema.bend as S
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/big-nat.bend as B
import ../../../runtime/src/f64.bend as F

# Immutable, credential-blind models.json snapshot (upstream model-config.ts).
#
# Language-driven adaptations:
# - Entries are typed values rather than frozen JSON objects. `compat` stays a
#   validated JSON object because its meaning depends on each model's api,
#   which is only known during provider composition.
# - Object keys keep their source order; JavaScript's integer-key-first
#   enumeration is not reproduced.
# - JSON syntax errors carry the native parser's reason instead of the
#   JavaScript engine's exception text; the surrounding message is upstream's.
# - The path is used as given; upstream's normalizePath additionally expands
#   `~` and file: URLs, which the agent-directory callers never pass.

# models.json types
# -----------------

type ModelsJsonModel is Data:
  ModelsJsonModel{id: String, name: Maybe<&2, String>, api: Maybe<&2, String>, baseUrl: Maybe<&2, String>, reasoning: Maybe<&2, Bool>, thinkingLevelMap: Maybe<&2, T.ThinkingLevelMap>, input: Maybe<&2, List<&2, T.ModelInput>>, inputLimits: Maybe<&2, T.ModelInputLimits>, cost: Maybe<&2, T.ModelCost>, promptCache: Maybe<&2, T.ModelPromptCache>, contextWindow: Maybe<&2, F64>, maxTokens: Maybe<&2, F64>, samplingParams: Maybe<&2, R.Record<T.JsonValue>>, headers: Maybe<&2, R.Record<String>>, compat: Maybe<&2, V.Value>}

# The override cost's rates are individually optional.
type ModelCostOverride is Data:
  ModelCostOverride{input: Maybe<&2, F64>, output: Maybe<&2, F64>, cacheRead: Maybe<&2, F64>, cacheWrite: Maybe<&2, F64>, tiers: Maybe<&2, List<&2, T.ModelCostTier>>}

type ModelsJsonModelOverride is Data:
  ModelsJsonModelOverride{name: Maybe<&2, String>, reasoning: Maybe<&2, Bool>, thinkingLevelMap: Maybe<&2, T.ThinkingLevelMap>, input: Maybe<&2, List<&2, T.ModelInput>>, inputLimits: Maybe<&2, T.ModelInputLimits>, cost: Maybe<&2, ModelCostOverride>, promptCache: Maybe<&2, T.ModelPromptCache>, contextWindow: Maybe<&2, F64>, maxTokens: Maybe<&2, F64>, samplingParams: Maybe<&2, R.Record<T.JsonValue>>, headers: Maybe<&2, R.Record<String>>, compat: Maybe<&2, V.Value>}

# `oauth` accepts only the literal "radius".
type ProviderOAuth is Data:
  RadiusOAuth{}

type ModelsJsonProvider is Data:
  ModelsJsonProvider{name: Maybe<&2, String>, baseUrl: Maybe<&2, String>, apiKey: Maybe<&2, String>, api: Maybe<&2, String>, oauth: Maybe<&2, ProviderOAuth>, headers: Maybe<&2, R.Record<String>>, compat: Maybe<&2, V.Value>, authHeader: Maybe<&2, Bool>, models: Maybe<&2, List<&2, ModelsJsonModel>>, modelOverrides: Maybe<&2, R.Record<ModelsJsonModelOverride>>}

type ModelConfig is Data:
  ModelConfig{providers: R.Record<ModelsJsonProvider>, error: Maybe<&2, String>}

def empty() -> ModelConfig: ModelConfig{R.new(ModelsJsonProvider), None{}}

def getProvider(config: ModelConfig, providerId: String) -> Maybe<&2, ModelsJsonProvider>:
  match config:
    case ModelConfig{providers, _}: R.get(ModelsJsonProvider, providers, providerId)

def providerKeys(entries: List<&2, R.Property<ModelsJsonProvider>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, _} <> rest: key <> providerKeys(rest)

def getProviderIds(config: ModelConfig) -> List<&2, String>:
  match config:
    case ModelConfig{providers, _}: providerKeys(R.entries(ModelsJsonProvider, providers))

def getError(config: ModelConfig) -> Maybe<&2, String>:
  match config:
    case ModelConfig{_, error}: error

# Comment stripping (upstream utils/json.ts)
# ------------------------------------------

# JavaScript's `\s`: ECMAScript white space and line terminators.
def jsSpace(char: Char) -> Bool:
  match char:
    case Chr{+code}: (U32.is_ge(code, 9) && U32.is_le(code, 13)) || U32.is_eq(code, 32) || U32.is_eq(code, 160) || U32.is_eq(code, 5760) || (U32.is_ge(code, 8192) && U32.is_le(code, 8202)) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233) || U32.is_eq(code, 8239) || U32.is_eq(code, 8287) || U32.is_eq(code, 12288) || U32.is_eq(code, 65279)

# Characters JavaScript's `.` does not match.
def lineTerminator(char: Char) -> Bool:
  match char:
    case Chr{+code}: U32.is_eq(code, 10) || U32.is_eq(code, 13) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233)

type Literal is Data:
  Literal{reversed: String, rest: String}

# The pattern "(?:\\.|[^"\\])*" after its opening quote: the literal's
# characters (reversed, including both quotes) and the text after it; None
# when it never closes or a backslash precedes a line terminator.
def closing(text: String, reversed: String) -> Maybe<&2, Literal>:
  match text:
    case SNil{}: None{}
    case SCon{'"', rest}: Some{Literal{SCon{'"', reversed}, rest}}
    case SCon{'\\', SNil{}}: None{}
    case SCon{'\\', SCon{+c, rest}}: Bool.pick(Unit -> Maybe<&2, Literal>, lineTerminator(c), _ => None{}, _ => closing(rest, SCon{c, SCon{'\\', reversed}}))(Unit{})
    case SCon{c, rest}: closing(rest, SCon{c, reversed})

type Strip is Data:
  Strip{text: String, output: String}

def prepended(text: String, output: String) -> String:
  match text:
    case SNil{}: output
    case SCon{c, rest}: prepended(rest, SCon{c, output})

# An unterminated quote is an ordinary character and scanning resumes after it.
def literalStep(found: Maybe<&2, Literal>, rest: String, output: String) -> Strip:
  match found:
    case None{}: Strip{rest, SCon{'"', output}}
    case Some{Literal{reversed, after}}: Strip{after, String.append(reversed, SCon{'"', output})}

def untilNewline(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'\n', rest}: SCon{'\n', rest}
    case SCon{_, rest}: untilNewline(rest)

def commentStep(text: String, output: String) -> Strip:
  match text:
    case SNil{}: Strip{SNil{}, output}
    case SCon{'"', +rest}: literalStep(closing(rest, ""), rest, output)
    case SCon{'/', SCon{'/', rest}}: Strip{untilNewline(rest), output}
    case SCon{c, rest}: Strip{rest, SCon{c, output}}

def closesAfterSpace(text: String) -> Bool:
  match text:
    case SCon{'}', _}: True{}
    case SCon{']', _}: True{}
    case SCon{c, rest}: jsSpace(c) && closesAfterSpace(rest)
    case SNil{}: False{}

def commaStep(text: String, +output: String) -> Strip:
  match text:
    case SNil{}: Strip{SNil{}, output}
    case SCon{'"', +rest}: literalStep(closing(rest, ""), rest, output)
    case SCon{',', +rest}: Strip{rest, Bool.pick(String, closesAfterSpace(rest), output, SCon{',', output})}
    case SCon{c, rest}: Strip{rest, SCon{c, output}}

# Every step consumes at least one character, so the length bounds the loop.
def commentLoop(fuel: Nat, state: Strip) -> String:
  match fuel state:
    case _ Strip{SNil{}, output}: String.reverse(output)
    case 0n Strip{text, output}: String.reverse(prepended(text, output))
    case 1n+n Strip{text, output}: commentLoop(n, commentStep(text, output))

def commaLoop(fuel: Nat, state: Strip) -> String:
  match fuel state:
    case _ Strip{SNil{}, output}: String.reverse(output)
    case 0n Strip{text, output}: String.reverse(prepended(text, output))
    case 1n+n Strip{text, output}: commaLoop(n, commaStep(text, output))

def withoutComments(+input: String) -> String:
  commentLoop(1n + String.length(input), Strip{input, ""})

# Strip `//` line comments and trailing commas, leaving string literals untouched.
def stripJsonComments(input: String) -> String:
  +uncommented = withoutComments(input)
  commaLoop(1n + String.length(uncommented), Strip{uncommented, ""})

def stripBom(content: String) -> String:
  match content:
    case SCon{Chr{65279}, rest}: rest
    case other: other

# Schema (TypeBox ModelsConfigSchema)
# -----------------------------------

# The native checker has no patternProperties node. A string-keyed record is
# checked as an object that declares each present key with the entry schema,
# which yields the same issues in the same order.
def one() -> B.BigNat: B.fromU32(1)

def string() -> S.Schema: S.JsonKind{S.StringType{}}
def number() -> S.Schema: S.JsonKind{S.NumberType{}}
def boolean() -> S.Schema: S.JsonKind{S.BooleanType{}}
def nullSchema() -> S.Schema: S.JsonKind{S.NullType{}}
def nonEmpty() -> S.Schema: S.All{[string(), S.StringLength{S.CountBounds{one(), None{}}}]}
def literal(value: String) -> S.Schema: S.All{[string(), S.Constant{V.Text{value}}]}
def positiveInteger() -> S.Schema: S.All{[S.JsonKind{S.IntegerType{}}, S.Minimum{F.fromU32(1), True{}}]}
def positiveNumber() -> S.Schema: S.All{[number(), S.Minimum{F.fromU32(0), False{}}]}
def stringOrNull() -> S.Schema: S.Any{[string(), nullSchema()]}
def numberOrString() -> S.Schema: S.Any{[number(), string()]}

def literalSchemas(values: List<&2, String>) -> List<&2, S.Schema>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: literal(value) <> literalSchemas(rest)

def literals(values: List<&2, String>) -> S.Schema: S.Any{literalSchemas(values)}

def array(items: S.Schema) -> S.Schema: S.All{[S.JsonKind{S.ArrayType{}}, S.Array{Nil{}, items}]}
def strings() -> S.Schema: array(string())

def object(properties: List<&2, R.Property<S.Schema>>, required: List<&2, String>) -> S.Schema:
  S.All{[S.JsonKind{S.ObjectType{}}, S.Object{R.Record{properties}, required, S.Accept{}}]}

def field(key: String, schema: S.Schema) -> R.Property<S.Schema>: R.Property{key, schema}

def entriesOf(value: Maybe<&2, V.Value>) -> List<&2, R.Property<V.Value>>:
  match value:
    case Some{V.ObjectValue{properties}}: R.entries(V.Value, properties)
    case _: Nil{}

def member(value: Maybe<&2, V.Value>, key: String) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.ObjectValue{properties}}: R.get(V.Value, properties, key)
    case _: None{}

def itemsOf(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{values}}: values
    case _: Nil{}

def recordFields(entries: List<&2, R.Property<V.Value>>, +schema: S.Schema) -> List<&2, R.Property<S.Schema>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, _} <> rest: field(key, schema) <> recordFields(rest, schema)

def record(value: Maybe<&2, V.Value>, schema: S.Schema) -> S.Schema:
  object(recordFields(entriesOf(value), schema), Nil{})

def percentileCutoffs() -> S.Schema:
  object([field("p50", number()), field("p75", number()), field("p90", number()), field("p99", number())], Nil{})

def openRouterRouting() -> S.Schema:
  +sort = {S.Any{[string(), object([field("by", string()), field("partition", stringOrNull())], Nil{})]} : S.Schema}
  +maxPrice = object([field("prompt", numberOrString()), field("completion", numberOrString()), field("image", numberOrString()), field("audio", numberOrString()), field("request", numberOrString())], Nil{})
  +preference = {S.Any{[number(), percentileCutoffs()]} : S.Schema}
  object([field("allow_fallbacks", boolean()), field("require_parameters", boolean()), field("data_collection", literals(["deny", "allow"])), field("zdr", boolean()), field("enforce_distillable_text", boolean()), field("order", strings()), field("only", strings()), field("ignore", strings()), field("quantizations", strings()), field("sort", sort), field("max_price", maxPrice), field("preferred_min_throughput", preference), field("preferred_max_latency", preference)], Nil{})

def vercelGatewayRouting() -> S.Schema:
  object([field("only", strings()), field("order", strings())], Nil{})

def thinkingLevelMap() -> S.Schema:
  object([field("off", stringOrNull()), field("minimal", stringOrNull()), field("low", stringOrNull()), field("medium", stringOrNull()), field("high", stringOrNull()), field("xhigh", stringOrNull()), field("max", stringOrNull())], Nil{})

def chatTemplateKwarg() -> S.Schema:
  +scalar = {S.Any{[string(), number(), boolean(), nullSchema()]} : S.Schema}
  +variable = object([field("$var", literals(["thinking.enabled", "thinking.effort"])), field("omitWhenOff", boolean())], ["$var"])
  S.Any{[scalar, variable]}

def sessionAffinityFormat() -> S.Schema: literals(["openai", "openai-nosession", "openrouter"])

def openAICompletionsCompat(+value: Maybe<&2, V.Value>) -> S.Schema:
  +thinkingFormat = literals(["openai", "openrouter", "together", "baseten", "deepseek", "zai", "qwen", "chat-template", "qwen-chat-template", "string-thinking", "ant-ling"])
  object([field("supportsStore", boolean()), field("supportsDeveloperRole", boolean()), field("supportsReasoningEffort", boolean()), field("supportsUsageInStreaming", boolean()), field("supportsFinishReason", boolean()), field("maxTokensField", literals(["max_completion_tokens", "max_tokens"])), field("requiresToolResultName", boolean()), field("requiresAssistantAfterToolResult", boolean()), field("requiresThinkingAsText", boolean()), field("requiresReasoningContentOnAssistantMessages", boolean()), field("thinkingFormat", thinkingFormat), field("chatTemplateKwargs", record(member(value, "chatTemplateKwargs"), chatTemplateKwarg())), field("chatTemplateArgs", record(member(value, "chatTemplateArgs"), chatTemplateKwarg())), field("cacheControlFormat", literal("anthropic")), field("openRouterRouting", openRouterRouting()), field("vercelGatewayRouting", vercelGatewayRouting()), field("supportsOpenAIGrammarTools", boolean()), field("supportsStrictMode", boolean()), field("sendSessionAffinityHeaders", boolean()), field("sessionAffinityFormat", sessionAffinityFormat()), field("supportsLongCacheRetention", boolean()), field("vllmPriority", number())], Nil{})

def openAIResponsesCompat() -> S.Schema:
  object([field("supportsDeveloperRole", boolean()), field("sessionAffinityFormat", sessionAffinityFormat()), field("supportsLongCacheRetention", boolean()), field("supportsStrictMode", boolean()), field("supportsOpenAIGrammarTools", boolean()), field("supportsMaxOutputTokens", boolean())], Nil{})

def costRates() -> List<&2, R.Property<S.Schema>>:
  [field("input", number()), field("output", number()), field("cacheRead", number()), field("cacheWrite", number())]

def costTier() -> S.Schema:
  object(field("inputTokensAbove", number()) <> costRates(), ["inputTokensAbove", "input", "output", "cacheRead", "cacheWrite"])

def modelCost() -> S.Schema:
  object(List.append(&2, R.Property<S.Schema>, costRates(), [field("tiers", array(costTier()))]), ["input", "output", "cacheRead", "cacheWrite"])

def promptCache() -> S.Schema:
  object([field("short", positiveNumber()), field("long", positiveNumber())], Nil{})

def inputLimits() -> S.Schema:
  +quality = {S.All{[S.JsonKind{S.IntegerType{}}, S.Minimum{F.fromU32(1), True{}}, S.Maximum{F.fromU32(100), True{}}]} : S.Schema}
  +resize = object([field("maxWidth", positiveInteger()), field("maxHeight", positiveInteger()), field("maxBytes", positiveInteger()), field("jpegQuality", quality)], Nil{})
  +images = object([field("resize", resize), field("maxPerMessage", positiveInteger()), field("maxPerRequest", positiveInteger())], Nil{})
  object([field("maxRequestBytes", positiveInteger()), field("images", images)], Nil{})

def anthropicMessagesCompat() -> S.Schema:
  +fallback = object([field("provider", nonEmpty()), field("model", nonEmpty()), field("cost", modelCost())], ["provider", "model", "cost"])
  +fallbacks = {S.All{[S.JsonKind{S.ArrayType{}}, S.Array{Nil{}, fallback}, S.ItemCount{S.CountBounds{B.zero(), Some{B.fromU32(3)}}}]} : S.Schema}
  object([field("supportsEagerToolInputStreaming", boolean()), field("supportsLongCacheRetention", boolean()), field("sendSessionAffinityHeaders", boolean()), field("supportsCacheControlOnTools", boolean()), field("supportsTemperature", boolean()), field("forceAdaptiveThinking", boolean()), field("allowEmptySignature", boolean()), field("supportsStrictTools", boolean()), field("supportsMidConvoEffort", boolean()), field("allowedFallbackModels", fallbacks)], Nil{})

def providerCompat(value: Maybe<&2, V.Value>) -> S.Schema:
  S.Any{[openAICompletionsCompat(value), openAIResponsesCompat(), anthropicMessagesCompat()]}

def inputs() -> S.Schema: array(literals(["text", "image"]))

def modelDefinition(+value: Maybe<&2, V.Value>) -> S.Schema:
  object([field("id", nonEmpty()), field("name", nonEmpty()), field("api", nonEmpty()), field("baseUrl", nonEmpty()), field("reasoning", boolean()), field("thinkingLevelMap", thinkingLevelMap()), field("input", inputs()), field("inputLimits", inputLimits()), field("cost", modelCost()), field("promptCache", promptCache()), field("contextWindow", number()), field("maxTokens", number()), field("samplingParams", record(member(value, "samplingParams"), S.Accept{})), field("headers", record(member(value, "headers"), string())), field("compat", providerCompat(member(value, "compat")))], ["id"])

def modelOverride(+value: Maybe<&2, V.Value>) -> S.Schema:
  +cost = object([field("input", number()), field("output", number()), field("cacheRead", number()), field("cacheWrite", number()), field("tiers", array(costTier()))], Nil{})
  object([field("name", nonEmpty()), field("reasoning", boolean()), field("thinkingLevelMap", thinkingLevelMap()), field("input", inputs()), field("inputLimits", inputLimits()), field("cost", cost), field("promptCache", promptCache()), field("contextWindow", number()), field("maxTokens", number()), field("samplingParams", record(member(value, "samplingParams"), S.Accept{})), field("headers", record(member(value, "headers"), string())), field("compat", providerCompat(member(value, "compat")))], Nil{})

def modelDefinitions(values: List<&2, V.Value>) -> List<&2, S.Schema>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: modelDefinition(Some{value}) <> modelDefinitions(rest)

def modelOverrideFields(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<S.Schema>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: field(key, modelOverride(Some{value})) <> modelOverrideFields(rest)

def providerConfig(+value: Maybe<&2, V.Value>) -> S.Schema:
  +models = {S.All{[S.JsonKind{S.ArrayType{}}, S.Array{modelDefinitions(itemsOf(member(value, "models"))), S.Accept{}}]} : S.Schema}
  +overrides = object(modelOverrideFields(entriesOf(member(value, "modelOverrides"))), Nil{})
  object([field("name", nonEmpty()), field("baseUrl", nonEmpty()), field("apiKey", nonEmpty()), field("api", nonEmpty()), field("oauth", literal("radius")), field("headers", record(member(value, "headers"), string())), field("compat", providerCompat(member(value, "compat"))), field("authHeader", boolean()), field("models", models), field("modelOverrides", overrides)], Nil{})

def providerFields(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<S.Schema>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: field(key, providerConfig(Some{value})) <> providerFields(rest)

def modelsConfigSchema(value: V.Value) -> S.Schema:
  object([field("providers", object(providerFields(entriesOf(member(Some{value}, "providers"))), Nil{}))], ["providers"])

# TypeBox's default error capacity.
def errorLimit() -> Nat: 8n

def schemaErrors(issues: Maybe<&2, List<&2, Errors.Issue>>) -> String:
  match issues:
    case Some{head <> rest}: String.join(Errors.lines(head <> rest), "\n")
    case _: "Unknown schema error"

# Decoding (after validation)
# ---------------------------

def fieldsOf(value: Maybe<&2, V.Value>) -> R.Record<V.Value>:
  match value:
    case Some{V.ObjectValue{properties}}: properties
    case _: R.new(V.Value)

def textValue(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{t}}: Some{t}
    case _: None{}

def numberValue(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{n}}: Some{n}
    case _: None{}

def boolValue(value: Maybe<&2, V.Value>) -> Maybe<&2, Bool>:
  match value:
    case Some{V.Boolean{b}}: Some{b}
    case _: None{}

def textAt(fields: R.Record<V.Value>, key: String) -> Maybe<&2, String>: textValue(R.get(V.Value, fields, key))
def numberAt(fields: R.Record<V.Value>, key: String) -> Maybe<&2, F64>: numberValue(R.get(V.Value, fields, key))
def flagAt(fields: R.Record<V.Value>, key: String) -> Maybe<&2, Bool>: boolValue(R.get(V.Value, fields, key))
def zero() -> F64: F.fromU32(0)
def rate(fields: R.Record<V.Value>, key: String) -> F64: Maybe.default(&2, F64, numberAt(fields, key), zero())

def thinkingLevel(key: String) -> Maybe<&2, T.ModelThinkingLevel>:
  match key:
    case "off": Some{T.Off{}}
    case "minimal": Some{T.Thinking{T.Minimal{}}}
    case "low": Some{T.Thinking{T.Low{}}}
    case "medium": Some{T.Thinking{T.Medium{}}}
    case "high": Some{T.Thinking{T.High{}}}
    case "xhigh": Some{T.Thinking{T.XHigh{}}}
    case "max": Some{T.Thinking{T.Max{}}}
    case _: None{}

def mappingValue(value: V.Value) -> T.Nullable<String>:
  match value:
    case V.Text{t}: T.PresentValue{t}
    case _: T.NullValue{}

def mappingOf(level: Maybe<&2, T.ModelThinkingLevel>, value: V.Value, rest: List<&2, T.ThinkingLevelMapping>) -> List<&2, T.ThinkingLevelMapping>:
  match level:
    case None{}: rest
    case Some{level}: T.ThinkingLevelMapping{level, Some{mappingValue(value)}} <> rest

def mappings(entries: List<&2, R.Property<V.Value>>) -> List<&2, T.ThinkingLevelMapping>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{+key, value} <> rest: mappingOf(thinkingLevel(key), value, mappings(rest))

def thinkingLevelMapOf(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ThinkingLevelMap>:
  match value:
    case Some{V.ObjectValue{properties}}: Some{T.ThinkingLevelMap{mappings(R.entries(V.Value, properties))}}
    case _: None{}

def inputValues(values: List<&2, V.Value>) -> List<&2, T.ModelInput>:
  match values:
    case Nil{}: Nil{}
    case V.Text{"image"} <> rest: T.InputImage{} <> inputValues(rest)
    case _ <> rest: T.InputText{} <> inputValues(rest)

def inputsOf(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, T.ModelInput>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{inputValues(values)}
    case _: None{}

def resizeOf(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ModelImageResizeOptions>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{T.ModelImageResizeOptions{numberAt(fields, "maxWidth"), numberAt(fields, "maxHeight"), numberAt(fields, "maxBytes"), numberAt(fields, "jpegQuality")}}
    case _: None{}

def imagesOf(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ModelImageInputLimits>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{T.ModelImageInputLimits{resizeOf(R.get(V.Value, fields, "resize")), numberAt(fields, "maxPerMessage"), numberAt(fields, "maxPerRequest")}}
    case _: None{}

def inputLimitsOf(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ModelInputLimits>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{T.ModelInputLimits{numberAt(fields, "maxRequestBytes"), imagesOf(R.get(V.Value, fields, "images"))}}
    case _: None{}

def costTierOf(value: V.Value) -> T.ModelCostTier:
  +fields = fieldsOf(Some{value})
  T.ModelCostTier{rate(fields, "input"), rate(fields, "output"), rate(fields, "cacheRead"), rate(fields, "cacheWrite"), rate(fields, "inputTokensAbove")}

def costTierValues(values: List<&2, V.Value>) -> List<&2, T.ModelCostTier>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: costTierOf(value) <> costTierValues(rest)

def tiersOf(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, T.ModelCostTier>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{costTierValues(values)}
    case _: None{}

def costOf(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ModelCost>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{T.ModelCost{rate(fields, "input"), rate(fields, "output"), rate(fields, "cacheRead"), rate(fields, "cacheWrite"), tiersOf(R.get(V.Value, fields, "tiers"))}}
    case _: None{}

def costOverrideOf(value: Maybe<&2, V.Value>) -> Maybe<&2, ModelCostOverride>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{ModelCostOverride{numberAt(fields, "input"), numberAt(fields, "output"), numberAt(fields, "cacheRead"), numberAt(fields, "cacheWrite"), tiersOf(R.get(V.Value, fields, "tiers"))}}
    case _: None{}

def promptCacheOf(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ModelPromptCache>:
  match value:
    case Some{V.ObjectValue{+fields}}: Some{T.ModelPromptCache{numberAt(fields, "short"), numberAt(fields, "long")}}
    case _: None{}

def jsonEntries(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<T.JsonValue>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, SchemaJson.toJson(value)} <> jsonEntries(rest)

def samplingOf(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<T.JsonValue>>:
  match value:
    case Some{V.ObjectValue{properties}}: Some{R.Record{jsonEntries(R.entries(V.Value, properties))}}
    case _: None{}

def textEntries(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<String>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, V.Text{value}} <> rest: R.Property{key, value} <> textEntries(rest)
    case _ <> rest: textEntries(rest)

def headersOf(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<String>>:
  match value:
    case Some{V.ObjectValue{properties}}: Some{R.Record{textEntries(R.entries(V.Value, properties))}}
    case _: None{}

def modelOf(value: V.Value) -> ModelsJsonModel:
  +fields = fieldsOf(Some{value})
  ModelsJsonModel{Maybe.default(&2, String, textAt(fields, "id"), ""), textAt(fields, "name"), textAt(fields, "api"), textAt(fields, "baseUrl"), flagAt(fields, "reasoning"), thinkingLevelMapOf(R.get(V.Value, fields, "thinkingLevelMap")), inputsOf(R.get(V.Value, fields, "input")), inputLimitsOf(R.get(V.Value, fields, "inputLimits")), costOf(R.get(V.Value, fields, "cost")), promptCacheOf(R.get(V.Value, fields, "promptCache")), numberAt(fields, "contextWindow"), numberAt(fields, "maxTokens"), samplingOf(R.get(V.Value, fields, "samplingParams")), headersOf(R.get(V.Value, fields, "headers")), R.get(V.Value, fields, "compat")}

def modelValues(values: List<&2, V.Value>) -> List<&2, ModelsJsonModel>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: modelOf(value) <> modelValues(rest)

def modelsOf(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, ModelsJsonModel>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{modelValues(values)}
    case _: None{}

def overrideOf(value: V.Value) -> ModelsJsonModelOverride:
  +fields = fieldsOf(Some{value})
  ModelsJsonModelOverride{textAt(fields, "name"), flagAt(fields, "reasoning"), thinkingLevelMapOf(R.get(V.Value, fields, "thinkingLevelMap")), inputsOf(R.get(V.Value, fields, "input")), inputLimitsOf(R.get(V.Value, fields, "inputLimits")), costOverrideOf(R.get(V.Value, fields, "cost")), promptCacheOf(R.get(V.Value, fields, "promptCache")), numberAt(fields, "contextWindow"), numberAt(fields, "maxTokens"), samplingOf(R.get(V.Value, fields, "samplingParams")), headersOf(R.get(V.Value, fields, "headers")), R.get(V.Value, fields, "compat")}

def overrideEntries(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<ModelsJsonModelOverride>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, overrideOf(value)} <> overrideEntries(rest)

def overridesOf(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<ModelsJsonModelOverride>>:
  match value:
    case Some{V.ObjectValue{properties}}: Some{R.Record{overrideEntries(R.entries(V.Value, properties))}}
    case _: None{}

def oauthOf(value: Maybe<&2, V.Value>) -> Maybe<&2, ProviderOAuth>:
  match value:
    case Some{V.Text{"radius"}}: Some{RadiusOAuth{}}
    case _: None{}

def providerOf(value: V.Value) -> ModelsJsonProvider:
  +fields = fieldsOf(Some{value})
  ModelsJsonProvider{textAt(fields, "name"), textAt(fields, "baseUrl"), textAt(fields, "apiKey"), textAt(fields, "api"), oauthOf(R.get(V.Value, fields, "oauth")), headersOf(R.get(V.Value, fields, "headers")), R.get(V.Value, fields, "compat"), flagAt(fields, "authHeader"), modelsOf(R.get(V.Value, fields, "models")), overridesOf(R.get(V.Value, fields, "modelOverrides"))}

def providerEntries(entries: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<ModelsJsonProvider>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: R.Property{key, providerOf(value)} <> providerEntries(rest)

# Loading
# -------

def failed(message: String) -> ModelConfig: ModelConfig{R.new(ModelsJsonProvider), Some{message}}

def fileSuffix(path: String) -> String: "\n\nFile: " ++ path

def validated(+value: V.Value, +path: String) -> ModelConfig:
  +schema = modelsConfigSchema(value)
  Bool.pick(Unit -> ModelConfig, S.check(schema, value),
    _ => ModelConfig{R.Record{providerEntries(entriesOf(member(Some{value}, "providers")))}, None{}},
    _ => failed("Invalid models.json schema:\n" ++ schemaErrors(Errors.fromNative(S.errorsLimited(schema, value, errorLimit()))) ++ fileSuffix(path)))(Unit{})

def parseReason(error: Json.ParseError) -> String:
  match error:
    case Json.ParseInvalidValue{}: "Invalid value"
    case Json.InvalidEscape{}: "Invalid escape"
    case Json.UnescapedControl{}: "Unescaped control character in string"
    case Json.UnterminatedString{}: "Unterminated string"
    case Json.UnexpectedToken{}: "Unexpected token"
    case Json.UnexpectedEnd{}: "Unexpected end of JSON input"
    case Json.TrailingInput{}: "Unexpected non-whitespace character after JSON"
    case Json.InputLimit{}: "Input limit exceeded"

def parsed(result: Result<&2, &2, Json.ParseError, V.Value>, +path: String) -> ModelConfig:
  match result:
    case Fail{error}: failed("Failed to parse models.json: " ++ parseReason(error) ++ fileSuffix(path))
    case Done{value}: validated(value, path)

# Node's fs message: reading a directory fails in read(2), other failures in open(2).
def readError(error: FS.Error, +path: String) -> String:
  match error:
    case FS.System{21, _}: "EISDIR: illegal operation on a directory, read"
    case FS.System{code, _}: FS.nodeMessage(code, "open", path)
    case other: FS.errorMessage(other)

def loaded(result: Result<&2, &2, FS.Error, List<&2, U32>>, +path: String) -> ModelConfig:
  match result:
    case Fail{FS.System{2, _}}: empty()
    case Fail{error}: failed("Failed to load models.json: " ++ readError(error, path) ++ fileSuffix(path))
    case Done{bytes}: parsed(Json.parse(stripJsonComments(stripBom(Utf8.decodeBuffer(bytes)))), path)

# A missing file is an empty configuration; read, parse and schema failures
# leave no providers and record the error.
def load(modelsJsonPath: Maybe<&2, String>) -> IO(ModelConfig):
  match modelsJsonPath:
    case None{}: IO.pure(ModelConfig, empty())
    case Some{SNil{}}: IO.pure(ModelConfig, empty())
    case Some{+path}:
      do IO<ModelConfig>:
        result : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
        return loaded(result, path)

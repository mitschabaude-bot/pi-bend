import Base
import ../types.bend as T
import ../utils/json.bend as Wire
import ../utils/schema-json.bend as Schema
import ../utils/text.bend as Text
import ../utils/transcript.bend as Transcript
import ../utils/thinking-levels.bend as Levels
import ../utils/sanitize-unicode.bend as Unicode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/f64.bend as F

# Chat Completions request values; transport and SSE state live separately.
def J() -> Data: T.JsonValue
def Fields() -> Data: R.Record<J()>
def str(value: String) -> J(): T.JsonString{value}
def obj(fields: Fields()) -> J(): T.JsonObject{fields}
def field(name: String, value: J()) -> R.Property<J()>: R.Property{name, value}
def put(fields: Fields(), name: String, value: J()) -> Fields(): R.set(J(), fields, name, value)
def maybe(fields: Fields(), name: String, value: Maybe<&2, J()>) -> Fields():
  match value:
    case None{}: fields
    case Some{item}: put(fields, name, item)
def number(value: Maybe<&2, F64>) -> Maybe<&2, J()>:
  match value:
    case None{}: None{}
    case Some{item}: Some{T.JsonNumber{item}}

type Options is Data:
  Options{maxTokens: Maybe<&2, F64>, temperature: Maybe<&2, F64>, toolChoice: Maybe<&2, T.ToolChoice>, reasoningEffort: Maybe<&2, String>, reasoningRequested: Bool}

type ThinkingWire is Data:
  StandardThinking{}
  OpenRouterWire{}
  TogetherWire{}

type Behavior is Data:
  Behavior{legacyMaxTokens: Bool, supportsStore: Bool, supportsDeveloperRole: Bool, supportsUsageInStreaming: Bool, supportsReasoningEffort: Bool, thinkingWire: ThinkingWire}

def detectedWire(provider: String, +base: String) -> ThinkingWire:
  match provider:
    case "openrouter": OpenRouterWire{}
    case "together": TogetherWire{}
    case _: Bool.pick(ThinkingWire, String.contains(base, "openrouter.ai"), OpenRouterWire{}, Bool.pick(ThinkingWire, String.contains(base, "api.together.ai") || String.contains(base, "api.together.xyz"), TogetherWire{}, StandardThinking{}))

def selectedWire(value: Maybe<&2, T.ThinkingFormat>, fallback: ThinkingWire) -> ThinkingWire:
  match value:
    case Some{T.OpenRouterThinking{}}: OpenRouterWire{}
    case Some{T.TogetherThinking{}}: TogetherWire{}
    case Some{T.OpenAIThinking{}}: StandardThinking{}
    case _: fallback

def boolean(value: Maybe<&2, Bool>, fallback: Bool) -> Bool: Maybe.default(&2, Bool, value, fallback)
def legacyField(value: Maybe<&2, T.MaxTokensField>, fallback: Bool) -> Bool:
  match value:
    case None{}: fallback
    case Some{T.MaxTokens{}}: True{}
    case Some{T.MaxCompletionTokens{}}: False{}

def detected(+provider: String, +base: String, +id: String, reasoning: Bool) -> Behavior:
  +nonStandard = String.eq(provider, "zai") || String.eq(provider, "zai-coding-cn") || String.eq(provider, "together") || String.eq(provider, "deepseek") || String.eq(provider, "moonshotai") || String.eq(provider, "moonshotai-cn") || String.eq(provider, "nvidia") || String.eq(provider, "cerebras") || String.eq(provider, "xai") || String.eq(provider, "opencode") || String.eq(provider, "cloudflare-workers-ai") || String.eq(provider, "cloudflare-ai-gateway") || String.eq(provider, "ant-ling") || String.contains(base, "chutes.ai") || String.contains(base, "api.together.ai") || String.contains(base, "deepseek.com") || String.contains(base, "api.z.ai") || String.contains(base, "api.x.ai")
  +legacy = String.eq(provider, "deepseek") || String.eq(provider, "together") || String.eq(provider, "zai") || String.eq(provider, "moonshotai") || String.contains(base, "chutes.ai") || String.contains(base, "api.together.ai") || String.contains(base, "deepseek.com")
  +router = String.eq(provider, "openrouter") || String.contains(base, "openrouter.ai")
  +developer = reasoning && ((Bool.not(nonStandard) && Bool.not(router)) || (router && (String.starts_with(id, "openai/") || String.starts_with(id, "anthropic/"))))
  +effort = Bool.not(String.eq(provider, "xai") || String.eq(provider, "zai") || String.eq(provider, "zai-coding-cn") || String.eq(provider, "moonshotai") || String.eq(provider, "moonshotai-cn") || String.eq(provider, "together") || String.eq(provider, "cloudflare-ai-gateway") || String.eq(provider, "nvidia") || String.eq(provider, "ant-ling"))
  Behavior{legacy, Bool.not(nonStandard), developer, True{}, effort, detectedWire(provider, base)}

def overrides(api: T.ModelApi, compat: Maybe<&2, T.ModelCompatibility(api)>, default: Behavior, reasoning: Bool) -> Behavior:
  match api compat default:
    case T.OpenAICompletionsApi{} Some{T.OpenAICompletionsCompat{store, developer, effort, usage, _, selectedField, _, _, _, _, format, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}} Behavior{legacy, defaultStore, defaultDeveloper, defaultUsage, defaultEffort, wire}:
      Behavior{legacyField(selectedField, legacy), boolean(store, defaultStore), reasoning && boolean(developer, defaultDeveloper), boolean(usage, defaultUsage), boolean(effort, defaultEffort), selectedWire(format, wire)}
    case _ _ fallback: fallback

def behavior(model: T.Model<J()>) -> Behavior:
  match model:
    case T.Model{id, _, api, provider, base, +reasoning, _, _, _, _, _, _, _, _, _, compat}: overrides(api, compat, detected(provider, base, id, reasoning), reasoning)

def enabled(value: Maybe<&2, Bool>) -> Bool:
  match value:
    case Some{True{}}: True{}
    case _: False{}
def issue(needed: Bool, description: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, needed, Some{description}, rest)
def defaultThinking(value: Maybe<&2, T.ThinkingFormat>) -> Bool:
  match value:
    case None{}: True{}
    case Some{T.OpenAIThinking{}}: True{}
    case Some{T.OpenRouterThinking{}}: True{}
    case Some{T.TogetherThinking{}}: True{}
    case _: False{}

# Do not silently drop model-specific compatibility requirements that this
# common wire path has not implemented yet.
def compatibilityIssue(api: T.ModelApi, compat: Maybe<&2, T.ModelCompatibility(api)>) -> Maybe<&2, String>:
  match api compat:
    case T.OpenAICompletionsApi{} Some{T.OpenAICompletionsCompat{_, _, _, _, finish, _, toolName, assistantAfter, thinkingText, reasoningContent, thinkingFormat, kwargs, args, openRouter, vercel, zaiStream, budgetField, budget, grammar, midSystem, midTools, strict, cacheFormat, affinity, _, _, priority}}:
      +a = issue(enabled(toolName), "requiresToolResultName", None{})
      +b = issue(enabled(assistantAfter), "requiresAssistantAfterToolResult", a)
      +c = issue(enabled(thinkingText), "requiresThinkingAsText", b)
      +d = issue(enabled(reasoningContent), "requiresReasoningContentOnAssistantMessages", c)
      +e = issue(Bool.not(defaultThinking(thinkingFormat)), "thinkingFormat", d)
      +f = issue(Maybe.is_some(&2, R.Record<T.ChatTemplateKwargValue>, kwargs) || Maybe.is_some(&2, R.Record<T.ChatTemplateKwargValue>, args), "chatTemplateKwargs", e)
      +g = issue(Maybe.is_some(&2, T.OpenRouterRouting, openRouter) || Maybe.is_some(&2, T.VercelGatewayRouting, vercel), "provider routing", f)
      +h = issue(enabled(zaiStream), "zaiToolStream", g)
      +i = issue(Maybe.is_some(&2, T.ThinkingTokenBudgetField, budgetField) || enabled(budget), "thinking token budget", h)
      +j = issue(enabled(grammar), "grammar tools", i)
      +k = issue(enabled(midSystem) || enabled(midTools), "mid-conversation updates", j)
      +l = issue(enabled(strict), "strict tool schemas", k)
      +m = issue(Maybe.is_some(&2, T.CacheControlFormat, cacheFormat), "cache control", l)
      +n = issue(enabled(affinity), "session affinity headers", m)
      +o = issue(Maybe.is_some(&2, F64, priority), "vllm priority", n)
      issue(Bool.not(boolean(finish, True{})), "missing finish_reason fallback", o)
    case _ _: None{}

def automaticThinkingIssue(+provider: String, +base: String, reasoning: Bool) -> Maybe<&2, String>:
  match reasoning:
    case False{}: None{}
    case True{}:
      +deepseek = String.eq(provider, "deepseek") || String.contains(base, "deepseek.com")
      +zai = String.eq(provider, "zai") || String.eq(provider, "zai-coding-cn") || String.contains(base, "api.z.ai") || String.contains(base, "open.bigmodel.cn")
      +antLing = String.eq(provider, "ant-ling") || String.contains(base, "api.ant-ling.com")
      issue(deepseek || zai || antLing, "auto-detected provider thinking format", None{})

def automaticIssue(provider: String, base: String, reasoning: Bool, compat: Maybe<&2, T.OpenAICompletionsCompat>) -> Maybe<&2, String>:
  match compat:
    case Some{T.OpenAICompletionsCompat{_, _, _, _, _, _, _, _, _, _, Some{_}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: None{}
    case _: automaticThinkingIssue(provider, base, reasoning)

def combinedIssue(explicit: Maybe<&2, String>, automatic: Maybe<&2, String>) -> Maybe<&2, String>:
  match explicit:
    case Some{message}: Some{message}
    case None{}: automatic

def modelIssue(model: T.Model<J()>) -> Maybe<&2, String>:
  match model:
    case T.Model{_, _, T.OpenAICompletionsApi{}, provider, base, reasoning, _, _, _, _, _, _, _, _, _, +compat}:
      combinedIssue(compatibilityIssue(T.OpenAICompletionsApi{}, compat), automaticIssue(provider, base, reasoning, compat))
    case _: None{}

def userPart(part: T.TextImageContent) -> J():
  match part:
    case T.TextImageText{T.TextContent{text, _}}: obj(R.Record{field("type", str("text")) <> field("text", str(Unicode.sanitizeSurrogates(text))) <> Nil{}})
    case T.TextImageImage{T.ImageContent{data, mime}}: obj(R.Record{field("type", str("image_url")) <> field("image_url", obj(R.Record{field("url", str("data:" ++ mime ++ ";base64," ++ data)) <> Nil{}})) <> Nil{}})

def userParts(parts: List<&2, T.TextImageContent>) -> List<&2, J()>:
  match parts:
    case Nil{}: Nil{}
    case T.TextImageText{T.TextContent{SNil{}, _}} <> rest: userParts(rest)
    case first <> rest: userPart(first) <> userParts(rest)

def user(value: T.UserContent) -> Maybe<&2, J()>:
  match value:
    case T.UserText{text}: Some{obj(R.Record{field("role", str("user")) <> field("content", str(Unicode.sanitizeSurrogates(text))) <> Nil{}})}
    case T.UserBlocks{parts}:
      +encoded = userParts(parts)
      Bool.pick(Maybe<&2, J()>, List.is_empty(&2, J(), encoded), None{}, Some{obj(R.Record{field("role", str("user")) <> field("content", T.JsonArray{encoded}) <> Nil{}})})

def textParts(parts: List<&2, T.AssistantContent<V.Value>>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case T.AssistantText{T.TextContent{text, _}} <> rest: text <> textParts(rest)
    case _ <> rest: textParts(rest)

def call(part: T.ToolCall<V.Value>) -> J():
  match part:
    case T.ToolCall{id, name, arguments, _, _}:
      +wire = Maybe.default(&2, String, Wire.stringify(Schema.toJson(arguments)), "{}")
      obj(R.Record{field("id", str(id)) <> field("type", str("function")) <> field("function", obj(R.Record{field("name", str(name)) <> field("arguments", str(wire)) <> Nil{}})) <> Nil{}})

def calls(parts: List<&2, T.AssistantContent<V.Value>>) -> List<&2, J()>:
  match parts:
    case Nil{}: Nil{}
    case T.AssistantToolCall{tool} <> rest: call(tool) <> calls(rest)
    case _ <> rest: calls(rest)

def assistantWith(+rendered: String, +found: List<&2, J()>) -> Maybe<&2, J()>:
  match rendered found:
    case SNil{} Nil{}: None{}
    case _ Nil{}: Some{obj(R.Record{field("role", str("assistant")) <> field("content", str(rendered)) <> Nil{}})}
    case _ _: Some{obj(R.Record{field("role", str("assistant")) <> field("content", Bool.pick(J(), String.is_empty(rendered), T.JsonNull{}, str(rendered))) <> field("tool_calls", T.JsonArray{found}) <> Nil{}})}

def assistant(+parts: List<&2, T.AssistantContent<V.Value>>) -> Maybe<&2, J()>:
  assistantWith(Unicode.sanitizeSurrogates(String.join(textParts(parts), "")), calls(parts))

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

def imageParts(parts: List<&2, T.TextImageContent>) -> List<&2, J()>:
  match parts:
    case Nil{}: Nil{}
    case T.TextImageImage{image} <> rest: userPart(T.TextImageImage{image}) <> imageParts(rest)
    case _ <> rest: imageParts(rest)

def imageInput(values: List<&2, T.ModelInput>) -> Bool:
  match values:
    case Nil{}: False{}
    case T.InputImage{} <> _: True{}
    case _ <> rest: imageInput(rest)

def imageAttachment(images: List<&2, J()>) -> Maybe<&2, J()>:
  match images:
    case Nil{}: None{}
    case _:
      +heading = obj(R.Record{field("type", str("text")) <> field("text", str("Attached image(s) from tool result:")) <> Nil{}})
      Some{obj(R.Record{field("role", str("user")) <> field("content", T.JsonArray{heading <> images}) <> Nil{}})}

def toolResult(-D: Data, value: T.ToolResultMessage<D>) -> J():
  match value:
    case T.ToolResultMessage{id, _, +content, _, _, _, _}:
      +text = String.join(resultTexts(content), "\n")
      +rendered = Bool.pick(String, String.is_empty(text), Bool.pick(String, hasImage(content), "(see attached image)", "(no tool output)"), text)
      obj(R.Record{field("role", str("tool")) <> field("content", str(Unicode.sanitizeSurrogates(rendered))) <> field("tool_call_id", str(id)) <> Nil{}})

def resultImages(-D: Data, value: T.ToolResultMessage<D>) -> List<&2, J()>:
  match value:
    case T.ToolResultMessage{_, _, content, _, _, _, _}: imageParts(content)

def prepend(value: Maybe<&2, J()>, rest: List<&2, J()>) -> List<&2, J()>:
  match value:
    case None{}: rest
    case Some{item}: item <> rest

def messages(-G: Data, -D: Data, values: List<&2, T.Message<V.Value, V.Value, G, D>>, initial: Bool, +developer: Bool, +images: Bool, pending: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: prepend(imageAttachment(pending), Nil{})
    case T.System{+system} <> rest:
      +content = Bool.pick(String, initial, Text.renderComplete(V.Value, system), Text.renderUpdate(V.Value, system))
      +role = Bool.pick(String, developer, "developer", "system")
      +tail = messages(G, D, rest, False{}, developer, images, Nil{})
      +updated = Bool.pick(List<&2, J()>, String.is_empty(content), tail, obj(R.Record{field("role", str(role)) <> field("content", str(Unicode.sanitizeSurrogates(content))) <> Nil{}}) <> tail)
      prepend(imageAttachment(pending), updated)
    case T.User{T.UserMessage{content, _}} <> rest:
      prepend(imageAttachment(pending), prepend(user(content), messages(G, D, rest, False{}, developer, images, Nil{})))
    case T.Assistant{T.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}} <> rest:
      prepend(imageAttachment(pending), prepend(assistant(content), messages(G, D, rest, False{}, developer, images, Nil{})))
    case T.ToolResult{+result} <> rest:
      +additional = Bool.pick(List<&2, J()>, images, resultImages(D, result), Nil{})
      toolResult(D, result) <> messages(G, D, rest, False{}, developer, images, List.append(&2, J(), pending, additional))

def tool(value: T.Tool<V.Value>) -> J():
  match value:
    case T.Tool{name, description, schema, _}:
      obj(R.Record{field("type", str("function")) <> field("function", obj(R.Record{field("name", str(name)) <> field("description", str(description)) <> field("parameters", Schema.toJson(schema)) <> Nil{}})) <> Nil{}})

def tools(values: List<&2, T.Tool<V.Value>>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case first <> rest: tool(first) <> tools(rest)

def toolList(value: Transcript.TranscriptTools<V.Value>) -> List<&2, J()>:
  match value:
    case Transcript.TranscriptTools{values, _}: tools(values)

def requestedTools(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>) -> List<&2, J()>:
  toolList(Transcript.resolveTranscriptTools(V.Value, V.Value, G, D, messages, False{}))

def choice(value: T.ToolChoice) -> J():
  match value:
    case T.AutoTool{}: str("auto")
    case T.NoTool{}: str("none")

def maxField(value: Maybe<&2, F64>, legacy: Bool, fields: Fields()) -> Fields():
  match value:
    case None{}: fields
    case Some{tokens}: put(fields, Bool.pick(String, legacy, "max_tokens", "max_completion_tokens"), T.JsonNumber{tokens})

def offEffortOf(value: Maybe<&2, T.Nullable<String>>, fallback: String) -> Maybe<&2, String>:
  match value:
    case Some{T.NullValue{}}: None{}
    case Some{T.PresentValue{value}}: Some{value}
    case None{}: Some{fallback}

def offEffort(mapping: Maybe<&2, T.ThinkingLevelMap>, fallback: String) -> Maybe<&2, String>:
  offEffortOf(Levels.mapped(mapping, T.Off{}), fallback)

def mappedOff(value: Maybe<&2, T.Nullable<String>>) -> Maybe<&2, String>:
  match value:
    case Some{T.PresentValue{selected}}: Some{selected}
    case _: None{}

def effortObject(value: String) -> J(): obj(R.Record{field("effort", str(value)) <> Nil{}})

def withReasoning(+fields: Fields(), wire: ThinkingWire, reasoning: Bool, enabled: Bool, supported: Bool, effort: Maybe<&2, String>, mapping: Maybe<&2, T.ThinkingLevelMap>) -> Fields():
  match wire reasoning enabled:
    case _ False{} _: fields
    case StandardThinking{} True{} True{}: Bool.pick(Fields(), supported, maybe(fields, "reasoning_effort", Maybe.map(&2, String, J(), str, effort)), fields)
    case StandardThinking{} True{} False{}: Bool.pick(Fields(), supported, maybe(fields, "reasoning_effort", Maybe.map(&2, String, J(), str, mappedOff(Levels.mapped(mapping, T.Off{})))), fields)
    case OpenRouterWire{} True{} True{}: maybe(fields, "reasoning", Maybe.map(&2, String, J(), effortObject, effort))
    case OpenRouterWire{} True{} False{}: maybe(fields, "reasoning", Maybe.map(&2, String, J(), effortObject, offEffort(mapping, "none")))
    case TogetherWire{} True{} True{}:
      +withFlag = put(fields, "reasoning", obj(R.Record{field("enabled", T.JsonBoolean{True{}}) <> Nil{}}))
      Bool.pick(Fields(), supported, maybe(withFlag, "reasoning_effort", Maybe.map(&2, String, J(), str, effort)), withFlag)
    case TogetherWire{} True{} False{}:
      put(fields, "reasoning", obj(R.Record{field("enabled", T.JsonBoolean{False{}}) <> Nil{}}))

def normalizedParams(-G: Data, -D: Data, id: String, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options, legacy: Bool, store: Bool, developer: Bool, usage: Bool, images: Bool, reasoning: Bool, supported: Bool, wire: ThinkingWire, mapping: Maybe<&2, T.ThinkingLevelMap>) -> J():
  match context options:
    case T.TranscriptContext{+normalizedMessages} Options{maxTokens, temperature, toolChoice, reasoningEffort, requested}:
      +declared = requestedTools(G, D, normalizedMessages)
      +base = {R.Record{field("model", str(id)) <> field("messages", T.JsonArray{messages(G, D, normalizedMessages, True{}, developer, images, Nil{})}) <> field("stream", T.JsonBoolean{True{}}) <> Nil{}} : Fields()}
      +withUsage = Bool.pick(Fields(), usage, put(base, "stream_options", obj(R.Record{field("include_usage", T.JsonBoolean{True{}}) <> Nil{}})), base)
      +withStore = Bool.pick(Fields(), store, put(withUsage, "store", T.JsonBoolean{False{}}), withUsage)
      +withMax = maxField(maxTokens, legacy, withStore)
      +withTemp = maybe(withMax, "temperature", number(temperature))
      +withTools = Bool.pick(Fields(), List.is_empty(&2, J(), declared), withTemp, put(withTemp, "tools", T.JsonArray{declared}))
      +withChoice = maybe(withTools, "tool_choice", Maybe.map(&2, T.ToolChoice, J(), choice, toolChoice))
      obj(withReasoning(withChoice, wire, reasoning, requested, supported, reasoningEffort, mapping))

def params(-G: Data, -D: Data, model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options, selected: Behavior) -> J():
  match model context options selected:
    case T.Model{id, _, _, _, _, reasoning, mapping, input, _, _, _, _, _, _, _, _} _ _ Behavior{legacy, store, developer, usage, supported, wire}:
      normalizedParams(G, D, id, Transcript.resolveTranscript(V.Value, V.Value, G, D, context, Some{False{}}), options, legacy, store, developer, usage, imageInput(input), reasoning, supported, wire, mapping)

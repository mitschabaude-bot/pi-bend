import Base
import ../types.bend as T
import ../utils/schema-json.bend as Schema
import ../utils/text.bend as Text
import ../utils/transcript.bend as Transcript
import ../utils/thinking-levels.bend as Levels
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../utils/sanitize-unicode.bend as Unicode
import ../utils/headers.bend as HeaderUtils

# Native Anthropic Messages wire format. This module owns provider decisions;
# the HTTP transport and SSE framing remain runtime facilities.
def J() -> Data: T.JsonValue
def Fields() -> Data: R.Record<J()>
def obj(fields: Fields()) -> J(): T.JsonObject{fields}
def str(value: String) -> J(): T.JsonString{value}
def bool(value: Bool) -> J(): T.JsonBoolean{value}
def field(name: String, value: J()) -> R.Property<J()>: R.Property{name, value}
def add(fields: Fields(), name: String, value: J()) -> Fields(): R.set(J(), fields, name, value)
def setMaybe(fields: Fields(), name: String, value: Maybe<&2, J()>) -> Fields():
  match value:
    case None{}: fields
    case Some{item}: add(fields, name, item)

type Thinking is Data:
  NoThinking{}
  DisabledThinking{}
  BudgetThinking{tokens: F64, display: String}
  AdaptiveThinking{effort: Maybe<&2, String>, display: String}

type ToolChoice is Data:
  Auto{}
  Any{}
  NoneChoice{}
  Named{name: String}

type Options is Data:
  Options{maxTokens: Maybe<&2, F64>, temperature: Maybe<&2, F64>, thinking: Thinking, toolChoice: Maybe<&2, ToolChoice>, cache: T.CacheRetention, oauth: Bool}

def cacheControl(cache: T.CacheRetention, longSupported: Bool) -> Maybe<&2, J()>:
  match cache:
    case T.CacheNone{}: None{}
    case T.CacheShort{}: Some{obj(R.Record{field("type", str("ephemeral")) <> Nil{}})}
    case T.CacheLong{}: Some{obj(setMaybe(R.Record{field("type", str("ephemeral")) <> Nil{}}, "ttl", Bool.pick(Maybe<&2, J()>, longSupported, Some{str("1h")}, None{})))}

def textBlock(value: String) -> J(): obj(R.Record{field("type", str("text")) <> field("text", str(Unicode.sanitizeSurrogates(value))) <> Nil{}})
def imageBlock(image: T.ImageContent) -> J():
  match image:
    case T.ImageContent{data, mime}: obj(R.Record{field("type", str("image")) <> field("source", obj(R.Record{field("type", str("base64")) <> field("media_type", str(mime)) <> field("data", str(data)) <> Nil{}})) <> Nil{}})

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

def toolContentKind(+items: List<&2, T.TextImageContent>, image: Bool) -> J():
  match image:
    case False{}: str(Unicode.sanitizeSurrogates(String.join(textParts(items), "\n")))
    case True{}: T.JsonArray{Bool.pick(List<&2, J()>, hasText(items), contentBlocks(items), textBlock("(see attached image)") <> contentBlocks(items))}

def toolContent(+items: List<&2, T.TextImageContent>) -> J(): toolContentKind(items, hasImage(items))

def userContent(content: T.UserContent) -> J():
  match content:
    case T.UserText{value}: str(Unicode.sanitizeSurrogates(value))
    case T.UserBlocks{items}: T.JsonArray{contentBlocks(items)}

def ordinaryThinking(+text: String, signature: Maybe<&2, String>, +allowEmptySignature: Bool) -> Maybe<&2, J()>:
  match signature:
    case Some{value}: Some{obj(R.Record{field("type", str("thinking")) <> field("thinking", str(Unicode.sanitizeSurrogates(text))) <> field("signature", str(value)) <> Nil{}})}
    case None{}: Bool.pick(Maybe<&2, J()>, allowEmptySignature, Some{obj(R.Record{field("type", str("thinking")) <> field("thinking", str(Unicode.sanitizeSurrogates(text))) <> field("signature", str("")) <> Nil{}})}, Some{textBlock(text)})

def redactedThinking(text: String, signature: Maybe<&2, String>, allowEmptySignature: Bool) -> Maybe<&2, J()>:
  match signature:
    case Some{value}: Some{obj(R.Record{field("type", str("redacted_thinking")) <> field("data", str(value)) <> Nil{}})}
    case None{}: ordinaryThinking(text, None{}, allowEmptySignature)

def thinkingBlock(text: String, signature: Maybe<&2, String>, redacted: Maybe<&2, Bool>, allowEmptySignature: Bool) -> Maybe<&2, J()>:
  match redacted:
    case Some{True{}}: redactedThinking(text, signature, allowEmptySignature)
    case _: ordinaryThinking(text, signature, allowEmptySignature)

def assistantBlock(block: T.AssistantContent<V.Value>, allowEmptySignature: Bool) -> Maybe<&2, J()>:
  match block:
    case T.AssistantText{T.TextContent{+text, _}}: Bool.pick(Maybe<&2, J()>, String.is_empty(String.trim(text)), None{}, Some{textBlock(text)})
    case T.AssistantThinking{T.ThinkingContent{text, signature, redacted}}: thinkingBlock(text, signature, redacted, allowEmptySignature)
    case T.AssistantToolCall{T.ToolCall{id, name, arguments, _, _}}: Some{obj(R.Record{field("type", str("tool_use")) <> field("id", str(id)) <> field("name", str(name)) <> field("input", Schema.toJson(arguments)) <> Nil{}})}

def optionalCons(converted: Maybe<&2, J()>, rest: List<&2, J()>) -> List<&2, J()>:
  match converted:
    case None{}: rest
    case Some{value}: value <> rest

def assistantBlocks(items: List<&2, T.AssistantContent<V.Value>>, +allowEmptySignature: Bool) -> List<&2, J()>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: optionalCons(assistantBlock(item, allowEmptySignature), assistantBlocks(rest, allowEmptySignature))

def message(role: String, content: J()) -> J(): obj(R.Record{field("role", str(role)) <> field("content", content) <> Nil{}})

def toolResult(-D: Data, result: T.ToolResultMessage<D>) -> J():
  match result:
    case T.ToolResultMessage{id, _, content, _, _, isError, _}:
      obj(R.Record{field("type", str("tool_result")) <> field("tool_use_id", str(id)) <> field("content", toolContent(content)) <> field("is_error", bool(isError)) <> Nil{}})

def appendResult(-D: Data, result: T.ToolResultMessage<D>, pending: List<&2, J()>) -> List<&2, J()>:
  List.append(&2, J(), pending, toolResult(D, result) <> Nil{})

def flushResults(reversed: List<&2, J()>, pending: List<&2, J()>) -> List<&2, J()>:
  match pending:
    case Nil{}: reversed
    case _: message("user", T.JsonArray{pending}) <> reversed

def updateMessage(-P: Data, system: T.SystemMessage<P>) -> Maybe<&2, J()>:
  +value = Text.renderUpdate(P, system)
  Bool.pick(Maybe<&2, J()>, String.is_empty(value), None{}, Some{message("system", T.JsonArray{textBlock(value) <> Nil{}})})

def prependOptional(value: Maybe<&2, J()>, values: List<&2, J()>) -> List<&2, J()>:
  match value:
    case None{}: values
    case Some{item}: item <> values

def messageList(-P: Data, -G: Data, -D: Data, messages: List<&2, T.Message<P, V.Value, G, D>>, +allowEmptySignature: Bool, +reversed: List<&2, J()>, +pending: List<&2, J()>) -> List<&2, J()>:
  match messages:
    case Nil{}: List.reverse(&2, J(), flushResults(reversed, pending))
    case T.ToolResult{result} <> rest: messageList(P, G, D, rest, allowEmptySignature, reversed, appendResult(D, result, pending))
    case T.System{system} <> rest: messageList(P, G, D, rest, allowEmptySignature, prependOptional(updateMessage(P, system), flushResults(reversed, pending)), Nil{})
    case T.User{T.UserMessage{content, _}} <> rest:
      messageList(P, G, D, rest, allowEmptySignature, message("user", userContent(content)) <> flushResults(reversed, pending), Nil{})
    case T.Assistant{T.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}} <> rest:
      +blocks = assistantBlocks(content, allowEmptySignature)
      +next = Bool.pick(List<&2, J()>, List.is_empty(&2, J(), blocks), flushResults(reversed, pending), message("assistant", T.JsonArray{blocks}) <> flushResults(reversed, pending))
      messageList(P, G, D, rest, allowEmptySignature, next, Nil{})

def dropInitialSystem(-P: Data, -G: Data, -D: Data, messages: List<&2, T.Message<P, V.Value, G, D>>) -> List<&2, T.Message<P, V.Value, G, D>>:
  match messages:
    case T.System{_} <> rest: rest
    case values: values

# An empty initial system text is omitted, as upstream's `if (initialSystemText)`.
def initialSystemValue(text: String, oauth: Bool, +cache: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match text oauth:
    case SNil{} False{}: None{}
    case SNil{} True{}: Some{T.JsonArray{obj(setMaybe(R.Record{field("type", str("text")) <> field("text", str("You are Claude Code, Anthropic's official CLI for Claude.")) <> Nil{}}, "cache_control", cache)) <> Nil{}}}
    case SCon{c, cs} False{}: Some{T.JsonArray{obj(setMaybe(R.Record{field("type", str("text")) <> field("text", str(SCon{c, cs})) <> Nil{}}, "cache_control", cache)) <> Nil{}}}
    case SCon{c, cs} True{}: Some{T.JsonArray{obj(setMaybe(R.Record{field("type", str("text")) <> field("text", str("You are Claude Code, Anthropic's official CLI for Claude.")) <> Nil{}}, "cache_control", cache)) <> obj(setMaybe(R.Record{field("type", str("text")) <> field("text", str(SCon{c, cs})) <> Nil{}}, "cache_control", cache)) <> Nil{}}}

def systemText(-P: Data, initial: Maybe<&2, T.SystemMessage<P>>) -> String:
  match initial:
    case None{}: ""
    case Some{system}: Text.renderComplete(P, system)

def initialSystem(-P: Data, -G: Data, -D: Data, messages: List<&2, T.Message<P, V.Value, G, D>>, oauth: Bool, cache: Maybe<&2, J()>) -> Maybe<&2, J()>:
  initialSystemValue(systemText(P, Transcript.getInitialSystemMessage(P, V.Value, G, D, messages)), oauth, cache)

def toolSchema(schema: V.Value) -> J(): Schema.toJson(schema)
def strictSampling(value: Maybe<&2, T.ToolConstrainedSampling>) -> Bool:
  match value:
    case Some{T.SamplingConfigured{T.JsonSchemaSampling{T.Require{}}}}: True{}
    case _: False{}
def toolValue(tool: T.Tool<V.Value>, cache: Maybe<&2, J()>, eager: Bool, strictSupport: Bool) -> J():
  match tool:
    case T.Tool{name, description, schema, sampling}:
      +strict = strictSupport && strictSampling(sampling)
      +base = {R.Record{field("name", str(name)) <> field("description", str(description)) <> field("input_schema", toolSchema(schema)) <> Nil{}} : Fields()}
      +withEager = Bool.pick(Fields(), eager, add(base, "eager_input_streaming", bool(True{})), base)
      +withStrict = Bool.pick(Fields(), strict, add(withEager, "strict", bool(True{})), withEager)
      obj(setMaybe(withStrict, "cache_control", cache))

def tools(values: List<&2, T.Tool<V.Value>>, cache: Maybe<&2, J()>, +eager: Bool, +strict: Bool) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case item <> Nil{}: toolValue(item, cache, eager, strict) <> Nil{}
    case item <> rest: toolValue(item, None{}, eager, strict) <> tools(rest, cache, eager, strict)

def choice(value: ToolChoice) -> J():
  match value:
    case Auto{}: obj(R.Record{field("type", str("auto")) <> Nil{}})
    case Any{}: obj(R.Record{field("type", str("any")) <> Nil{}})
    case NoneChoice{}: obj(R.Record{field("type", str("none")) <> Nil{}})
    case Named{name}: obj(R.Record{field("type", str("tool")) <> field("name", str(name)) <> Nil{}})

def thinking(value: Thinking) -> Maybe<&2, J()>:
  match value:
    case NoThinking{}: None{}
    case DisabledThinking{}: Some{obj(R.Record{field("type", str("disabled")) <> Nil{}})}
    case BudgetThinking{tokens, display}: Some{obj(R.Record{field("type", str("enabled")) <> field("budget_tokens", T.JsonNumber{tokens}) <> field("display", str(display)) <> Nil{}})}
    case AdaptiveThinking{effort, display}: Some{obj(R.Record{field("type", str("adaptive")) <> field("display", str(display)) <> Nil{}})}

def outputConfig(value: Thinking) -> Maybe<&2, J()>:
  match value:
    case AdaptiveThinking{Some{effort}, _}: Some{obj(R.Record{field("effort", str(effort)) <> Nil{}})}
    case _: None{}

def selectedManaged(requested: Thinking) -> Thinking:
  match requested:
    case NoThinking{}: AdaptiveThinking{Some{"high"}, "summarized"}
    case DisabledThinking{}: AdaptiveThinking{Some{"high"}, "summarized"}
    case value: value

# Thinking applies to reasoning models only; disabling it is omitted when the
# model maps the off level to null.
def reasoningThinking(reasoning: Bool, requested: Thinking, omitted: Bool) -> Thinking:
  match reasoning requested omitted:
    case False{} _ _: NoThinking{}
    case True{} DisabledThinking{} True{}: NoThinking{}
    case True{} value _: value

def nullMapped(value: Maybe<&2, T.Nullable<String>>) -> Bool:
  match value:
    case Some{T.NullValue{}}: True{}
    case _: False{}

def offOmitted(levels: Maybe<&2, T.ThinkingLevelMap>) -> Bool: nullMapped(Levels.mapped(levels, T.Off{}))

def selectedThinking(requested: Thinking, managed: Bool) -> Thinking:
  match managed:
    case True{}: selectedManaged(requested)
    case False{}: requested

def managedThinking(value: Thinking, managed: Bool) -> Maybe<&2, J()>:
  match managed:
    case False{}: thinking(value)
    case True{}: Some{obj(R.Record{field("type", str("adaptive")) <> field("display", str("summarized")) <> field("block_binding", obj(R.Record{field("prefix_mismatch_behavior", str("drop_block")) <> Nil{}})) <> Nil{}})}

def managedOutput(value: Thinking, managed: Bool) -> Maybe<&2, J()>:
  match managed:
    case False{}: outputConfig(value)
    case True{}: Some{obj(R.Record{field("effort", str("high")) <> Nil{}})}

def effort(value: Thinking) -> String:
  match value:
    case AdaptiveThinking{Some{level}, _}: level
    case _: "high"

def effortMarker(value: String) -> J():
  obj(R.Record{field("role", str("system")) <> field("content", T.JsonArray{Nil{}}) <> field("output_config", obj(R.Record{field("effort", str(value)) <> Nil{}})) <> Nil{}})

def appendMarker(messages: List<&2, J()>, value: Thinking, managed: Bool) -> List<&2, J()>:
  match managed:
    case False{}: messages
    case True{}: List.append(&2, J(), messages, effortMarker(effort(value)) <> Nil{})

def cacheBlock(value: J(), cache: J()) -> J():
  match value:
    case T.JsonObject{fields}: obj(add(fields, "cache_control", cache))
    case other: other

def cacheLastBlock(values: List<&2, J()>, cache: J()) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case head <> Nil{}: cacheBlock(head, cache) <> Nil{}
    case head <> rest: head <> cacheLastBlock(rest, cache)

def cacheMessageContent(value: J(), cache: J()) -> J():
  match value:
    case T.JsonString{text}: T.JsonArray{cacheBlock(textBlock(text), cache) <> Nil{}}
    case T.JsonArray{values}: T.JsonArray{cacheLastBlock(values, cache)}
    case other: other

def cacheMessageFields(+fields: Fields(), cache: J(), role: Maybe<&2, J()>) -> J():
  match role:
    case Some{T.JsonString{"user"}}: obj(add(fields, "content", cacheMessageContent(Maybe.default(&2, J(), R.get(J(), fields, "content"), T.JsonNull{}), cache)))
    case Some{T.JsonString{"system"}}: obj(add(fields, "content", cacheMessageContent(Maybe.default(&2, J(), R.get(J(), fields, "content"), T.JsonNull{}), cache)))
    case _: obj(fields)

def cacheMessage(value: J(), cache: J()) -> J():
  match value:
    case T.JsonObject{+fields}: cacheMessageFields(fields, cache, R.get(J(), fields, "role"))
    case other: other

def cacheLastWith(messages: List<&2, J()>, +value: J()) -> List<&2, J()>:
  match messages:
    case Nil{}: Nil{}
    case head <> Nil{}: cacheMessage(head, value) <> Nil{}
    case head <> rest: head <> cacheLastWith(rest, value)

def cacheLast(messages: List<&2, J()>, cache: Maybe<&2, J()>) -> List<&2, J()>:
  match cache:
    case None{}: messages
    case Some{value}: cacheLastWith(messages, value)

def betaList(oauth: Bool, eager: Bool, hasTools: Bool, managed: Bool, nativeChanges: Bool, fallbacks: Bool, budget: Bool) -> List<&2, J()>:
  +a = Bool.pick(List<&2, J()>, oauth, str("claude-code-20250219") <> str("oauth-2025-04-20") <> Nil{}, Nil{})
  +b = Bool.pick(List<&2, J()>, hasTools && Bool.not(eager), str("fine-grained-tool-streaming-2025-05-14") <> Nil{}, Nil{})
  +c = Bool.pick(List<&2, J()>, budget, str("interleaved-thinking-2025-05-14") <> Nil{}, Nil{})
  +d = Bool.pick(List<&2, J()>, fallbacks, str("server-side-fallback-2026-07-01") <> Nil{}, Nil{})
  +e = Bool.pick(List<&2, J()>, managed, str("mid-conversation-output-config-2026-07-01") <> str("thinking-binding-controls-2026-08-01") <> Nil{}, Nil{})
  +f = Bool.pick(List<&2, J()>, nativeChanges, str("mid-conversation-tool-changes-2026-07-01") <> Nil{}, Nil{})
  List.append(&2, J(), a, List.append(&2, J(), b, List.append(&2, J(), c, List.append(&2, J(), d, List.append(&2, J(), e, f)))))

def optionalBetas(values: List<&2, J()>) -> Maybe<&2, J()>:
  match values:
    case Nil{}: None{}
    case list: Some{T.JsonArray{list}}

def budget(value: Thinking) -> Bool:
  match value:
    case BudgetThinking{_, _}: True{}
    case _: False{}

def fallbackJson(values: List<&2, T.AnthropicAllowedFallbackModel>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case T.AnthropicAllowedFallbackModel{_, model, _} <> rest: obj(R.Record{field("model", str(model)) <> Nil{}}) <> fallbackJson(rest)

def optionalFallbacks(values: Maybe<&2, List<&2, T.AnthropicAllowedFallbackModel>>) -> Maybe<&2, J()>:
  match values:
    case None{}: None{}
    case Some{Nil{}}: None{}
    case Some{items}: Some{T.JsonArray{fallbackJson(items)}}

def hasFallbacks(values: Maybe<&2, List<&2, T.AnthropicAllowedFallbackModel>>) -> Bool:
  match values:
    case Some{_ <> _}: True{}
    case _: False{}

def placeholder() -> J():
  obj(R.Record{field("name", str("__pi_deferred_placeholder__")) <> field("description", str("Reserved placeholder. Never available. Never call this.")) <> field("input_schema", obj(R.Record{field("type", str("object")) <> field("properties", obj(R.new(J()))) <> field("required", T.JsonArray{Nil{}}) <> Nil{}})) <> field("defer_loading", bool(True{})) <> Nil{}})

def toolsWithPlaceholder(values: List<&2, J()>, native: Bool) -> List<&2, J()>:
  match native:
    case False{}: values
    case True{}: List.append(&2, J(), values, placeholder() <> Nil{})

def modelCompat(model: T.Model<T.JsonValue>) -> T.AnthropicMessagesCompat:
  match model:
    case T.Model{_, _, T.AnthropicMessagesApi{}, _, _, _, _, _, _, _, _, _, _, _, _, Some{value}}: value
    case _: T.AnthropicMessagesCompat{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def optionalBool(value: Maybe<&2, Bool>, default: Bool) -> Bool:
  match value:
    case None{}: default
    case Some{item}: item

def optionalNumber(value: Maybe<&2, F64>, default: F64) -> F64:
  match value:
    case None{}: default
    case Some{item}: item

def optionalChoice(value: Maybe<&2, ToolChoice>) -> Maybe<&2, J()>:
  match value:
    case None{}: None{}
    case Some{item}: Some{choice(item)}

def optionalJsonNumber(value: Maybe<&2, F64>) -> Maybe<&2, J()>:
  match value:
    case None{}: None{}
    case Some{item}: Some{T.JsonNumber{item}}

def temperatureAllowed(thought: Thinking, managed: Bool, supported: Bool) -> Bool:
  match thought:
    case NoThinking{}: supported && Bool.not(managed)
    case DisabledThinking{}: supported && Bool.not(managed)
    case _: False{}

def buildParamsWith(-G: Data, -D: Data, model: T.Model<T.JsonValue>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options, compat: T.AnthropicMessagesCompat) -> J():
  match model context options compat:
    case T.Model{id, _, _, _, _, reasoning, mapping, _, _, _, _, _, modelMax, _, _, _} T.TranscriptContext{+messages} Options{maxTokens, temperature, thought, toolChoice, retention, +oauth} T.AnthropicMessagesCompat{+eager, longCache, _, _, toolCache, supportsTemp, _, emptySignature, strict, managed, midSystem, midTools, +fallbacks}:
      +cache = cacheControl(retention, optionalBool(longCache, True{}))
      +managedEnabled = optionalBool(managed, False{})
      +selected = selectedThinking(reasoningThinking(reasoning, thought, offOmitted(mapping)), managedEnabled)
      +wireMessages = appendMarker(cacheLast(messageList(V.Value, G, D, dropInitialSystem(V.Value, G, D, messages), optionalBool(emptySignature, False{}), Nil{}, Nil{}), cache), selected, managedEnabled)
      +base = {R.Record{field("model", str(id)) <> field("messages", T.JsonArray{wireMessages}) <> field("max_tokens", T.JsonNumber{optionalNumber(maxTokens, modelMax)}) <> field("stream", bool(True{})) <> Nil{}} : Fields()}
      +withSystem = setMaybe(base, "system", initialSystem(V.Value, G, D, messages, oauth, cache))
      +withThinking = setMaybe(withSystem, "thinking", managedThinking(selected, managedEnabled))
      +withOutput = setMaybe(withThinking, "output_config", managedOutput(selected, managedEnabled))
      +withChoice = setMaybe(withOutput, "tool_choice", optionalChoice(toolChoice))
      +withTemp = setMaybe(withChoice, "temperature", Bool.pick(Maybe<&2, J()>, temperatureAllowed(selected, managedEnabled, optionalBool(supportsTemp, True{})), optionalJsonNumber(temperature), None{}))
      +currentTools = Transcript.getCurrentTools(V.Value, V.Value, G, D, messages)
      +hasTools = Bool.not(List.is_empty(&2, T.Tool<V.Value>, currentTools))
      +native = hasTools && optionalBool(midSystem, False{}) && optionalBool(midTools, False{})
      +withTools = Bool.pick(Fields(), hasTools, add(withTemp, "tools", T.JsonArray{toolsWithPlaceholder(tools(currentTools, Bool.pick(Maybe<&2, J()>, optionalBool(toolCache, True{}), cache, None{}), optionalBool(eager, True{}), optionalBool(strict, False{})), native)}), withTemp)
      +withBetas = setMaybe(withTools, "betas", optionalBetas(betaList(oauth, optionalBool(eager, True{}), hasTools, managedEnabled, native, hasFallbacks(fallbacks), budget(selected))))
      obj(setMaybe(withBetas, "fallbacks", optionalFallbacks(fallbacks)))

def buildParams(-G: Data, -D: Data, +model: T.Model<T.JsonValue>, context: T.TranscriptContext<V.Value, V.Value, G, D>, options: Options) -> J():
  buildParamsWith(G, D, model, context, options, modelCompat(model))

# upstream createClient's session-affinity header for API-key and
# header-owned auth; Copilot and OAuth clients send none.
def affinityHeader(format: Maybe<&2, T.AnthropicSessionAffinityFormat>, router: Bool) -> String:
  match format:
    case Some{T.AnthropicOpenRouterSession{}}: "x-session-id"
    case None{}: Bool.pick(String, router, "x-session-id", "x-session-affinity")

def affinityFor(send: Bool, header: String, sessionId: Maybe<&2, String>) -> R.Record<String>:
  match send sessionId:
    case True{} Some{SCon{c, cs}}: R.Record{R.Property{header, SCon{c, cs}} <> Nil{}}
    case _ _: R.new(String)

def affinityOf(+router: Bool, compat: T.AnthropicMessagesCompat, sessionId: Maybe<&2, String>) -> R.Record<String>:
  match compat:
    case T.AnthropicMessagesCompat{_, _, send, format, _, _, _, _, _, _, _, _, _}: affinityFor(optionalBool(send, router), affinityHeader(format, router), sessionId)

def routed(model: T.Model<T.JsonValue>) -> Bool:
  match model:
    case T.Model{_, _, _, provider, base, _, _, _, _, _, _, _, _, _, _, _}: String.eq(provider, "openrouter") || String.contains(base, "openrouter.ai")

def copilot(model: T.Model<T.JsonValue>) -> Bool:
  match model:
    case T.Model{_, _, _, provider, _, _, _, _, _, _, _, _, _, _, _, _}: String.eq(provider, "github-copilot")

def sessionAffinityHeaders(+model: T.Model<T.JsonValue>, sessionId: Maybe<&2, String>) -> R.Record<String>:
  affinityOf(routed(model), modelCompat(model), sessionId)

# The request headers the client applies after its own: session affinity,
# then the options' headers, which override it.
def headersFor(bearer: Bool, affinity: R.Record<String>, custom: Maybe<&2, T.ProviderHeaders()>) -> Maybe<&2, T.ProviderHeaders()>:
  match bearer:
    case True{}: custom
    case False{}: Some{HeaderUtils.overlay(HeaderUtils.fromRecord(affinity), custom)}

def clientHeaders(+model: T.Model<T.JsonValue>, sessionId: Maybe<&2, String>, oauth: Bool, custom: Maybe<&2, T.ProviderHeaders()>) -> Maybe<&2, T.ProviderHeaders()>:
  headersFor(oauth || copilot(model), sessionAffinityHeaders(model, sessionId), custom)

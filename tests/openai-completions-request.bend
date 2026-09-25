import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/api/openai-completions.bend as Request
import ../packages/ai/src/api/constrained-sampling.bend as Sampling
import ../packages/ai/src/utils/json.bend as Wire
import ../packages/ai/src/utils/model-json.bend as ModelJson
import ../packages/ai/src/providers/openai.models.bend as Catalog0
import ../packages/ai/src/providers/groq.models.bend as Catalog1
import ../packages/ai/src/providers/zai.models.bend as Catalog2
import ../packages/ai/src/providers/zai-coding-cn.models.bend as Catalog3
import ../packages/ai/src/providers/openrouter.models.bend as Catalog4
import ../packages/ai/src/providers/xiaomi.models.bend as Catalog5
import ../packages/ai/src/providers/xiaomi-token-plan-cn.models.bend as Catalog6
import ../packages/ai/src/providers/xiaomi-token-plan-ams.models.bend as Catalog7
import ../packages/ai/src/providers/xiaomi-token-plan-sgp.models.bend as Catalog8
import ../packages/ai/src/providers/qwen-token-plan.models.bend as Catalog9
import ../packages/ai/src/providers/qwen-token-plan-cn.models.bend as Catalog10
import ../packages/ai/src/providers/qwen-token-plan-individual.models.bend as Catalog11
import ../packages/ai/src/providers/opencode.models.bend as Catalog12
import ../packages/ai/src/providers/opencode-go.models.bend as Catalog13
import ../packages/ai/src/providers/moonshotai.models.bend as Catalog14
import ../packages/ai/src/providers/moonshotai-cn.models.bend as Catalog15
import ../packages/ai/src/providers/deepseek.models.bend as Catalog16
import ../packages/ai/src/providers/ant-ling.models.bend as Catalog17
import ../packages/ai/src/providers/fireworks.models.bend as Catalog18
import ../packages/ai/src/providers/baseten.models.bend as Catalog19
import ../packages/ai/src/providers/cloudflare-ai-gateway.models.bend as Catalog20
import ../packages/ai/src/utils/message-json.bend as MessageJson
import ../packages/ai/src/utils/schema-json.bend as Convert
import ../packages/ai/src/utils/transcript.bend as Transcript
import ../packages/ai/src/utils/event-stream.bend as Events
import ../packages/ai/test/openai-request-headers.bend as H
import ../packages/agent/src/types.bend as Agent
import ../packages/coding-agent/src/core/model-config.bend as Config
import ../packages/coding-agent/src/core/provider-composer.bend as Composer
import ../packages/coding-agent/src/core/openai-completions-provider.bend as Completions
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-message.bend as Message
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/test/utf8-runner.bend as Text

# The Chat Completions request path against upstream `stream`, `streamSimple`
# and `convertMessages` (tests/openai_completions_request_check.py). Each
# argument is one JSON case, encoded as comma-separated scalars:
#   {entry: "simple" | "stream" | "convert", provider, baseUrl, model,
#    systemPrompt?, messages, tools?, options?}
# "simple" and "stream" run the native provider with a capturing fetch and
# report the request's headers and body, or the error the stream ends with;
# "convert" reports convertMessages under the model's resolved compat.

def Details() -> Data: Tools.ToolDetails
def Error() -> Data: Tools.ToolError
def Context() -> Data: Ai.TranscriptContext<V.Value, V.Value, Unit, Details()>
def Captured() -> Data: Maybe<&2, V.Value>
def Output() -> Type: Result<&2, &1, Error(), Agent.StreamLease<Unit, Error()>>

def urls() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>: H.optionField(value, name)
def text(value: Maybe<&2, V.Value>) -> Maybe<&2, String>: H.optionalText(value)
def number(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>: H.milliseconds(value)
def object(entries: List<&2, R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{entries}}

def stringProperties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<String>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, V.Text{value}} <> rest: R.Property{name, value} <> stringProperties(rest)
    case _ <> rest: stringProperties(rest)

def strings(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<String>>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{R.Record{stringProperties(values)}}
    case _: None{}

def jsonProperties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<Ai.JsonValue>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, Convert.toJson(value)} <> jsonProperties(rest)

def jsonRecord(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<Ai.JsonValue>>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{R.Record{jsonProperties(values)}}
    case _: None{}

def level(value: Maybe<&2, String>) -> Maybe<&2, Ai.ThinkingLevel>:
  match value:
    case Some{"minimal"}: Some{Ai.Minimal{}}
    case Some{"low"}: Some{Ai.Low{}}
    case Some{"medium"}: Some{Ai.Medium{}}
    case Some{"high"}: Some{Ai.High{}}
    case Some{"xhigh"}: Some{Ai.XHigh{}}
    case Some{"max"}: Some{Ai.Max{}}
    case _: None{}

def retention(value: Maybe<&2, String>) -> Maybe<&2, Ai.CacheRetention>:
  match value:
    case Some{"none"}: Some{Ai.CacheNone{}}
    case Some{"short"}: Some{Ai.CacheShort{}}
    case Some{"long"}: Some{Ai.CacheLong{}}
    case _: None{}

def choice(value: Maybe<&2, String>) -> Maybe<&2, Ai.ToolChoice>:
  match value:
    case Some{"auto"}: Some{Ai.AutoTool{}}
    case Some{"none"}: Some{Ai.NoTool{}}
    case _: None{}

def budgets(value: Maybe<&2, V.Value>) -> Maybe<&2, Ai.ThinkingBudgets>:
  match value:
    case Some{+levels}: Some{Ai.ThinkingBudgets{number(field(levels, "minimal")), number(field(levels, "low")), number(field(levels, "medium")), number(field(levels, "high"))}}
    case None{}: None{}

# Catalog
# -------

def catalogModels(+provider: String) -> List<&2, Ai.Model<Ai.JsonValue>>:
  match provider:
    case "openai": Catalog0.OPENAI_MODELS()
    case "groq": Catalog1.GROQ_MODELS()
    case "zai": Catalog2.ZAI_MODELS()
    case "zai-coding-cn": Catalog3.ZAI_CODING_CN_MODELS()
    case "openrouter": Catalog4.OPENROUTER_MODELS()
    case "xiaomi": Catalog5.XIAOMI_MODELS()
    case "xiaomi-token-plan-cn": Catalog6.XIAOMI_TOKEN_PLAN_CN_MODELS()
    case "xiaomi-token-plan-ams": Catalog7.XIAOMI_TOKEN_PLAN_AMS_MODELS()
    case "xiaomi-token-plan-sgp": Catalog8.XIAOMI_TOKEN_PLAN_SGP_MODELS()
    case "qwen-token-plan": Catalog9.QWEN_TOKEN_PLAN_MODELS()
    case "qwen-token-plan-cn": Catalog10.QWEN_TOKEN_PLAN_CN_MODELS()
    case "qwen-token-plan-individual": Catalog11.QWEN_TOKEN_PLAN_INDIVIDUAL_MODELS()
    case "opencode": Catalog12.OPENCODE_MODELS()
    case "opencode-go": Catalog13.OPENCODE_GO_MODELS()
    case "moonshotai": Catalog14.MOONSHOTAI_MODELS()
    case "moonshotai-cn": Catalog15.MOONSHOTAI_CN_MODELS()
    case "deepseek": Catalog16.DEEPSEEK_MODELS()
    case "ant-ling": Catalog17.ANT_LING_MODELS()
    case "fireworks": Catalog18.FIREWORKS_MODELS()
    case "baseten": Catalog19.BASETEN_MODELS()
    case "cloudflare-ai-gateway": Catalog20.CLOUDFLARE_AI_GATEWAY_MODELS()
    case _: Nil{}

def findModel(models: List<&2, Ai.Model<Ai.JsonValue>>, +id: String) -> Maybe<&2, Ai.Model<Ai.JsonValue>>:
  match models:
    case Nil{}: None{}
    case +first <> rest: Bool.pick(Maybe<&2, Ai.Model<Ai.JsonValue>>, String.eq(Ai.modelId(first), id), Some{first}, findModel(rest, id))

def catalogEntry(value: Maybe<&2, V.Value>) -> Maybe<&2, Ai.Model<Ai.JsonValue>>:
  match value:
    case Some{V.ArrayValue{V.Text{provider} <> V.Text{id} <> Nil{}}}: findModel(catalogModels(provider), id)
    case _: None{}

# Model
# -----

def withHeaders(model: Ai.Model<Ai.JsonValue>, headers: Maybe<&2, R.Record<String>>) -> Ai.Model<Ai.JsonValue>:
  match model:
    case Ai.Model{id, name, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, _, compat}:
      Ai.Model{id, name, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, compat}

def configured(+value: V.Value) -> Ai.Model<Ai.JsonValue>:
  +definition = Maybe.default(&2, V.Value, field(value, "model"), V.Null{})
  withHeaders(Composer.builtModel(Maybe.default(&2, String, text(field(value, "provider")), ""), Config.modelOf(definition), None{}, Ai.OpenAICompletionsApi{}, Maybe.default(&2, String, text(field(value, "baseUrl")), "")), strings(field(definition, "headers")))

# A catalog entry, or a models.json-style definition.
def model(+value: V.Value) -> Ai.Model<Ai.JsonValue>:
  Maybe.default(&2, Ai.Model<Ai.JsonValue>, catalogEntry(field(value, "catalog")), configured(value))

# Context
# -------

def noDetails(value: V.Value) -> MessageJson.Decoded(Details()):
  Fail{Decode.WrongType{Nil{}, "no tool details"}}

def noDiagnostics(value: V.Value) -> MessageJson.Decoded(Unit):
  Fail{Decode.WrongType{Nil{}, "no diagnostic details"}}

def decodedMessage(value: MessageJson.Decoded(Ai.Message<V.Value, V.Value, Unit, Details()>), rest: List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>) -> List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>:
  match value:
    case Done{message}: message <> rest
    case Fail{_}: rest

def messages(values: List<&2, V.Value>) -> List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>:
  match values:
    case Nil{}: Nil{}
    case +first <> rest: decodedMessage(MessageJson.decodeMessage(~Unit, ~Details(), ~noDiagnostics, ~noDetails, first), messages(rest))

def decodedTool(value: MessageJson.Decoded(Ai.Tool<V.Value>), rest: List<&2, Ai.Tool<V.Value>>) -> List<&2, Ai.Tool<V.Value>>:
  match value:
    case Done{tool}: tool <> rest
    case Fail{_}: rest

def tools(values: List<&2, V.Value>) -> List<&2, Ai.Tool<V.Value>>:
  match values:
    case Nil{}: Nil{}
    case first <> rest: decodedTool(MessageJson.decodeTool(first), tools(rest))

def items(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{values}}: values
    case _: Nil{}

def toolList(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, Ai.Tool<V.Value>>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{tools(values)}
    case _: None{}

def context(+value: V.Value) -> Context():
  Transcript.normalizeContext(V.Value, V.Value, Unit, Details(), Ai.Context{text(field(value, "systemPrompt")), messages(items(field(value, "messages"))), toolList(field(value, "tools"))})

# Options
# -------

def settings(+value: V.Value) -> V.Value: Maybe.default(&2, V.Value, field(value, "options"), object(Nil{}))

def simpleOptions(+value: V.Value, fetch: Fetch.Fetch(Unit)) -> Completions.Options():
  Ai.SimpleStreamOptions{None{}, None{}, text(field(value, "apiKey")), Some{fetch}, strings(field(value, "env")), None{}, None{}, H.headerLayer(field(value, "headers")), number(field(value, "timeoutMs")), number(field(value, "maxRetries")), number(field(value, "maxRetryDelayMs")), number(field(value, "temperature")), jsonRecord(field(value, "samplingParams")), number(field(value, "maxTokens")), None{}, retention(text(field(value, "cacheRetention"))), text(field(value, "sessionId")), None{}, None{}, choice(text(field(value, "toolChoice"))), level(text(field(value, "reasoning"))), None{}, budgets(field(value, "thinkingBudgets"))}

def streamOptions(+value: V.Value, fetch: Maybe<&2, Fetch.Fetch(Unit)>) -> Completions.Completions():
  +base = {Ai.StreamOptions{None{}, None{}, text(field(value, "apiKey")), fetch, strings(field(value, "env")), None{}, None{}, H.headerLayer(field(value, "headers")), number(field(value, "timeoutMs")), number(field(value, "maxRetries")), number(field(value, "maxRetryDelayMs")), number(field(value, "temperature")), jsonRecord(field(value, "samplingParams")), number(field(value, "maxTokens")), None{}, retention(text(field(value, "cacheRetention"))), text(field(value, "sessionId")), None{}, None{}} : Completions.Base()}
  Request.OpenAICompletionsOptions{base, Maybe.map(&2, V.Value, Ai.JsonValue, Convert.toJson, field(value, "toolChoice")), level(text(field(value, "reasoningEffort"))), budgets(field(value, "thinkingBudgets"))}

# Capture
# -------

def headerFields(entries: List<&2, Message.Header>) -> List<&2, R.Property<V.Value>>:
  match entries:
    case Nil{}: Nil{}
    case Message.Header{name, value} <> rest: R.Property{String.to_lower(name), V.Text{value}} <> headerFields(rest)

def bodyText(body: Message.Input) -> V.Value:
  match body:
    case Message.Text{content}: V.Text{content}
    case _: V.Null{}

def capture(slot: Ref.Ref<Captured()>, input: Fetch.Input<Unit>) -> IO(Fetch.Result_(Unit)):
  match input:
    case Fetch.Input{url, _, headers, body, _}:
      do IO<Fetch.Result_(Unit)>:
        Ref.write(Captured(), slot, Some{object([R.Property{"url", V.Text{URL.serialize(url, False{})}}, R.Property{"headers", object(headerFields(Message.entries(headers)))}, R.Property{"body", bodyText(body)}])})
        return Fail{Fetch.Rejected{Message.TLSRequired{}}}

def failureText(message: Ai.AssistantMessage<V.Value, Unit>) -> V.Value:
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, Some{content}, _, _, _}: V.Text{content}
    case _: V.Null{}

def settled(output: Output()) -> IO(V.Value):
  match output:
    case Fail{_}: IO.pure(V.Value, V.Text{"provider failed to open"})
    case Done{Agent.StreamLease{events, release}}:
      do IO<V.Value>:
        message : Ai.AssistantMessage<V.Value, Unit> <- Events.resultValue(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, events)
        result : Result<&2, &2, Error(), Unit> <- release
        return failureText(message)

def reported(error: V.Value, captured: Captured()) -> V.Value:
  match captured:
    case Some{request}: request
    case None{}: object([R.Property{"error", error}])

def opened(+entry: String, +fetch: Fetch.Fetch(Unit), +value: V.Value) -> IO(Output()):
  match entry:
    case "stream": Completions.openStream(fetch, urls(), model(value), context(value), streamOptions(settings(value), Some{fetch}))
    case _: Completions.open(fetch, urls(), model(value), context(value), Some{simpleOptions(settings(value), fetch)})

def requested(+entry: String, +value: V.Value) -> IO(V.Value):
  do IO<V.Value>:
    +slot : Ref.Ref<Captured()> <- Ref.new(Captured(), None{})
    +fetch : Fetch.Fetch(Unit) <- C.create(~Ref.Ref<Captured()>, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~capture, slot)
    output : Output() <- opened(entry, fetch, value)
    error : V.Value <- settled(output)
    C.dispose(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch)
    captured : Captured() <- Ref.dispose(Captured(), slot)
    return reported(error, captured)

def converted(result: Request.Converted()) -> V.Value:
  match result:
    case Done{chat}: object([R.Property{"messages", V.Text{Maybe.default(&2, String, Wire.stringify(Request.messagesJson(chat)), "")}}])
    case Fail{_}: object([R.Property{"error", V.Text{"conversion failed"}}])

def conversion(+value: V.Value) -> IO(V.Value):
  +selected = model(value)
  do IO<V.Value>:
    result : Request.Converted() <- Request.convertMessages(~Unit, ~Details(), selected, context(value), Request.getCompat(selected), R.new(String))
    return converted(result)

def built(result: Request.ParamsResult()) -> V.Value:
  match result:
    case Done{payload}: object([R.Property{"body", V.Text{Maybe.default(&2, String, Wire.stringify(payload), "")}}])
    case Fail{error}: object([R.Property{"error", V.Text{Sampling.errorMessage(error)}}])

def withGrammar(+selected: Ai.Model<Ai.JsonValue>, +normalized: Context(), options: Completions.Completions(), +compat: Request.Compat(), retention: Ai.CacheRetention, properties: Result<&2, &2, Sampling.Error, R.Record<String>>) -> IO(V.Value):
  match properties:
    case Fail{error}: IO.pure(V.Value, object([R.Property{"error", V.Text{Sampling.errorMessage(error)}}]))
    case Done{selectedProperties}:
      do IO<V.Value>:
        result : Request.ParamsResult() <- Request.buildParams(~Unit, ~Details(), ~Abort.AbortSignal<Unit>, ~Unit, ~Fetch.Fetch(Unit), ~Error(), selected, normalized, options, compat, retention, selectedProperties)
        return built(result)

def contextMessages(context: Context()) -> List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>:
  match context:
    case Ai.TranscriptContext{transcript}: transcript

# The request builder without the provider's refusal of grammar tools.
def parameters(+value: V.Value) -> IO(V.Value):
  +selected = model(value)
  +compat = Request.getCompat(selected)
  +normalized = Transcript.resolveTranscript(V.Value, V.Value, Unit, Details(), context(value), Some{Request.supportsMidConvoSystemMessages(compat)})
  +options = streamOptions(settings(value), None{})
  +shared = Completions.base(options)
  do IO<V.Value>:
    retention : Ai.CacheRetention <- Request.resolveCacheRetention(Completions.retentionOf(shared), Completions.envOf(shared))
    withGrammar(selected, normalized, options, compat, retention, Sampling.createGrammarToolInputProperties(Some{Transcript.getDeclaredTools(V.Value, V.Value, Unit, Details(), contextMessages(normalized))}, Request.supportsOpenAIGrammarTools(compat)))

def metadata(value: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> V.Value:
  match value:
    case Some{selected}: object([R.Property{"model", ModelJson.model(selected)}])
    case None{}: object([R.Property{"error", V.Text{"unknown model"}}])

def evaluated(+entry: String, +value: V.Value) -> IO(V.Value):
  match entry:
    case "metadata": IO.pure(V.Value, metadata(catalogEntry(field(value, "catalog"))))
    case "convert": conversion(value)
    case "params": parameters(value)
    case _: requested(entry, value)

def shown(value: V.Value) -> String:
  Maybe.default(&2, String, Wire.stringify(Convert.toJson(value)), "null")

def run(result: Result<&2, &2, Decode.ParseError, V.Value>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("R " ++ Text.showText("{\"error\":\"invalid case\"}"))
    case Done{+value}:
      do IO<Unit>:
        outcome : V.Value <- evaluated(Maybe.default(&2, String, text(field(value, "entry")), "simple"), value)
        IO.print("R " ++ Text.showText(shown(outcome)))

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case encoded <> rest:
      do IO<Unit>:
        run(Decode.parse(Text.fromScalars(Text.parseNumbers(encoded))))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)

import Base
import ../src/providers/anthropic.models.bend as Catalog
import ../src/providers/openrouter.models.bend as OpenRouter
import ../src/types.bend as T
import ./anthropic-harness.bend as H
import ./anthropic-sse-bodies.bend as Bodies
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/anthropic-mid-conversation-effort.test.ts.
def mapping(level: T.ModelThinkingLevel, value: Maybe<&2, T.Nullable<String>>) -> T.ThinkingLevelMapping: T.ThinkingLevelMapping{level, value}

def levels() -> T.ThinkingLevelMap:
  T.ThinkingLevelMap{mapping(T.Off{}, Some{T.NullValue{}}) <> mapping(T.Thinking{T.Minimal{}}, Some{T.PresentValue{"low"}}) <> mapping(T.Thinking{T.Low{}}, Some{T.PresentValue{"low"}}) <> mapping(T.Thinking{T.Medium{}}, Some{T.PresentValue{"medium"}}) <> mapping(T.Thinking{T.High{}}, Some{T.PresentValue{"high"}}) <> mapping(T.Thinking{T.Max{}}, Some{T.PresentValue{"max"}}) <> Nil{}}

def compat(managed: Bool) -> T.AnthropicMessagesCompat:
  T.AnthropicMessagesCompat{None{}, None{}, None{}, None{}, None{}, None{}, Some{True{}}, None{}, None{}, Bool.pick(Maybe<&2, Bool>, managed, Some{True{}}, None{}), None{}, None{}, None{}}

def managedModel(managed: Bool) -> T.Model<T.JsonValue>:
  H.custom("claude-fable-5-1", "Claude Fable 5.1", "anthropic", "http://127.0.0.1:9", 32000, 200000, Some{levels()}, Some{compat(managed)})

def assistant(provider: String, level: Maybe<&2, String>) -> T.Message<V.Value, V.Value, H.Diagnostics(), Unit>:
  H.assistant(H.thinkingBlock("reasoning", "signature") <> H.textBlock("answer") <> Nil{}, provider, "claude-fable-5-1", level)

def capture(+model: T.Model<T.JsonValue>, messages: List<&2, T.Message<V.Value, V.Value, H.Diagnostics(), Unit>>, effort: Maybe<&2, String>) -> IO(H.Outcome):
  H.run(model, H.context(messages), H.direct(H.streamOptions(Some{"test-key"}, Some{T.CacheNone{}}, None{}), Some{True{}}, effort), H.Capture{})

def marker(effort: String) -> String: "{\"role\":\"system\",\"content\":[],\"output_config\":{\"effort\":\"" ++ effort ++ "\"}}"

def systems(values: List<&2, T.JsonValue>) -> List<&2, T.JsonValue>:
  match values:
    case Nil{}: Nil{}
    case +value <> rest:
      +tail = systems(rest)
      Bool.pick(List<&2, T.JsonValue>, H.isRole(value, "system"), value <> tail, tail)

def effortMessages(payload: Maybe<&2, T.JsonValue>) -> Maybe<&2, T.JsonValue>: Some{T.JsonArray{systems(H.elements(H.fieldOf(payload, "messages")))}}

def prefix(values: List<&2, T.JsonValue>, count: Nat) -> List<&2, T.JsonValue>: List.take(&2, T.JsonValue, values, count)

def lastOf(values: List<&2, T.JsonValue>) -> Maybe<&2, T.JsonValue>: List.last(&2, T.JsonValue, values)

def historical() -> IO(Unit):
  +name = {"reconstructs an exact historical marker prefix and appends the current marker" : String}
  do IO<Unit>:
    +first : H.Outcome <- capture(managedModel(True{}), H.user("one", 1) <> Nil{}, Some{"low"})
    +second : H.Outcome <- capture(managedModel(True{}), H.user("one", 1) <> assistant("anthropic", Some{"low"}) <> H.user("two", 2) <> Nil{}, Some{"high"})
    +firstMessages : List<&2, T.JsonValue> <- IO.pure(List<&2, T.JsonValue>, H.elements(H.fieldOf(H.payloadOf(first), "messages")))
    +secondMessages : List<&2, T.JsonValue> <- IO.pure(List<&2, T.JsonValue>, H.elements(H.fieldOf(H.payloadOf(second), "messages")))
    H.equalJson(Some{T.JsonArray{firstMessages}}, "[{\"role\":\"user\",\"content\":\"one\"}," ++ marker("low") ++ "]", name ++ ": first messages")
    H.equalJson(Some{T.JsonArray{prefix(secondMessages, List.length(&2, T.JsonValue, firstMessages))}}, "[{\"role\":\"user\",\"content\":\"one\"}," ++ marker("low") ++ "]", name ++ ": second prefix")
    H.equalJson(lastOf(secondMessages), marker("high"), name ++ ": last marker")
    H.equalJson(H.fieldOf(H.payloadOf(first), "output_config"), "{\"effort\":\"high\"}", name ++ ": first output_config")
    H.equalJson(H.fieldOf(H.payloadOf(second), "output_config"), "{\"effort\":\"high\"}", name ++ ": second output_config")
    H.equalJson(H.fieldOf(H.payloadOf(second), "thinking"), "{\"type\":\"adaptive\",\"display\":\"summarized\",\"block_binding\":{\"prefix_mismatch_behavior\":\"drop_block\"}}", name ++ ": thinking")
    H.equalText(H.providerLevel(H.messageOf(first)), Some{"low"}, name ++ ": providerThinkingLevel")
    H.pass(name)

def native(+effort: String) -> IO(Unit):
  +name = "preserves native effort " ++ effort
  do IO<Unit>:
    +outcome : H.Outcome <- capture(managedModel(True{}), H.user("one", 1) <> Nil{}, Some{effort})
    H.equalJson(effortMessages(H.payloadOf(outcome)), "[" ++ marker(effort) ++ "]", name)
    H.equalText(H.providerLevel(H.messageOf(outcome)), Some{effort}, name ++ ": providerThinkingLevel")
    H.pass(name)

def defaulted() -> IO(Unit):
  +name = {"defaults omitted effort to high and still enables drop_block" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- capture(managedModel(True{}), H.user("one", 1) <> Nil{}, None{})
    H.equalJson(lastOf(H.elements(H.fieldOf(H.payloadOf(outcome), "messages"))), marker("high"), name)
    H.equalJson(H.pathOf(["thinking", "block_binding", "prefix_mismatch_behavior"], H.payloadOf(outcome)), "\"drop_block\"", name)
    H.equalText(H.providerLevel(H.messageOf(outcome)), Some{"high"}, name ++ ": providerThinkingLevel")
    H.pass(name)

def legacy() -> IO(Unit):
  +name = {"does not invent markers for legacy or other-provider assistants" : String}
  do IO<Unit>:
    outcome : H.Outcome <- capture(managedModel(True{}), H.user("one", 1) <> assistant("anthropic", None{}) <> H.user("two", 2) <> assistant("other-provider", Some{"low"}) <> H.user("three", 3) <> Nil{}, Some{"medium"})
    H.equalJson(effortMessages(H.payloadOf(outcome)), "[" ++ marker("medium") ++ "]", name)
    H.pass(name)

def unsupported() -> IO(Unit):
  +name = {"leaves unsupported models on top-level effort" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- capture(managedModel(False{}), H.user("one", 1) <> Nil{}, Some{"low"})
    H.equalJson(H.fieldOf(H.payloadOf(outcome), "messages"), "[{\"role\":\"user\",\"content\":\"one\"}]", name)
    H.equalJson(H.fieldOf(H.payloadOf(outcome), "output_config"), "{\"effort\":\"low\"}", name)
    H.equalJson(H.fieldOf(H.payloadOf(outcome), "thinking"), "{\"type\":\"adaptive\",\"display\":\"summarized\"}", name)
    H.equalText(H.providerLevel(H.messageOf(outcome)), None{}, name ++ ": providerThinkingLevel")
    H.pass(name)

# upstream reads the header from a fetch returning the SSE body. Natively the
# injected client streams the body (the result) and a recording fetch
# observes the wire header of the same request.
def headers() -> IO(Unit):
  +name = {"sends the effort and binding beta headers" : String}
  +options = H.direct(H.streamOptions(Some{"test-key"}, Some{T.CacheNone{}}, None{}), None{}, None{})
  do IO<Unit>:
    streamed : H.Outcome <- H.run(managedModel(True{}), H.context(H.user("one", 1) <> Nil{}), options, H.Respond{Bodies.effortFetch() <> Nil{}})
    H.equalStop(H.messageOf(streamed), "stop")
    +sent : H.Outcome <- H.run(managedModel(True{}), H.context(H.user("one", 1) <> Nil{}), options, H.Send{})
    +beta : Maybe<&2, String> <- IO.pure(Maybe<&2, String>, H.header(H.requestOf(sent), "anthropic-beta"))
    H.check(H.contains(beta, "mid-conversation-output-config-2026-07-01"), name ++ ": output config beta " ++ H.showMaybe(beta))
    H.check(H.contains(beta, "thinking-binding-controls-2026-08-01"), name ++ ": binding beta")
    H.pass(name)

def compatOf(model: T.Model<T.JsonValue>) -> T.AnthropicMessagesCompat:
  match model:
    case T.Model{_, _, T.AnthropicMessagesApi{}, _, _, _, _, _, _, _, _, _, _, _, _, Some{value}}: value
    case _: H.noCompat()

def managedFlag(compat: T.AnthropicMessagesCompat) -> Maybe<&2, Bool>:
  match compat:
    case T.AnthropicMessagesCompat{_, _, _, _, _, _, _, _, _, value, _, _, _}: value

def fallbacksOf(compat: T.AnthropicMessagesCompat) -> Bool:
  match compat:
    case T.AnthropicMessagesCompat{_, _, _, _, _, _, _, _, _, _, _, _, None{}}: True{}
    case _: False{}

def isTrue(value: Maybe<&2, Bool>) -> Bool:
  match value:
    case Some{True{}}: True{}
    case _: False{}

def offIn(values: List<&2, T.ThinkingLevelMapping>) -> Bool:
  match values:
    case Nil{}: False{}
    case T.ThinkingLevelMapping{T.Off{}, Some{T.NullValue{}}} <> _: True{}
    case _ <> rest: offIn(rest)

def offNull(model: T.Model<T.JsonValue>) -> Bool:
  match model:
    case T.Model{_, _, _, _, _, _, Some{T.ThinkingLevelMap{mappings}}, _, _, _, _, _, _, _, _, _}: offIn(mappings)
    case _: False{}

def anthropicApi(model: T.Model<T.JsonValue>) -> Bool:
  match model:
    case T.Model{_, _, T.AnthropicMessagesApi{}, _, _, _, _, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def baseOf(model: T.Model<T.JsonValue>) -> String:
  match model:
    case T.Model{_, _, _, _, base, _, _, _, _, _, _, _, _, _, _, _}: base

def gates() -> IO(Unit):
  +name = {"generates exact model and transport gates" : String}
  do IO<Unit>:
    H.check(isTrue(managedFlag(compatOf(Catalog.model_claude_fable_5_1()))), name ++ ": direct supportsMidConvoEffort")
    H.check(offNull(Catalog.model_claude_fable_5_1()), name ++ ": direct off level is null")
    H.check(anthropicApi(OpenRouter.model_anthropic_claude_fable_5_1()), name ++ ": OpenRouter api")
    H.equalText(Some{baseOf(OpenRouter.model_anthropic_claude_fable_5_1())}, Some{"https://openrouter.ai/api"}, name ++ ": OpenRouter baseUrl")
    H.check(isTrue(managedFlag(compatOf(OpenRouter.model_anthropic_claude_fable_5_1()))), name ++ ": OpenRouter supportsMidConvoEffort")
    H.check(Maybe.is_none(&2, Bool, managedFlag(compatOf(Catalog.model_claude_opus_4_8()))), name ++ ": Opus 4.8 unmanaged")
    # OpenRouter rejects configuration_update on Opus 5 but accepts it on Fable 5.1.
    H.check(Maybe.is_none(&2, Bool, managedFlag(compatOf(OpenRouter.model_anthropic_claude_opus_5()))), name ++ ": OpenRouter Opus 5 unmanaged")
    H.check(fallbacksOf(compatOf(Catalog.model_claude_opus_5())), name ++ ": Opus 5 has no fallbacks")
    H.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    historical()
    native("low")
    native("medium")
    native("high")
    native("xhigh")
    native("max")
    defaulted()
    legacy()
    unsupported()
    headers()
    gates()

import Base
import ../src/providers/anthropic.models.bend as Catalog
import ../src/providers/kimi-coding.models.bend as Kimi
import ../src/types.bend as T
import ./anthropic-harness.bend as H

# pi-mono f07218c4d packages/ai/test/anthropic-force-adaptive-thinking.test.ts.
def capture(model: T.Model<T.JsonValue>, reasoning: Maybe<&2, T.ThinkingLevel>) -> IO(Maybe<&2, T.JsonValue>):
  +selected = H.withBase(model, "http://127.0.0.1:9")
  +context = H.hello()
  do IO<Maybe<&2, T.JsonValue>>:
    outcome : H.Outcome <- H.runSimple(selected, context, H.simple(Some{"fake-key"}, None{}, reasoning), H.Capture{})
    return H.payloadOf(outcome)

# The id intentionally matches no built-in adaptive substring, like corporate
# proxy schemes such as `anthropic--claude-opus-latest`.
def customModel(compat: Maybe<&2, T.AnthropicMessagesCompat>) -> T.Model<T.JsonValue>:
  H.custom("vendor--claude-opus-latest", "Vendor Proxy Opus Latest", "vendor-proxy", "http://127.0.0.1:9", 32000, 200000, None{}, compat)

def forced(value: Bool) -> T.AnthropicMessagesCompat:
  T.AnthropicMessagesCompat{None{}, None{}, None{}, None{}, None{}, None{}, Some{value}, None{}, None{}, None{}, None{}, None{}, None{}}

def legacy(model: T.Model<T.JsonValue>, +name: String) -> IO(Unit):
  do IO<Unit>:
    +payload : Maybe<&2, T.JsonValue> <- capture(model, Some{T.Medium{}})
    H.equalJson(H.pathOf(["thinking", "type"], payload), "\"enabled\"", name)
    H.absent(H.fieldOf(payload, "output_config"), name)
    H.pass(name)

def adaptive(model: T.Model<T.JsonValue>, reasoning: T.ThinkingLevel, +effort: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    +payload : Maybe<&2, T.JsonValue> <- capture(model, Some{reasoning})
    H.equalJson(H.fieldOf(payload, "thinking"), "{\"type\":\"adaptive\",\"display\":\"summarized\"}", name)
    H.equalJson(H.fieldOf(payload, "output_config"), "{\"effort\":\"" ++ effort ++ "\"}", name)
    H.pass(name)

def disabled(+name: String) -> IO(Unit):
  do IO<Unit>:
    +payload : Maybe<&2, T.JsonValue> <- capture(customModel(Some{forced(True{})}), None{})
    H.equalJson(H.fieldOf(payload, "thinking"), "{\"type\":\"disabled\"}", name)
    H.absent(H.fieldOf(payload, "output_config"), name)
    H.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    legacy(customModel(None{}), "sends legacy thinking payload for custom model ids by default")
    adaptive(customModel(Some{forced(True{})}), T.Medium{}, "medium", "sends adaptive thinking payload when compat.forceAdaptiveThinking is true")
    adaptive(Catalog.model_claude_fable_5(), T.XHigh{}, "xhigh", "uses adaptive thinking with native xhigh effort for Claude Fable 5")
    adaptive(Kimi.model_kimi_for_coding(), T.Medium{}, "medium", "uses adaptive thinking effort without a token budget for Kimi Coding kimi-for-coding")
    adaptive(Kimi.model_k3(), T.Max{}, "max", "uses adaptive thinking effort without a token budget for Kimi Coding k3")
    adaptive(Kimi.model_kimi_for_coding_highspeed(), T.Medium{}, "medium", "uses adaptive thinking effort without a token budget for Kimi Coding kimi-for-coding-highspeed")
    legacy(H.withCompat(Catalog.model_claude_opus_4_8(), forced(False{})), "allows built-in adaptive models to opt out with compat.forceAdaptiveThinking false")
    disabled("preserves thinking.type=disabled when reasoning is off regardless of override")

import Base
import ../src/providers/anthropic.models.bend as Catalog
import ../src/types.bend as T
import ./anthropic-harness.bend as H
import ../../runtime/src/f64.bend as F

# pi-mono f07218c4d packages/ai/test/anthropic-temperature-compat.test.ts:
# streamSimple's payload, captured by onPayload.
def capture(model: T.Model<T.JsonValue>, temperature: U32) -> IO(Maybe<&2, T.JsonValue>):
  +selected = H.withBase(model, "http://127.0.0.1:9")
  +context = H.hello()
  do IO<Maybe<&2, T.JsonValue>>:
    outcome : H.Outcome <- H.runSimple(selected, context, H.simple(Some{"fake-key"}, Some{F.fromU32(temperature)}, None{}), H.Capture{})
    return H.payloadOf(outcome)

def omitted(model: T.Model<T.JsonValue>, temperature: U32, +name: String) -> IO(Unit):
  do IO<Unit>:
    +payload : Maybe<&2, T.JsonValue> <- capture(model, temperature)
    H.check(Maybe.is_some(&2, T.JsonValue, payload), name ++ ": payload captured")
    H.absent(H.fieldOf(payload, "temperature"), name)
    H.pass(name)

def kept(model: T.Model<T.JsonValue>, +name: String) -> IO(Unit):
  do IO<Unit>:
    +payload : Maybe<&2, T.JsonValue> <- capture(model, 0)
    H.equalJson(H.fieldOf(payload, "temperature"), "0", name)
    H.pass(name)

def supportsNoTemperature() -> T.AnthropicMessagesCompat:
  T.AnthropicMessagesCompat{None{}, None{}, None{}, None{}, None{}, Some{False{}}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def run() -> IO(Unit):
  do IO<Unit>:
    omitted(Catalog.model_claude_opus_4_7(), 0, "omits temperature for Claude Opus 4.7")
    omitted(Catalog.model_claude_opus_4_8(), 0, "omits temperature for Claude Opus 4.8")
    omitted(Catalog.model_claude_opus_4_7(), 1, "omits default temperature for Claude Opus 4.7")
    kept(Catalog.model_claude_opus_4_6(), "keeps temperature for Claude Opus 4.6")
    kept(Catalog.model_claude_sonnet_4_6(), "keeps temperature for Claude Sonnet 4.6")
    omitted(H.custom("vendor--claude-opus-4-7", "Vendor Proxy Opus 4.7", "vendor-proxy", "http://127.0.0.1:9", 32000, 200000, None{}, Some{supportsNoTemperature()}), 0, "omits temperature for custom models with supportsTemperature disabled")

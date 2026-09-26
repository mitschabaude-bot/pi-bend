import Base
import ../src/providers/anthropic.models.bend as Catalog
import ../src/types.bend as T
import ./anthropic-harness.bend as H

# pi-mono f07218c4d packages/ai/test/anthropic-thinking-disable.test.ts, the
# payload suite. The E2E suite needs ANTHROPIC_API_KEY and stays pending.
def capture(model: T.Model<T.JsonValue>, reasoning: Maybe<&2, T.ThinkingLevel>) -> IO(Maybe<&2, T.JsonValue>):
  +selected = H.withBase(model, "http://127.0.0.1:9")
  +context = H.hello()
  do IO<Maybe<&2, T.JsonValue>>:
    outcome : H.Outcome <- H.runSimple(selected, context, H.simple(Some{"fake-key"}, None{}, reasoning), H.Capture{})
    return H.payloadOf(outcome)

def disabled(model: T.Model<T.JsonValue>, +name: String) -> IO(Unit):
  do IO<Unit>:
    +payload : Maybe<&2, T.JsonValue> <- capture(model, None{})
    H.equalJson(H.fieldOf(payload, "thinking"), "{\"type\":\"disabled\"}", name)
    H.absent(H.fieldOf(payload, "output_config"), name)
    H.pass(name)

def omitted(model: T.Model<T.JsonValue>, +name: String) -> IO(Unit):
  do IO<Unit>:
    +payload : Maybe<&2, T.JsonValue> <- capture(model, None{})
    H.check(Maybe.is_some(&2, T.JsonValue, payload), name ++ ": payload captured")
    H.absent(H.fieldOf(payload, "thinking"), name)
    H.absent(H.fieldOf(payload, "output_config"), name)
    H.pass(name)

def adaptive(model: T.Model<T.JsonValue>, reasoning: T.ThinkingLevel, +effort: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    +payload : Maybe<&2, T.JsonValue> <- capture(model, Some{reasoning})
    H.equalJson(H.fieldOf(payload, "thinking"), "{\"type\":\"adaptive\",\"display\":\"summarized\"}", name)
    H.equalJson(H.fieldOf(payload, "output_config"), "{\"effort\":\"" ++ effort ++ "\"}", name)
    H.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    disabled(Catalog.model_claude_sonnet_4_5(), "sends thinking.type=disabled for budget-based reasoning models when thinking is off")
    disabled(Catalog.model_claude_opus_4_6(), "sends thinking.type=disabled for adaptive reasoning models when thinking is off")
    disabled(Catalog.model_claude_opus_4_8(), "sends thinking.type=disabled for Claude Opus 4.8 when thinking is off")
    omitted(Catalog.model_claude_fable_5(), "omits thinking.type=disabled for Claude Fable 5 when thinking is off")
    adaptive(Catalog.model_claude_opus_4_8(), T.High{}, "high", "uses adaptive thinking for Claude Opus 4.8 when reasoning is enabled")
    adaptive(Catalog.model_claude_sonnet_5(), T.High{}, "high", "uses adaptive thinking for Claude Sonnet 5 when reasoning is enabled")
    adaptive(Catalog.model_claude_opus_4_8(), T.XHigh{}, "xhigh", "maps xhigh reasoning to effort=xhigh for Claude Opus 4.8")

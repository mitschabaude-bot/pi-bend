import Base
import ../src/providers/fireworks.models.bend as Fireworks
import ../src/providers/kimi-coding.models.bend as Kimi
import ../src/providers/vercel-ai-gateway.models.bend as Vercel
import ../src/types.bend as T
import ./anthropic-harness.bend as H
import ../../runtime/src/schema-value.bend as V

def allowing(value: Bool) -> T.AnthropicMessagesCompat:
  T.AnthropicMessagesCompat{None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{value}, None{}, None{}, None{}, None{}, None{}}

def makeContext(content: List<&2, T.AssistantContent<V.Value>>, provider: String, model: String) -> H.Context():
  H.context(H.user("first", 1) <> H.assistant(content, provider, model, None{}) <> H.user("second", 2) <> Nil{})

def capture(+model: T.Model<T.JsonValue>, +context: H.Context()) -> IO(Maybe<&2, T.JsonValue>):
  do IO<Maybe<&2, T.JsonValue>>:
    outcome : H.Outcome <- H.run(model, context, H.fromSimple(model, context, H.simple(Some{"fake-key"}, None{}, None{})), H.Capture{})
    return H.payloadOf(outcome)

def assistantContent(model: T.Model<T.JsonValue>, context: H.Context(), +want: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    +payload : Maybe<&2, T.JsonValue> <- capture(model, context)
    H.equalJson(H.fieldOf(H.payloadMessage(payload, "assistant"), "content"), want, name)
    H.pass(name)

def mimo(thinking: String, signature: String) -> H.Context():
  makeContext(H.thinkingBlock(thinking, signature) <> Nil{}, "xiaomi-token-plan-ams", "mimo-v2.5-pro")

# pi-mono f07218c4d packages/ai/test/anthropic-empty-thinking-signature-compat.test.ts.
def makeModel(allowEmptySignature: Maybe<&2, Bool>) -> T.Model<T.JsonValue>:
  H.custom("mimo-v2.5-pro", "MiMo-V2.5-Pro", "xiaomi-token-plan-ams", "http://127.0.0.1:9/anthropic", 1024, 1048576, None{}, Maybe.map(&2, Bool, T.AnthropicMessagesCompat, allowing, allowEmptySignature))

def allowsEmpty(model: T.Model<T.JsonValue>) -> Bool:
  match model:
    case T.Model{_, _, T.AnthropicMessagesApi{}, _, _, _, _, _, _, _, _, _, _, _, _, Some{T.AnthropicMessagesCompat{_, _, _, _, _, _, _, Some{True{}}, _, _, _, _, _}}}: True{}
    case _: False{}

def everyAllows(models: List<&2, T.Model<T.JsonValue>>) -> Bool:
  match models:
    case Nil{}: True{}
    case model <> rest: allowsEmpty(model) && everyAllows(rest)

def fireworks(model: T.Model<T.JsonValue>, +id: String) -> IO(Unit):
  +name = "preserves unsigned thinking for Fireworks " ++ id
  +selected = model
  do IO<Unit>:
    H.check(allowsEmpty(selected), name ++ ": allowEmptySignature")
    assistantContent(selected, makeContext(H.thinkingBlock("internal reasoning", "") <> H.textBlock("answer") <> Nil{}, "fireworks", id), "[{\"type\":\"thinking\",\"thinking\":\"internal reasoning\",\"signature\":\"\"},{\"type\":\"text\",\"text\":\"answer\"}]", name)

def run() -> IO(Unit):
  do IO<Unit>:
    assistantContent(makeModel(None{}), mimo("internal reasoning", ""), "[{\"type\":\"text\",\"text\":\"internal reasoning\"}]", "converts empty-signature thinking to text by default")
    assistantContent(makeModel(None{}), mimo("", "signed-thinking"), "[{\"type\":\"thinking\",\"thinking\":\"\",\"signature\":\"signed-thinking\"}]", "preserves empty thinking text when the signature is present")
    assistantContent(makeModel(Some{True{}}), mimo("internal reasoning", " "), "[{\"type\":\"thinking\",\"thinking\":\"internal reasoning\",\"signature\":\"\"}]", "preserves empty-signature thinking when allowEmptySignature is enabled")
    H.check(Bool.not(List.is_empty(&2, T.Model<T.JsonValue>, Vercel.VERCEL_AI_GATEWAY_MODELS())) && everyAllows(Vercel.VERCEL_AI_GATEWAY_MODELS()), "every Vercel AI Gateway model allows empty signatures")
    H.pass("allows empty thinking signatures for every Vercel AI Gateway model")
    fireworks(Fireworks.model_accounts_fireworks_models_deepseek_v4_flash_0731(), "accounts/fireworks/models/deepseek-v4-flash-0731")
    fireworks(Fireworks.model_accounts_fireworks_models_deepseek_v4_flash_vision_exp(), "accounts/fireworks/models/deepseek-v4-flash-vision-exp")
    fireworks(Fireworks.model_accounts_fireworks_models_deepseek_v4_pro_0813(), "accounts/fireworks/models/deepseek-v4-pro-0813")
    fireworks(Fireworks.model_accounts_fireworks_models_qwen3p8_max(), "accounts/fireworks/models/qwen3p8-max")
    fireworks(Fireworks.model_accounts_fireworks_models_qwen3p8_2p4t_a95b(), "accounts/fireworks/models/qwen3p8-2p4t-a95b")
    fireworks(Fireworks.model_accounts_fireworks_models_kimi_k2p6(), "accounts/fireworks/models/kimi-k2p6")
    assistantContent(Fireworks.model_accounts_fireworks_models_deepseek_v4_flash_0731(), makeContext(H.thinkingBlock("internal reasoning", "") <> Nil{}, "fireworks", "accounts/fireworks/models/kimi-k2p6"), "[{\"type\":\"text\",\"text\":\"internal reasoning\"}]", "still converts cross-model Fireworks thinking to text")
    H.check(allowsEmpty(Kimi.model_k3()), "k3 allows empty signatures")
    assistantContent(Kimi.model_k3(), makeContext(H.thinkingBlock("internal reasoning", " ") <> Nil{}, "kimi-coding", "k3"), "[{\"type\":\"thinking\",\"thinking\":\"internal reasoning\",\"signature\":\"\"}]", "allows empty signatures for Kimi Coding k3")

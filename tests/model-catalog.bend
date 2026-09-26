import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/model-json.bend as MJ
import ../packages/ai/src/models.bend as Models
import ../packages/ai/src/utils/thinking-levels.bend as Thinking
import ../packages/ai/src/utils/json.bend as Json
import ../packages/ai/src/utils/schema-json.bend as S
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/ai/src/providers/amazon-bedrock.models.bend as C0
import ../packages/ai/src/providers/ant-ling.models.bend as C1
import ../packages/ai/src/providers/anthropic.models.bend as C2
import ../packages/ai/src/providers/azure-openai-responses.models.bend as C3
import ../packages/ai/src/providers/baseten.models.bend as C4
import ../packages/ai/src/providers/cerebras.models.bend as C5
import ../packages/ai/src/providers/cloudflare-ai-gateway.models.bend as C6
import ../packages/ai/src/providers/cloudflare-workers-ai.models.bend as C7
import ../packages/ai/src/providers/deepseek.models.bend as C8
import ../packages/ai/src/providers/fireworks.models.bend as C9
import ../packages/ai/src/providers/github-copilot.models.bend as C10
import ../packages/ai/src/providers/google-vertex.models.bend as C11
import ../packages/ai/src/providers/google.models.bend as C12
import ../packages/ai/src/providers/groq.models.bend as C13
import ../packages/ai/src/providers/huggingface.models.bend as C14
import ../packages/ai/src/providers/kimi-coding.models.bend as C15
import ../packages/ai/src/providers/meta.models.bend as C16
import ../packages/ai/src/providers/minimax-cn.models.bend as C17
import ../packages/ai/src/providers/minimax.models.bend as C18
import ../packages/ai/src/providers/mistral.models.bend as C19
import ../packages/ai/src/providers/moonshotai-cn.models.bend as C20
import ../packages/ai/src/providers/moonshotai.models.bend as C21
import ../packages/ai/src/providers/nvidia.models.bend as C22
import ../packages/ai/src/providers/openai-codex.models.bend as C23
import ../packages/ai/src/providers/openai.models.bend as C24
import ../packages/ai/src/providers/opencode-go.models.bend as C25
import ../packages/ai/src/providers/opencode.models.bend as C26
import ../packages/ai/src/providers/openrouter.models.bend as C27
import ../packages/ai/src/providers/qwen-token-plan-cn.models.bend as C28
import ../packages/ai/src/providers/qwen-token-plan-individual.models.bend as C29
import ../packages/ai/src/providers/qwen-token-plan.models.bend as C30
import ../packages/ai/src/providers/together.models.bend as C31
import ../packages/ai/src/providers/vercel-ai-gateway.models.bend as C32
import ../packages/ai/src/providers/xai.models.bend as C33
import ../packages/ai/src/providers/xiaomi-token-plan-ams.models.bend as C34
import ../packages/ai/src/providers/xiaomi-token-plan-cn.models.bend as C35
import ../packages/ai/src/providers/xiaomi-token-plan-sgp.models.bend as C36
import ../packages/ai/src/providers/xiaomi.models.bend as C37
import ../packages/ai/src/providers/zai-coding-cn.models.bend as C38
import ../packages/ai/src/providers/zai.models.bend as C39

# Every built-in model, one per line as {"model": <public JSON shape of
# upstream Model>, "levels": <getSupportedThinkingLevels>}:
# tests/model_catalog.test.ts runs upstream catalog assertions on them.
# Generated imports: one per providers/*.models.bend catalog.
def levelNames(levels: List<&2, T.ModelThinkingLevel>) -> List<&2, V.Value>:
  match levels:
    case Nil{}: Nil{}
    case level <> rest: V.Text{Thinking.name(level)} <> levelNames(rest)
def entry(+model: T.Model<T.JsonValue>) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"model", MJ.model(model)} <> R.Property{"levels", V.ArrayValue{levelNames(Models.getSupportedThinkingLevels(T.JsonValue, model))}} <> Nil{}}}
def line(model: T.Model<T.JsonValue>) -> String: Maybe.default(&2, String, Json.stringify(S.toJson(entry(model))), "null")
def lines(models: List<&2, T.Model<T.JsonValue>>) -> String:
  match models:
    case Nil{}: ""
    case m <> rest: line(m) ++ "\n" ++ lines(rest)
def catalogs() -> List<&2, List<&2, T.Model<T.JsonValue>>>: [C0.AMAZON_BEDROCK_MODELS(), C1.ANT_LING_MODELS(), C2.ANTHROPIC_MODELS(), C3.AZURE_OPENAI_RESPONSES_MODELS(), C4.BASETEN_MODELS(), C5.CEREBRAS_MODELS(), C6.CLOUDFLARE_AI_GATEWAY_MODELS(), C7.CLOUDFLARE_WORKERS_AI_MODELS(), C8.DEEPSEEK_MODELS(), C9.FIREWORKS_MODELS(), C10.GITHUB_COPILOT_MODELS(), C11.GOOGLE_VERTEX_MODELS(), C12.GOOGLE_MODELS(), C13.GROQ_MODELS(), C14.HUGGINGFACE_MODELS(), C15.KIMI_CODING_MODELS(), C16.META_MODELS(), C17.MINIMAX_CN_MODELS(), C18.MINIMAX_MODELS(), C19.MISTRAL_MODELS(), C20.MOONSHOTAI_CN_MODELS(), C21.MOONSHOTAI_MODELS(), C22.NVIDIA_MODELS(), C23.OPENAI_CODEX_MODELS(), C24.OPENAI_MODELS(), C25.OPENCODE_GO_MODELS(), C26.OPENCODE_MODELS(), C27.OPENROUTER_MODELS(), C28.QWEN_TOKEN_PLAN_CN_MODELS(), C29.QWEN_TOKEN_PLAN_INDIVIDUAL_MODELS(), C30.QWEN_TOKEN_PLAN_MODELS(), C31.TOGETHER_MODELS(), C32.VERCEL_AI_GATEWAY_MODELS(), C33.XAI_MODELS(), C34.XIAOMI_TOKEN_PLAN_AMS_MODELS(), C35.XIAOMI_TOKEN_PLAN_CN_MODELS(), C36.XIAOMI_TOKEN_PLAN_SGP_MODELS(), C37.XIAOMI_MODELS(), C38.ZAI_CODING_CN_MODELS(), C39.ZAI_MODELS()]
def each(groups: List<&2, List<&2, T.Model<T.JsonValue>>>) -> String:
  match groups:
    case Nil{}: ""
    case g <> rest: lines(g) ++ each(rest)
def main() -> IO(Unit): IO.print(each(catalogs()))

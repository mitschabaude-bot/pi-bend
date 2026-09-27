import Base
import ../../ai/src/types.bend as Ai
import ../../ai/src/api/openai-responses.bend as Responses
import ../../ai/src/api/azure-openai-responses.bend as Azure
import ../../ai/src/api/openai-codex-responses.bend as Codex
import ../../ai/src/api/anthropic-messages.bend as Messages
import ../../ai/src/api/google-generative-ai.bend as Gemini
import ../../ai/src/api/openai-completions.bend as Chat
import ../../ai/src/utils/event-stream.bend as Events
import ../../ai/src/utils/message-json.bend as MessageJson
import ../../ai/src/utils/schema-json.bend as Convert
import ../../ai/src/utils/json.bend as Wire
import ../../ai/src/utils/transcript.bend as Transcript
import ../../ai/src/utils/overflow.bend as Overflow
import ../../ai/src/providers/ant-ling.models.bend as CatalogAntLing
import ../../ai/src/providers/anthropic.models.bend as CatalogAnthropic
import ../../ai/src/providers/azure-openai-responses.models.bend as CatalogAzureOpenaiResponses
import ../../ai/src/providers/baseten.models.bend as CatalogBaseten
import ../../ai/src/providers/cerebras.models.bend as CatalogCerebras
import ../../ai/src/providers/cloudflare-ai-gateway.models.bend as CatalogCloudflareAiGateway
import ../../ai/src/providers/cloudflare-workers-ai.models.bend as CatalogCloudflareWorkersAi
import ../../ai/src/providers/deepseek.models.bend as CatalogDeepseek
import ../../ai/src/providers/fireworks.models.bend as CatalogFireworks
import ../../ai/src/providers/github-copilot.models.bend as CatalogGithubCopilot
import ../../ai/src/providers/google.models.bend as CatalogGoogle
import ../../ai/src/providers/groq.models.bend as CatalogGroq
import ../../ai/src/providers/huggingface.models.bend as CatalogHuggingface
import ../../ai/src/providers/kimi-coding.models.bend as CatalogKimiCoding
import ../../ai/src/providers/meta.models.bend as CatalogMeta
import ../../ai/src/providers/minimax.models.bend as CatalogMinimax
import ../../ai/src/providers/minimax-cn.models.bend as CatalogMinimaxCn
import ../../ai/src/providers/nvidia.models.bend as CatalogNvidia
import ../../ai/src/providers/openai.models.bend as CatalogOpenai
import ../../ai/src/providers/openai-codex.models.bend as CatalogOpenaiCodex
import ../../ai/src/providers/opencode.models.bend as CatalogOpencode
import ../../ai/src/providers/opencode-go.models.bend as CatalogOpencodeGo
import ../../ai/src/providers/openrouter.models.bend as CatalogOpenrouter
import ../../ai/src/providers/qwen-token-plan.models.bend as CatalogQwenTokenPlan
import ../../ai/src/providers/qwen-token-plan-cn.models.bend as CatalogQwenTokenPlanCn
import ../../ai/src/providers/qwen-token-plan-individual.models.bend as CatalogQwenTokenPlanIndividual
import ../../ai/src/providers/together.models.bend as CatalogTogether
import ../../ai/src/providers/vercel-ai-gateway.models.bend as CatalogVercelAiGateway
import ../../ai/src/providers/xai.models.bend as CatalogXai
import ../../ai/src/providers/xiaomi.models.bend as CatalogXiaomi
import ../../ai/src/providers/xiaomi-token-plan-ams.models.bend as CatalogXiaomiTokenPlanAms
import ../../ai/src/providers/xiaomi-token-plan-cn.models.bend as CatalogXiaomiTokenPlanCn
import ../../ai/src/providers/xiaomi-token-plan-sgp.models.bend as CatalogXiaomiTokenPlanSgp
import ../../ai/src/providers/zai.models.bend as CatalogZai
import ../../agent/src/providers.bend as Providers
import ../../ai/src/utils/model-json.bend as ModelJson
import ../../ai/src/models.bend as AiModels
import ../../ai/src/api/openai-client.bend as OpenAIClient
import ../../runtime/src/pi-user-agent.bend as UserAgent
import ../src/core/provider-composer.bend as Composer
import ../src/core/model-config.bend as ModelConfig
import ../../agent/src/types.bend as Agent
import ../src/core/anthropic-provider.bend as Anthropic
import ../src/core/google-provider.bend as Google
import ../src/core/openai-completions-provider.bend as Completions
import ../../ai/test/responses-payload.bend as RP
import ../../ai/test/anthropic-messages-client.bend as TestClient
import ../src/core/tools/index.bend as Tools
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/record.bend as R
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/utf16.bend as Utf16
import ../../runtime/test/utf8-runner.bend as Text
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/utf8.bend as Utf8

# One request of pi-mono's live provider suites (stream, abort, empty, tokens,
# total-tokens, unicode-surrogate, context-overflow, tool-call-without-result,
# cross-provider-handoff) through the CLI's provider streams, against the
# loopback server of tests/live_replay_check.py, which replays provider wire
# responses. tests/live_replay_reference.ts runs the same case through
# pinned pi-mono. The first argument is the server's base URL; the second is
# the case as JSON (comma-separated code points):
#   {run, provider, model, api?, entry: "stream" | "simple", context,
#    options: {apiKey?, transport?, reasoning?, thinkingEnabled?, thinkingBudgetTokens?, effort?,
#    thinking?: {enabled, budgetTokens?}, reasoningEffort?},
#    abortAfterChars?, abortBefore?, overflow?}
# The model is the built-in catalog model with its base URL replaced by
# `<base>/<run>` (and, with `api`, its API replaced and compat dropped, as
# the suites do for OpenAI Completions). `overflow` replaces the context with
# the context-overflow suite's generated prompt for the model's window.
# Output: "E <type>[:<delta>]" per event (deltas as code points), then "R <message JSON>", or
# "T <message>" when the stream fails before it exists.
def J() -> Data: Ai.JsonValue
def Details() -> Data: Tools.ToolDetails
def Error() -> Data: Tools.ToolError
def Model() -> Data: Ai.Model<J()>
def Context() -> Data: Ai.TranscriptContext<V.Value, V.Value, Unit, Details()>
def StreamEvent() -> Data: Ai.AssistantMessageEvent<V.Value, Unit>
def Message() -> Data: Ai.AssistantMessage<V.Value, Unit>
def Output() -> Type: Result<&2, &1, Error(), Agent.StreamLease<Unit, Error()>>
def Base() -> Data: Ai.StreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>
def Simple() -> Data: Ai.SimpleStreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>

# Case decoding
# -------------
def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def text(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{item}}: Some{item}
    case _: None{}

def number(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{item}}: Some{item}
    case _: None{}

def flag(value: Maybe<&2, V.Value>) -> Maybe<&2, Bool>:
  match value:
    case Some{V.Boolean{item}}: Some{item}
    case _: None{}

def list(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{values}}: values
    case _: Nil{}

def noDiagnostics(value: V.Value) -> MessageJson.Decoded(Unit):
  Fail{Decode.WrongType{Nil{}, "no diagnostic details"}}

def noDetails(value: V.Value) -> MessageJson.Decoded(Details()):
  Fail{Decode.WrongType{Nil{}, "no tool details"}}

def prependedMessage(value: MessageJson.Decoded(Ai.Message<V.Value, V.Value, Unit, Details()>), rest: Result<&2, &2, String, List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>>) -> Result<&2, &2, String, List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>>:
  match value rest:
    case Done{message} Done{messages}: Done{message <> messages}
    case Fail{_} _: Fail{"invalid message"}
    case _ Fail{error}: Fail{error}

def decodedMessages(values: List<&2, V.Value>) -> Result<&2, &2, String, List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>>:
  match values:
    case Nil{}: Done{Nil{}}
    case +first <> rest: prependedMessage(MessageJson.decodeMessage(~Unit, ~Details(), ~noDiagnostics, ~noDetails, first), decodedMessages(rest))

def prependedTool(value: MessageJson.Decoded(Ai.Tool<V.Value>), rest: Result<&2, &2, String, List<&2, Ai.Tool<V.Value>>>) -> Result<&2, &2, String, List<&2, Ai.Tool<V.Value>>>:
  match value rest:
    case Done{tool} Done{tools}: Done{tool <> tools}
    case Fail{_} _: Fail{"invalid tool"}
    case _ Fail{error}: Fail{error}

def decodedTools(values: List<&2, V.Value>) -> Result<&2, &2, String, List<&2, Ai.Tool<V.Value>>>:
  match values:
    case Nil{}: Done{Nil{}}
    case first <> rest: prependedTool(MessageJson.decodeTool(first), decodedTools(rest))

def someTools(value: Result<&2, &2, String, List<&2, Ai.Tool<V.Value>>>) -> Result<&2, &2, String, Maybe<&2, List<&2, Ai.Tool<V.Value>>>>:
  match value:
    case Done{tools}: Done{Some{tools}}
    case Fail{error}: Fail{error}

def toolsOf(value: Maybe<&2, V.Value>) -> Result<&2, &2, String, Maybe<&2, List<&2, Ai.Tool<V.Value>>>>:
  match value:
    case Some{V.ArrayValue{values}}: someTools(decodedTools(values))
    case _: Done{None{}}

def contextWith(system: Maybe<&2, String>, messages: Result<&2, &2, String, List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>>, tools: Result<&2, &2, String, Maybe<&2, List<&2, Ai.Tool<V.Value>>>>) -> Result<&2, &2, String, Context()>:
  match messages tools:
    case Done{items} Done{declared}: Done{Transcript.normalizeContext(V.Value, V.Value, Unit, Details(), Ai.Context{system, items, declared})}
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}

def contextOf(+value: V.Value) -> Result<&2, &2, String, Context()>:
  contextWith(text(field(value, "systemPrompt")), decodedMessages(list(field(value, "messages"))), toolsOf(field(value, "tools")))

# Models
# ------
# The built-in catalog models the replayed suites use (upstream getModel).
def catalogModel(+key: String) -> Maybe<&2, Model()>:
  match key:
    case "ant-ling/Ling-2.6-flash": Some{CatalogAntLing.model_Ling_2_6_flash()}
    case "ant-ling/Ring-2.6-1T": Some{CatalogAntLing.model_Ring_2_6_1T()}
    case "anthropic/claude-haiku-4-5": Some{CatalogAnthropic.model_claude_haiku_4_5()}
    case "anthropic/claude-opus-4-5": Some{CatalogAnthropic.model_claude_opus_4_5()}
    case "anthropic/claude-opus-4-6": Some{CatalogAnthropic.model_claude_opus_4_6()}
    case "anthropic/claude-sonnet-4-5": Some{CatalogAnthropic.model_claude_sonnet_4_5()}
    case "anthropic/claude-sonnet-4-6": Some{CatalogAnthropic.model_claude_sonnet_4_6()}
    case "azure-openai-responses/gpt-4o-mini": Some{CatalogAzureOpenaiResponses.model_gpt_4o_mini()}
    case "baseten/deepseek-ai/DeepSeek-V4-Flash-0731": Some{CatalogBaseten.model_deepseek_ai_DeepSeek_V4_Flash_0731()}
    case "baseten/deepseek-ai/DeepSeek-V4-Pro": Some{CatalogBaseten.model_deepseek_ai_DeepSeek_V4_Pro()}
    case "baseten/deepseek-ai/DeepSeek-V4-Pro-0813": Some{CatalogBaseten.model_deepseek_ai_DeepSeek_V4_Pro_0813()}
    case "baseten/deepseek-ai/DeepSeek-V4.1-Flash": Some{CatalogBaseten.model_deepseek_ai_DeepSeek_V4_1_Flash()}
    case "baseten/moonshotai/Kimi-K2.5": Some{CatalogBaseten.model_moonshotai_Kimi_K2_5()}
    case "baseten/moonshotai/Kimi-K2.6": Some{CatalogBaseten.model_moonshotai_Kimi_K2_6()}
    case "baseten/moonshotai/Kimi-K2.7-Code": Some{CatalogBaseten.model_moonshotai_Kimi_K2_7_Code()}
    case "baseten/moonshotai/Kimi-K3": Some{CatalogBaseten.model_moonshotai_Kimi_K3()}
    case "baseten/nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B": Some{CatalogBaseten.model_nvidia_NVIDIA_Nemotron_3_Ultra_550B_A55B()}
    case "baseten/nvidia/Nemotron-120B-A12B": Some{CatalogBaseten.model_nvidia_Nemotron_120B_A12B()}
    case "baseten/openai/gpt-oss-120b": Some{CatalogBaseten.model_openai_gpt_oss_120b()}
    case "baseten/thinkingmachines/inkling": Some{CatalogBaseten.model_thinkingmachines_inkling()}
    case "baseten/thinkingmachines/inkling-small": Some{CatalogBaseten.model_thinkingmachines_inkling_small()}
    case "baseten/zai-org/GLM-4.7": Some{CatalogBaseten.model_zai_org_GLM_4_7()}
    case "baseten/zai-org/GLM-5": Some{CatalogBaseten.model_zai_org_GLM_5()}
    case "baseten/zai-org/GLM-5.1": Some{CatalogBaseten.model_zai_org_GLM_5_1()}
    case "baseten/zai-org/GLM-5.2": Some{CatalogBaseten.model_zai_org_GLM_5_2()}
    case "baseten/zai-org/GLM-5.2-Fast": Some{CatalogBaseten.model_zai_org_GLM_5_2_Fast()}
    case "baseten/zai-org/GLM-5.3": Some{CatalogBaseten.model_zai_org_GLM_5_3()}
    case "baseten/zai-org/GLM-5.3-Fast": Some{CatalogBaseten.model_zai_org_GLM_5_3_Fast()}
    case "baseten/zai-org/GLM-5.3-Flash": Some{CatalogBaseten.model_zai_org_GLM_5_3_Flash()}
    case "cerebras/gpt-oss-120b": Some{CatalogCerebras.model_gpt_oss_120b()}
    case "cloudflare-ai-gateway/claude-sonnet-4.5": Some{CatalogCloudflareAiGateway.model_claude_sonnet_4_5()}
    case "cloudflare-ai-gateway/gpt-5.1": Some{CatalogCloudflareAiGateway.model_gpt_5_1()}
    case "cloudflare-ai-gateway/gpt-5.6-sol": Some{CatalogCloudflareAiGateway.model_gpt_5_6_sol()}
    case "cloudflare-ai-gateway/workers-ai/@cf/moonshotai/kimi-k2.6": Some{CatalogCloudflareAiGateway.model_workers_ai__cf_moonshotai_kimi_k2_6()}
    case "cloudflare-workers-ai/@cf/moonshotai/kimi-k2.6": Some{CatalogCloudflareWorkersAi.model__cf_moonshotai_kimi_k2_6()}
    case "deepseek/deepseek-flash": Some{CatalogDeepseek.model_deepseek_flash()}
    case "fireworks/accounts/fireworks/models/deepseek-v4-flash-0731": Some{CatalogFireworks.model_accounts_fireworks_models_deepseek_v4_flash_0731()}
    case "fireworks/accounts/fireworks/models/deepseek-v4-flash-vision-exp": Some{CatalogFireworks.model_accounts_fireworks_models_deepseek_v4_flash_vision_exp()}
    case "fireworks/accounts/fireworks/models/deepseek-v4-pro": Some{CatalogFireworks.model_accounts_fireworks_models_deepseek_v4_pro()}
    case "fireworks/accounts/fireworks/models/deepseek-v4-pro-0813": Some{CatalogFireworks.model_accounts_fireworks_models_deepseek_v4_pro_0813()}
    case "fireworks/accounts/fireworks/models/deepseek-v4p1-flash": Some{CatalogFireworks.model_accounts_fireworks_models_deepseek_v4p1_flash()}
    case "fireworks/accounts/fireworks/models/glm-5p2": Some{CatalogFireworks.model_accounts_fireworks_models_glm_5p2()}
    case "fireworks/accounts/fireworks/models/glm-5p3": Some{CatalogFireworks.model_accounts_fireworks_models_glm_5p3()}
    case "fireworks/accounts/fireworks/models/glm-5p3-flash": Some{CatalogFireworks.model_accounts_fireworks_models_glm_5p3_flash()}
    case "fireworks/accounts/fireworks/models/gpt-oss-120b": Some{CatalogFireworks.model_accounts_fireworks_models_gpt_oss_120b()}
    case "fireworks/accounts/fireworks/models/inkling": Some{CatalogFireworks.model_accounts_fireworks_models_inkling()}
    case "fireworks/accounts/fireworks/models/kimi-k2p6": Some{CatalogFireworks.model_accounts_fireworks_models_kimi_k2p6()}
    case "fireworks/accounts/fireworks/models/kimi-k2p7-code": Some{CatalogFireworks.model_accounts_fireworks_models_kimi_k2p7_code()}
    case "fireworks/accounts/fireworks/models/kimi-k3": Some{CatalogFireworks.model_accounts_fireworks_models_kimi_k3()}
    case "fireworks/accounts/fireworks/models/minimax-m2p7": Some{CatalogFireworks.model_accounts_fireworks_models_minimax_m2p7()}
    case "fireworks/accounts/fireworks/models/minimax-m3": Some{CatalogFireworks.model_accounts_fireworks_models_minimax_m3()}
    case "fireworks/accounts/fireworks/models/muse-glimmer-30b": Some{CatalogFireworks.model_accounts_fireworks_models_muse_glimmer_30b()}
    case "fireworks/accounts/fireworks/models/nemotron-3-ultra-nvfp4": Some{CatalogFireworks.model_accounts_fireworks_models_nemotron_3_ultra_nvfp4()}
    case "fireworks/accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b": Some{CatalogFireworks.model_accounts_fireworks_models_nemotron_lightning_3p5_30b_a3b()}
    case "fireworks/accounts/fireworks/models/qwen3p7-plus": Some{CatalogFireworks.model_accounts_fireworks_models_qwen3p7_plus()}
    case "fireworks/accounts/fireworks/models/qwen3p8-2p4t-a95b": Some{CatalogFireworks.model_accounts_fireworks_models_qwen3p8_2p4t_a95b()}
    case "fireworks/accounts/fireworks/models/qwen3p8-max": Some{CatalogFireworks.model_accounts_fireworks_models_qwen3p8_max()}
    case "fireworks/accounts/fireworks/routers/deepseek-flash-latest": Some{CatalogFireworks.model_accounts_fireworks_routers_deepseek_flash_latest()}
    case "fireworks/accounts/fireworks/routers/deepseek-pro-latest": Some{CatalogFireworks.model_accounts_fireworks_routers_deepseek_pro_latest()}
    case "fireworks/accounts/fireworks/routers/glm-5p2-fast": Some{CatalogFireworks.model_accounts_fireworks_routers_glm_5p2_fast()}
    case "fireworks/accounts/fireworks/routers/glm-5p3-fast": Some{CatalogFireworks.model_accounts_fireworks_routers_glm_5p3_fast()}
    case "fireworks/accounts/fireworks/routers/glm-fast-latest": Some{CatalogFireworks.model_accounts_fireworks_routers_glm_fast_latest()}
    case "fireworks/accounts/fireworks/routers/glm-flash-latest": Some{CatalogFireworks.model_accounts_fireworks_routers_glm_flash_latest()}
    case "fireworks/accounts/fireworks/routers/glm-latest": Some{CatalogFireworks.model_accounts_fireworks_routers_glm_latest()}
    case "fireworks/accounts/fireworks/routers/kimi-fast-latest": Some{CatalogFireworks.model_accounts_fireworks_routers_kimi_fast_latest()}
    case "fireworks/accounts/fireworks/routers/kimi-k3-fast": Some{CatalogFireworks.model_accounts_fireworks_routers_kimi_k3_fast()}
    case "fireworks/accounts/fireworks/routers/kimi-latest": Some{CatalogFireworks.model_accounts_fireworks_routers_kimi_latest()}
    case "fireworks/accounts/fireworks/routers/minimax-latest": Some{CatalogFireworks.model_accounts_fireworks_routers_minimax_latest()}
    case "fireworks/accounts/fireworks/routers/qwen-max-latest": Some{CatalogFireworks.model_accounts_fireworks_routers_qwen_max_latest()}
    case "github-copilot/claude-haiku-4.5": Some{CatalogGithubCopilot.model_claude_haiku_4_5()}
    case "github-copilot/claude-sonnet-4.6": Some{CatalogGithubCopilot.model_claude_sonnet_4_6()}
    case "github-copilot/gemini-3.5-flash": Some{CatalogGithubCopilot.model_gemini_3_5_flash()}
    case "github-copilot/gpt-5-mini": Some{CatalogGithubCopilot.model_gpt_5_mini()}
    case "github-copilot/gpt-5.3-codex": Some{CatalogGithubCopilot.model_gpt_5_3_codex()}
    case "github-copilot/gpt-5.5": Some{CatalogGithubCopilot.model_gpt_5_5()}
    case "google/gemini-2.5-flash": Some{CatalogGoogle.model_gemini_2_5_flash()}
    case "google/gemini-3-flash-preview": Some{CatalogGoogle.model_gemini_3_flash_preview()}
    case "google/gemini-3.1-pro-preview": Some{CatalogGoogle.model_gemini_3_1_pro_preview()}
    case "groq/llama-3.3-70b-versatile": Some{CatalogGroq.model_llama_3_3_70b_versatile()}
    case "groq/openai/gpt-oss-120b": Some{CatalogGroq.model_openai_gpt_oss_120b()}
    case "groq/openai/gpt-oss-20b": Some{CatalogGroq.model_openai_gpt_oss_20b()}
    case "huggingface/moonshotai/Kimi-K2.5": Some{CatalogHuggingface.model_moonshotai_Kimi_K2_5()}
    case "kimi-coding/kimi-for-coding": Some{CatalogKimiCoding.model_kimi_for_coding()}
    case "meta/muse-spark-1.3": Some{CatalogMeta.model_muse_spark_1_3()}
    case "minimax/MiniMax-M2.7": Some{CatalogMinimax.model_MiniMax_M2_7()}
    case "minimax-cn/MiniMax-M2.7": Some{CatalogMinimaxCn.model_MiniMax_M2_7()}
    case "nvidia/nvidia/nemotron-3-super-120b-a12b": Some{CatalogNvidia.model_nvidia_nemotron_3_super_120b_a12b()}
    case "openai/gpt-4o": Some{CatalogOpenai.model_gpt_4o()}
    case "openai/gpt-4o-mini": Some{CatalogOpenai.model_gpt_4o_mini()}
    case "openai/gpt-5": Some{CatalogOpenai.model_gpt_5()}
    case "openai/gpt-5-mini": Some{CatalogOpenai.model_gpt_5_mini()}
    case "openai/gpt-5-nano": Some{CatalogOpenai.model_gpt_5_nano()}
    case "openai/gpt-5-pro": Some{CatalogOpenai.model_gpt_5_pro()}
    case "openai/gpt-5.1": Some{CatalogOpenai.model_gpt_5_1()}
    case "openai/gpt-5.2": Some{CatalogOpenai.model_gpt_5_2()}
    case "openai/gpt-5.2-pro": Some{CatalogOpenai.model_gpt_5_2_pro()}
    case "openai/gpt-5.3-codex": Some{CatalogOpenai.model_gpt_5_3_codex()}
    case "openai/gpt-5.4": Some{CatalogOpenai.model_gpt_5_4()}
    case "openai/gpt-5.4-mini": Some{CatalogOpenai.model_gpt_5_4_mini()}
    case "openai/gpt-5.4-nano": Some{CatalogOpenai.model_gpt_5_4_nano()}
    case "openai/gpt-5.4-pro": Some{CatalogOpenai.model_gpt_5_4_pro()}
    case "openai/gpt-5.5": Some{CatalogOpenai.model_gpt_5_5()}
    case "openai/gpt-5.5-pro": Some{CatalogOpenai.model_gpt_5_5_pro()}
    case "openai/gpt-5.6-luna": Some{CatalogOpenai.model_gpt_5_6_luna()}
    case "openai/gpt-5.6-sol": Some{CatalogOpenai.model_gpt_5_6_sol()}
    case "openai/gpt-5.6-terra": Some{CatalogOpenai.model_gpt_5_6_terra()}
    case "openai/gpt-6-luna": Some{CatalogOpenai.model_gpt_6_luna()}
    case "openai/gpt-6-sol": Some{CatalogOpenai.model_gpt_6_sol()}
    case "openai-codex/gpt-5.5": Some{CatalogOpenaiCodex.model_gpt_5_5()}
    case "opencode/big-pickle": Some{CatalogOpencode.model_big_pickle()}
    case "opencode/claude-fable-5": Some{CatalogOpencode.model_claude_fable_5()}
    case "opencode/claude-fable-5-1": Some{CatalogOpencode.model_claude_fable_5_1()}
    case "opencode/claude-haiku-4-5": Some{CatalogOpencode.model_claude_haiku_4_5()}
    case "opencode/claude-opus-4-5": Some{CatalogOpencode.model_claude_opus_4_5()}
    case "opencode/claude-opus-4-6": Some{CatalogOpencode.model_claude_opus_4_6()}
    case "opencode/claude-opus-4-7": Some{CatalogOpencode.model_claude_opus_4_7()}
    case "opencode/claude-opus-4-8": Some{CatalogOpencode.model_claude_opus_4_8()}
    case "opencode/claude-opus-5": Some{CatalogOpencode.model_claude_opus_5()}
    case "opencode/claude-opus-5-5": Some{CatalogOpencode.model_claude_opus_5_5()}
    case "opencode/claude-sonnet-4": Some{CatalogOpencode.model_claude_sonnet_4()}
    case "opencode/claude-sonnet-4-5": Some{CatalogOpencode.model_claude_sonnet_4_5()}
    case "opencode/claude-sonnet-4-6": Some{CatalogOpencode.model_claude_sonnet_4_6()}
    case "opencode/claude-sonnet-5": Some{CatalogOpencode.model_claude_sonnet_5()}
    case "opencode/deepseek-v4-flash": Some{CatalogOpencode.model_deepseek_v4_flash()}
    case "opencode/deepseek-v4-flash-vision-exp": Some{CatalogOpencode.model_deepseek_v4_flash_vision_exp()}
    case "opencode/deepseek-v4-pro": Some{CatalogOpencode.model_deepseek_v4_pro()}
    case "opencode/deepseek-v4.1-flash": Some{CatalogOpencode.model_deepseek_v4_1_flash()}
    case "opencode/gemini-3-flash": Some{CatalogOpencode.model_gemini_3_flash()}
    case "opencode/gemini-3.1-pro": Some{CatalogOpencode.model_gemini_3_1_pro()}
    case "opencode/gemini-3.5-flash": Some{CatalogOpencode.model_gemini_3_5_flash()}
    case "opencode/gemini-3.5-flash-lite": Some{CatalogOpencode.model_gemini_3_5_flash_lite()}
    case "opencode/gemini-3.6-flash": Some{CatalogOpencode.model_gemini_3_6_flash()}
    case "opencode/gemini-3.7-flash": Some{CatalogOpencode.model_gemini_3_7_flash()}
    case "opencode/gemini-3.8-flash": Some{CatalogOpencode.model_gemini_3_8_flash()}
    case "opencode/glm-5": Some{CatalogOpencode.model_glm_5()}
    case "opencode/glm-5.1": Some{CatalogOpencode.model_glm_5_1()}
    case "opencode/glm-5.2": Some{CatalogOpencode.model_glm_5_2()}
    case "opencode/glm-5.3": Some{CatalogOpencode.model_glm_5_3()}
    case "opencode/glm-5.3-flash": Some{CatalogOpencode.model_glm_5_3_flash()}
    case "opencode/gpt-5": Some{CatalogOpencode.model_gpt_5()}
    case "opencode/gpt-5-codex": Some{CatalogOpencode.model_gpt_5_codex()}
    case "opencode/gpt-5-nano": Some{CatalogOpencode.model_gpt_5_nano()}
    case "opencode/gpt-5.1": Some{CatalogOpencode.model_gpt_5_1()}
    case "opencode/gpt-5.1-codex": Some{CatalogOpencode.model_gpt_5_1_codex()}
    case "opencode/gpt-5.1-codex-max": Some{CatalogOpencode.model_gpt_5_1_codex_max()}
    case "opencode/gpt-5.1-codex-mini": Some{CatalogOpencode.model_gpt_5_1_codex_mini()}
    case "opencode/gpt-5.2": Some{CatalogOpencode.model_gpt_5_2()}
    case "opencode/gpt-5.2-codex": Some{CatalogOpencode.model_gpt_5_2_codex()}
    case "opencode/gpt-5.3-codex": Some{CatalogOpencode.model_gpt_5_3_codex()}
    case "opencode/gpt-5.4": Some{CatalogOpencode.model_gpt_5_4()}
    case "opencode/gpt-5.4-mini": Some{CatalogOpencode.model_gpt_5_4_mini()}
    case "opencode/gpt-5.4-nano": Some{CatalogOpencode.model_gpt_5_4_nano()}
    case "opencode/gpt-5.4-pro": Some{CatalogOpencode.model_gpt_5_4_pro()}
    case "opencode/gpt-5.5": Some{CatalogOpencode.model_gpt_5_5()}
    case "opencode/gpt-5.5-pro": Some{CatalogOpencode.model_gpt_5_5_pro()}
    case "opencode/gpt-5.6-luna": Some{CatalogOpencode.model_gpt_5_6_luna()}
    case "opencode/gpt-5.6-sol": Some{CatalogOpencode.model_gpt_5_6_sol()}
    case "opencode/gpt-5.6-terra": Some{CatalogOpencode.model_gpt_5_6_terra()}
    case "opencode/gpt-6-astra": Some{CatalogOpencode.model_gpt_6_astra()}
    case "opencode/gpt-6-luna": Some{CatalogOpencode.model_gpt_6_luna()}
    case "opencode/gpt-6-sol": Some{CatalogOpencode.model_gpt_6_sol()}
    case "opencode/grok-4.5": Some{CatalogOpencode.model_grok_4_5()}
    case "opencode/grok-4.6": Some{CatalogOpencode.model_grok_4_6()}
    case "opencode/grok-build-0.1": Some{CatalogOpencode.model_grok_build_0_1()}
    case "opencode/kimi-k2.5": Some{CatalogOpencode.model_kimi_k2_5()}
    case "opencode/kimi-k2.6": Some{CatalogOpencode.model_kimi_k2_6()}
    case "opencode/kimi-k2.7-code": Some{CatalogOpencode.model_kimi_k2_7_code()}
    case "opencode/kimi-k3": Some{CatalogOpencode.model_kimi_k3()}
    case "opencode/ling-3.0-flash-fin-free": Some{CatalogOpencode.model_ling_3_0_flash_fin_free()}
    case "opencode/mimo-v2.6-flash-free": Some{CatalogOpencode.model_mimo_v2_6_flash_free()}
    case "opencode/minimax-m2.5": Some{CatalogOpencode.model_minimax_m2_5()}
    case "opencode/minimax-m2.7": Some{CatalogOpencode.model_minimax_m2_7()}
    case "opencode/minimax-m3": Some{CatalogOpencode.model_minimax_m3()}
    case "opencode/muse-spark-1.2": Some{CatalogOpencode.model_muse_spark_1_2()}
    case "opencode/muse-spark-1.2-contributor-free": Some{CatalogOpencode.model_muse_spark_1_2_contributor_free()}
    case "opencode/muse-spark-1.3": Some{CatalogOpencode.model_muse_spark_1_3()}
    case "opencode/muse-spark-1.3-contributor-free": Some{CatalogOpencode.model_muse_spark_1_3_contributor_free()}
    case "opencode/nemotron-3-ultra-free": Some{CatalogOpencode.model_nemotron_3_ultra_free()}
    case "opencode/nemotron-3.5-lightning-free": Some{CatalogOpencode.model_nemotron_3_5_lightning_free()}
    case "opencode/qwen3.5-plus": Some{CatalogOpencode.model_qwen3_5_plus()}
    case "opencode/qwen3.6-plus": Some{CatalogOpencode.model_qwen3_6_plus()}
    case "opencode/qwen3.8-flash": Some{CatalogOpencode.model_qwen3_8_flash()}
    case "opencode-go/deepseek-v4-flash": Some{CatalogOpencodeGo.model_deepseek_v4_flash()}
    case "opencode-go/deepseek-v4-flash-vision-exp": Some{CatalogOpencodeGo.model_deepseek_v4_flash_vision_exp()}
    case "opencode-go/deepseek-v4-pro": Some{CatalogOpencodeGo.model_deepseek_v4_pro()}
    case "opencode-go/deepseek-v4.1-flash": Some{CatalogOpencodeGo.model_deepseek_v4_1_flash()}
    case "opencode-go/glm-5.1": Some{CatalogOpencodeGo.model_glm_5_1()}
    case "opencode-go/glm-5.2": Some{CatalogOpencodeGo.model_glm_5_2()}
    case "opencode-go/glm-5.3": Some{CatalogOpencodeGo.model_glm_5_3()}
    case "opencode-go/glm-5.3-flash": Some{CatalogOpencodeGo.model_glm_5_3_flash()}
    case "opencode-go/gpt-5.6-luna": Some{CatalogOpencodeGo.model_gpt_5_6_luna()}
    case "opencode-go/grok-4.6": Some{CatalogOpencodeGo.model_grok_4_6()}
    case "opencode-go/grok-4.7": Some{CatalogOpencodeGo.model_grok_4_7()}
    case "opencode-go/hy3": Some{CatalogOpencodeGo.model_hy3()}
    case "opencode-go/hy4-preview": Some{CatalogOpencodeGo.model_hy4_preview()}
    case "opencode-go/kimi-k2.6": Some{CatalogOpencodeGo.model_kimi_k2_6()}
    case "opencode-go/kimi-k2.7-code": Some{CatalogOpencodeGo.model_kimi_k2_7_code()}
    case "opencode-go/kimi-k3": Some{CatalogOpencodeGo.model_kimi_k3()}
    case "opencode-go/longcat-2.0": Some{CatalogOpencodeGo.model_longcat_2_0()}
    case "opencode-go/mimo-v2.5": Some{CatalogOpencodeGo.model_mimo_v2_5()}
    case "opencode-go/mimo-v2.5-pro": Some{CatalogOpencodeGo.model_mimo_v2_5_pro()}
    case "opencode-go/mimo-v2.6-flash": Some{CatalogOpencodeGo.model_mimo_v2_6_flash()}
    case "opencode-go/mimo-v2.6-pro": Some{CatalogOpencodeGo.model_mimo_v2_6_pro()}
    case "opencode-go/minimax-m2.7": Some{CatalogOpencodeGo.model_minimax_m2_7()}
    case "opencode-go/minimax-m3": Some{CatalogOpencodeGo.model_minimax_m3()}
    case "opencode-go/muse-spark-1.2-contributor": Some{CatalogOpencodeGo.model_muse_spark_1_2_contributor()}
    case "opencode-go/muse-spark-1.3-contributor": Some{CatalogOpencodeGo.model_muse_spark_1_3_contributor()}
    case "opencode-go/qwen3.6-plus": Some{CatalogOpencodeGo.model_qwen3_6_plus()}
    case "opencode-go/qwen3.7-max": Some{CatalogOpencodeGo.model_qwen3_7_max()}
    case "opencode-go/qwen3.7-plus": Some{CatalogOpencodeGo.model_qwen3_7_plus()}
    case "opencode-go/qwen3.8-flash": Some{CatalogOpencodeGo.model_qwen3_8_flash()}
    case "opencode-go/qwen3.8-max": Some{CatalogOpencodeGo.model_qwen3_8_max()}
    case "openrouter/anthropic/claude-sonnet-4": Some{CatalogOpenrouter.model_anthropic_claude_sonnet_4()}
    case "openrouter/deepseek/deepseek-chat": Some{CatalogOpenrouter.model_deepseek_deepseek_chat()}
    case "openrouter/deepseek/deepseek-v3.2": Some{CatalogOpenrouter.model_deepseek_deepseek_v3_2()}
    case "openrouter/google/gemini-2.5-flash": Some{CatalogOpenrouter.model_google_gemini_2_5_flash()}
    case "openrouter/meta-llama/llama-4-scout": Some{CatalogOpenrouter.model_meta_llama_llama_4_scout()}
    case "openrouter/mistralai/mistral-large": Some{CatalogOpenrouter.model_mistralai_mistral_large()}
    case "openrouter/mistralai/mistral-small-3.2-24b-instruct": Some{CatalogOpenrouter.model_mistralai_mistral_small_3_2_24b_instruct()}
    case "openrouter/openai/gpt-5.5": Some{CatalogOpenrouter.model_openai_gpt_5_5()}
    case "openrouter/qwen/qwen3.5-plus-02-15": Some{CatalogOpenrouter.model_qwen_qwen3_5_plus_02_15()}
    case "openrouter/z-ai/glm-4.5v": Some{CatalogOpenrouter.model_z_ai_glm_4_5v()}
    case "qwen-token-plan/MiniMax-M2.5": Some{CatalogQwenTokenPlan.model_MiniMax_M2_5()}
    case "qwen-token-plan/deepseek-v3.2": Some{CatalogQwenTokenPlan.model_deepseek_v3_2()}
    case "qwen-token-plan/deepseek-v4-flash": Some{CatalogQwenTokenPlan.model_deepseek_v4_flash()}
    case "qwen-token-plan/deepseek-v4-flash-0731": Some{CatalogQwenTokenPlan.model_deepseek_v4_flash_0731()}
    case "qwen-token-plan/deepseek-v4-pro": Some{CatalogQwenTokenPlan.model_deepseek_v4_pro()}
    case "qwen-token-plan/deepseek-v4-pro-0813": Some{CatalogQwenTokenPlan.model_deepseek_v4_pro_0813()}
    case "qwen-token-plan/deepseek-v4.1-flash": Some{CatalogQwenTokenPlan.model_deepseek_v4_1_flash()}
    case "qwen-token-plan/glm-5": Some{CatalogQwenTokenPlan.model_glm_5()}
    case "qwen-token-plan/glm-5.1": Some{CatalogQwenTokenPlan.model_glm_5_1()}
    case "qwen-token-plan/glm-5.2": Some{CatalogQwenTokenPlan.model_glm_5_2()}
    case "qwen-token-plan/glm-5.3": Some{CatalogQwenTokenPlan.model_glm_5_3()}
    case "qwen-token-plan/kimi-k2.5": Some{CatalogQwenTokenPlan.model_kimi_k2_5()}
    case "qwen-token-plan/kimi-k2.6": Some{CatalogQwenTokenPlan.model_kimi_k2_6()}
    case "qwen-token-plan/kimi-k2.7-code": Some{CatalogQwenTokenPlan.model_kimi_k2_7_code()}
    case "qwen-token-plan/qwen3.6-flash": Some{CatalogQwenTokenPlan.model_qwen3_6_flash()}
    case "qwen-token-plan/qwen3.6-plus": Some{CatalogQwenTokenPlan.model_qwen3_6_plus()}
    case "qwen-token-plan/qwen3.7-max": Some{CatalogQwenTokenPlan.model_qwen3_7_max()}
    case "qwen-token-plan/qwen3.7-plus": Some{CatalogQwenTokenPlan.model_qwen3_7_plus()}
    case "qwen-token-plan/qwen3.8-flash": Some{CatalogQwenTokenPlan.model_qwen3_8_flash()}
    case "qwen-token-plan/qwen3.8-max": Some{CatalogQwenTokenPlan.model_qwen3_8_max()}
    case "qwen-token-plan-cn/MiniMax-M2.5": Some{CatalogQwenTokenPlanCn.model_MiniMax_M2_5()}
    case "qwen-token-plan-cn/deepseek-v3.2": Some{CatalogQwenTokenPlanCn.model_deepseek_v3_2()}
    case "qwen-token-plan-cn/deepseek-v4-flash": Some{CatalogQwenTokenPlanCn.model_deepseek_v4_flash()}
    case "qwen-token-plan-cn/deepseek-v4-flash-0731": Some{CatalogQwenTokenPlanCn.model_deepseek_v4_flash_0731()}
    case "qwen-token-plan-cn/deepseek-v4-pro": Some{CatalogQwenTokenPlanCn.model_deepseek_v4_pro()}
    case "qwen-token-plan-cn/deepseek-v4-pro-0813": Some{CatalogQwenTokenPlanCn.model_deepseek_v4_pro_0813()}
    case "qwen-token-plan-cn/deepseek-v4.1-flash": Some{CatalogQwenTokenPlanCn.model_deepseek_v4_1_flash()}
    case "qwen-token-plan-cn/glm-5": Some{CatalogQwenTokenPlanCn.model_glm_5()}
    case "qwen-token-plan-cn/glm-5.1": Some{CatalogQwenTokenPlanCn.model_glm_5_1()}
    case "qwen-token-plan-cn/glm-5.2": Some{CatalogQwenTokenPlanCn.model_glm_5_2()}
    case "qwen-token-plan-cn/glm-5.3": Some{CatalogQwenTokenPlanCn.model_glm_5_3()}
    case "qwen-token-plan-cn/kimi-k2.5": Some{CatalogQwenTokenPlanCn.model_kimi_k2_5()}
    case "qwen-token-plan-cn/kimi-k2.6": Some{CatalogQwenTokenPlanCn.model_kimi_k2_6()}
    case "qwen-token-plan-cn/kimi-k2.7-code": Some{CatalogQwenTokenPlanCn.model_kimi_k2_7_code()}
    case "qwen-token-plan-cn/qwen3.6-flash": Some{CatalogQwenTokenPlanCn.model_qwen3_6_flash()}
    case "qwen-token-plan-cn/qwen3.6-plus": Some{CatalogQwenTokenPlanCn.model_qwen3_6_plus()}
    case "qwen-token-plan-cn/qwen3.7-max": Some{CatalogQwenTokenPlanCn.model_qwen3_7_max()}
    case "qwen-token-plan-cn/qwen3.7-plus": Some{CatalogQwenTokenPlanCn.model_qwen3_7_plus()}
    case "qwen-token-plan-cn/qwen3.8-flash": Some{CatalogQwenTokenPlanCn.model_qwen3_8_flash()}
    case "qwen-token-plan-cn/qwen3.8-max": Some{CatalogQwenTokenPlanCn.model_qwen3_8_max()}
    case "qwen-token-plan-individual/deepseek-v4-flash-0731": Some{CatalogQwenTokenPlanIndividual.model_deepseek_v4_flash_0731()}
    case "qwen-token-plan-individual/deepseek-v4-pro": Some{CatalogQwenTokenPlanIndividual.model_deepseek_v4_pro()}
    case "qwen-token-plan-individual/deepseek-v4-pro-0813": Some{CatalogQwenTokenPlanIndividual.model_deepseek_v4_pro_0813()}
    case "qwen-token-plan-individual/glm-5.2": Some{CatalogQwenTokenPlanIndividual.model_glm_5_2()}
    case "qwen-token-plan-individual/qwen3.6-flash": Some{CatalogQwenTokenPlanIndividual.model_qwen3_6_flash()}
    case "qwen-token-plan-individual/qwen3.7-max": Some{CatalogQwenTokenPlanIndividual.model_qwen3_7_max()}
    case "qwen-token-plan-individual/qwen3.7-plus": Some{CatalogQwenTokenPlanIndividual.model_qwen3_7_plus()}
    case "qwen-token-plan-individual/qwen3.8-flash": Some{CatalogQwenTokenPlanIndividual.model_qwen3_8_flash()}
    case "qwen-token-plan-individual/qwen3.8-max": Some{CatalogQwenTokenPlanIndividual.model_qwen3_8_max()}
    case "together/moonshotai/Kimi-K2.6": Some{CatalogTogether.model_moonshotai_Kimi_K2_6()}
    case "vercel-ai-gateway/anthropic/claude-opus-4.5": Some{CatalogVercelAiGateway.model_anthropic_claude_opus_4_5()}
    case "vercel-ai-gateway/google/gemini-2.5-flash": Some{CatalogVercelAiGateway.model_google_gemini_2_5_flash()}
    case "vercel-ai-gateway/openai/gpt-5.1-codex-max": Some{CatalogVercelAiGateway.model_openai_gpt_5_1_codex_max()}
    case "xai/grok-4.3": Some{CatalogXai.model_grok_4_3()}
    case "xai/grok-4.5": Some{CatalogXai.model_grok_4_5()}
    case "xai/grok-4.6": Some{CatalogXai.model_grok_4_6()}
    case "xai/grok-4.7": Some{CatalogXai.model_grok_4_7()}
    case "xiaomi/mimo-v2.5-pro": Some{CatalogXiaomi.model_mimo_v2_5_pro()}
    case "xiaomi-token-plan-ams/mimo-v2.5-pro": Some{CatalogXiaomiTokenPlanAms.model_mimo_v2_5_pro()}
    case "xiaomi-token-plan-cn/mimo-v2.5-pro": Some{CatalogXiaomiTokenPlanCn.model_mimo_v2_5_pro()}
    case "xiaomi-token-plan-sgp/mimo-v2.5-pro": Some{CatalogXiaomiTokenPlanSgp.model_mimo_v2_5_pro()}
    case "zai/glm-5.2": Some{CatalogZai.model_glm_5_2()}
    case _: None{}

def apiNamed(name: Maybe<&2, String>) -> Maybe<&2, Ai.ModelApi>:
  match name:
    case Some{"openai-completions"}: Some{Ai.OpenAICompletionsApi{}}
    case Some{"openai-responses"}: Some{Ai.OpenAIResponsesApi{}}
    case _: None{}

# The suites' `{ compat: _compat, ...baseModel, api }` override.
def withApi(model: Model(), api: Maybe<&2, Ai.ModelApi>) -> Model():
  match model api:
    case _ None{}: model
    case Ai.Model{id, name, _, provider, url, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, _} Some{replaced}:
      Ai.Model{id, name, replaced, provider, url, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, None{}}

def withBaseUrl(model: Model(), +url: String) -> Model():
  match model:
    case Ai.Model{id, name, api, provider, _, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}:
      Ai.Model{id, name, api, provider, url, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}

def apiOf(model: Model()) -> Ai.ModelApi:
  match model:
    case Ai.Model{_, _, api, _, _, _, _, _, _, _, _, _, _, _, _, _}: api

def windowOf(model: Model()) -> F64:
  match model:
    case Ai.Model{_, _, _, _, _, _, _, _, _, _, _, window, _, _, _, _}: window

# context-overflow.test.ts
# ------------------------
def LOREM_IPSUM() -> String: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. "

def repeated(+text: String, count: Nat, done: String) -> String:
  match count:
    case 0n: done
    case 1n+rest: repeated(text, rest, text ++ done)

def natOf(value: F64) -> Nat: U32.to_nat(F64.to_u32(F64.floor(value)))

# generateOverflowContent: (contextWindow + 10000) tokens at 4 * 1.5
# characters each, in whole repetitions of the paragraph.
def generateOverflowContent(contextWindow: F64) -> String:
  +length = Utf16.length(LOREM_IPSUM())
  +targetChars = (natOf(contextWindow) + 10000n) * 6n
  repeated(LOREM_IPSUM(), Nat.div(targetChars + Nat.sub(length, 1n), length), "")

def overflowContext(model: Model()) -> Context():
  Transcript.normalizeContext(V.Value, V.Value, Unit, Details(), Ai.Context{Some{"You are a helpful assistant."}, Ai.User{Ai.UserMessage{Ai.UserText{generateOverflowContent(windowOf(model))}, F.fromU32(1)}} <> Nil{}, None{}})

# Options
# -------
def levelOf(value: Maybe<&2, String>) -> Maybe<&2, Ai.ThinkingLevel>:
  match value:
    case Some{"minimal"}: Some{Ai.Minimal{}}
    case Some{"low"}: Some{Ai.Low{}}
    case Some{"medium"}: Some{Ai.Medium{}}
    case Some{"high"}: Some{Ai.High{}}
    case Some{"xhigh"}: Some{Ai.XHigh{}}
    case Some{"max"}: Some{Ai.Max{}}
    case _: None{}

def transportOf(value: Maybe<&2, String>) -> Maybe<&2, Ai.Transport>:
  match value:
    case Some{"sse"}: Some{Ai.Sse{}}
    case Some{"websocket"}: Some{Ai.WebSocket{}}
    case Some{"auto"}: Some{Ai.AutoTransport{}}
    case _: None{}

def nullableText(value: V.Value) -> Ai.Nullable<String>:
  match value:
    case V.Text{item}: Ai.PresentValue{item}
    case _: Ai.NullValue{}

def headerProperties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<Ai.Nullable<String>>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, nullableText(value)} <> headerProperties(rest)

def headersOf(value: Maybe<&2, V.Value>) -> Maybe<&2, Ai.ProviderHeaders()>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{R.Record{headerProperties(values)}}
    case _: None{}

def retentionOf(value: Maybe<&2, String>) -> Maybe<&2, Ai.CacheRetention>:
  match value:
    case Some{"none"}: Some{Ai.CacheNone{}}
    case Some{"short"}: Some{Ai.CacheShort{}}
    case Some{"long"}: Some{Ai.CacheLong{}}
    case _: None{}

def tierOf(value: Maybe<&2, String>) -> Maybe<&2, Ai.Nullable<Responses.ServiceTier>>:
  match value:
    case Some{"auto"}: Some{Ai.PresentValue{Responses.TierAuto{}}}
    case Some{"default"}: Some{Ai.PresentValue{Responses.TierDefault{}}}
    case Some{"flex"}: Some{Ai.PresentValue{Responses.TierFlex{}}}
    case Some{"scale"}: Some{Ai.PresentValue{Responses.TierScale{}}}
    case Some{"priority"}: Some{Ai.PresentValue{Responses.TierPriority{}}}
    case _: None{}

def baseOptions(+options: V.Value, signal: Abort.AbortSignal<Unit>, fetch: Fetch.Fetch(Unit)) -> Base():
  Ai.StreamOptions{Some{signal}, None{}, text(field(options, "apiKey")), Some{fetch}, None{}, None{}, None{}, headersOf(field(options, "headers")), None{}, None{}, None{}, number(field(options, "temperature")), None{}, number(field(options, "maxTokens")), transportOf(text(field(options, "transport"))), retentionOf(text(field(options, "cacheRetention"))), text(field(options, "sessionId")), None{}, None{}}

def simpleOptions(+options: V.Value, signal: Abort.AbortSignal<Unit>, fetch: Fetch.Fetch(Unit)) -> Simple():
  Ai.SimpleStreamOptions{Some{signal}, None{}, text(field(options, "apiKey")), Some{fetch}, None{}, None{}, None{}, headersOf(field(options, "headers")), None{}, None{}, None{}, number(field(options, "temperature")), None{}, number(field(options, "maxTokens")), transportOf(text(field(options, "transport"))), retentionOf(text(field(options, "cacheRetention"))), text(field(options, "sessionId")), None{}, None{}, None{}, levelOf(text(field(options, "reasoning"))), None{}, None{}}

def googleThinking(value: Maybe<&2, V.Value>) -> Maybe<&2, Gemini.GoogleThinking>:
  match value:
    case Some{+thinking}: Some{Gemini.GoogleThinking{Maybe.default(&2, Bool, flag(field(thinking, "enabled")), False{}), number(field(thinking, "budgetTokens")), None{}}}
    case None{}: None{}

def responsesOptions(+options: V.Value, signal: Abort.AbortSignal<Unit>, fetch: Fetch.Fetch(Unit)) -> Responses.OpenAIResponsesOptions<Unit, Unit, Error()>:
  Responses.OpenAIResponsesOptions{Some{signal}, None{}, text(field(options, "apiKey")), Some{fetch}, None{}, None{}, None{}, headersOf(field(options, "headers")), None{}, None{}, None{}, number(field(options, "temperature")), None{}, number(field(options, "maxTokens")), transportOf(text(field(options, "transport"))), retentionOf(text(field(options, "cacheRetention"))), text(field(options, "sessionId")), None{}, None{}, levelOf(text(field(options, "reasoningEffort"))), None{}, tierOf(text(field(options, "serviceTier"))), Maybe.map(&2, V.Value, J(), Convert.toJson, field(options, "toolChoice"))}

# Opening the stream
# ------------------
def render(error: Error()) -> String: Tools.errorMessage(error)

def failure(cause: Responses.Error<Unit, Error()>) -> Error():
  Tools.Failure{Responses.describe(~Unit, ~Error(), ~render, "openai", cause)}

def selected(-Options: Data, value: Options) -> Options: value

# The Responses configuration with the process user agent, as the agent runtime builds it.
def withAgent(agent: String, config: Responses.Config) -> Responses.Config:
  match config:
    case Responses.Config{url, OpenAIClient.Defaults{_, a, b, c}, files, transport, security, limit, synthesize}: Responses.Config{url, OpenAIClient.Defaults{agent, a, b, c}, files, transport, security, limit, synthesize}

def configFor(agent: String) -> Responses.Config: withAgent(agent, RP.config())

# upstream stream(): the provider's own options.
def opened(+agent: String, +fetch: Fetch.Fetch(Unit), counter: Ref.Ref<Nat>, api: Ai.ModelApi, +model: Model(), +context: Context(), +options: V.Value, signal: Abort.AbortSignal<Unit>) -> IO(Output()):
  match api:
    case Ai.AnthropicMessagesApi{}: Anthropic.openStream(fetch, TestClient.urlContext(), model, context, Messages.AnthropicOptions{baseOptions(options, signal, fetch), flag(field(options, "thinkingEnabled")), number(field(options, "thinkingBudgetTokens")), text(field(options, "effort")), None{}, None{}, None{}, None{}})
    case Ai.GoogleGenerativeAiApi{}: Google.openStream(fetch, TestClient.urlContext(), counter, model, context, Gemini.GoogleOptions{baseOptions(options, signal, fetch), None{}, googleThinking(field(options, "thinking"))})
    case Ai.OpenAICompletionsApi{}: Completions.openStream(fetch, TestClient.urlContext(), model, context, Chat.OpenAICompletionsOptions{baseOptions(options, signal, fetch), None{}, levelOf(text(field(options, "reasoningEffort"))), None{}})
    case Ai.AzureOpenAIResponsesApi{}:
      do IO<Output()>:
        owner : Responses.Run<Unit, Unit, Error()> <- Azure.stream(~Unit, ~Unit, ~Unit, ~Details(), ~Error(), ~render, configFor(agent), model, context, Azure.AzureOpenAIResponsesOptions{baseOptions(options, signal, fetch), levelOf(text(field(options, "reasoningEffort"))), None{}, None{}, None{}, None{}, None{}, None{}})
        return Providers.lease(~Unit, ~Error(), ~failure, Responses.borrow(Unit, Unit, Error(), owner))
    case Ai.OpenAICodexResponsesApi{}:
      do IO<Output()>:
        owner : Responses.Run<Unit, Unit, Error()> <- Codex.stream(~Unit, ~Unit, ~Unit, ~Details(), ~Error(), ~render, configFor(agent), model, context, responsesOptions(options, signal, fetch))
        return Providers.lease(~Unit, ~Error(), ~failure, Responses.borrow(Unit, Unit, Error(), owner))
    case _:
      do IO<Output()>:
        owner : Responses.Run<Unit, Unit, Error()> <- Responses.stream(~Unit, ~Unit, ~Unit, ~Details(), ~Error(), ~render, configFor(agent), model, context, responsesOptions(options, signal, fetch))
        return Providers.lease(~Unit, ~Error(), ~failure, Responses.borrow(Unit, Unit, Error(), owner))

# upstream streamSimple(), as the agent runtime dispatches it.
def openedSimple(+agent: String, +fetch: Fetch.Fetch(Unit), counter: Ref.Ref<Nat>, api: Ai.ModelApi, +model: Model(), +context: Context(), +options: V.Value, signal: Abort.AbortSignal<Unit>) -> IO(Output()):
  match api:
    case Ai.AnthropicMessagesApi{}: Anthropic.open(fetch, TestClient.urlContext(), model, context, Some{simpleOptions(options, signal, fetch)})
    case Ai.GoogleGenerativeAiApi{}: Google.open(fetch, TestClient.urlContext(), counter, model, context, Some{simpleOptions(options, signal, fetch)})
    case Ai.OpenAICompletionsApi{}: Completions.open(fetch, TestClient.urlContext(), model, context, Some{simpleOptions(options, signal, fetch)})
    case _: Providers.openResponses(~Simple(), ~Unit, ~Unit, ~Details(), ~Error(), ~selected(Simple()), ~render, ~failure, configFor(agent), Agent.StreamInput{model, context, Some{simpleOptions(options, signal, fetch)}})

def entered(+agent: String, +entry: String, fetch: Fetch.Fetch(Unit), counter: Ref.Ref<Nat>, +model: Model(), +context: Context(), +options: V.Value, signal: Abort.AbortSignal<Unit>) -> IO(Output()):
  match entry:
    case "simple": openedSimple(agent, fetch, counter, apiOf(model), model, context, options, signal)
    case _: opened(agent, fetch, counter, apiOf(model), model, context, options, signal)

# Draining
# --------
def label(event: StreamEvent()) -> String:
  match event:
    case Ai.Start{_}: "start"
    case Ai.TextStart{_, _}: "text_start"
    case Ai.TextDelta{_, delta, _}: "text_delta:" ++ Text.showText(delta)
    case Ai.TextEnd{_, _, _}: "text_end"
    case Ai.ThinkingStart{_, _}: "thinking_start"
    case Ai.ThinkingDelta{_, delta, _}: "thinking_delta:" ++ Text.showText(delta)
    case Ai.ThinkingEnd{_, _, _}: "thinking_end"
    case Ai.ToolcallStart{_, _}: "toolcall_start"
    case Ai.ToolcallDelta{_, delta, _}: "toolcall_delta:" ++ Text.showText(delta)
    case Ai.ToolcallEnd{_, _, _}: "toolcall_end"
    case Ai.StreamDone{_, _}: "done"
    case Ai.StreamError{_, _}: "error"
    case _: "other"

# Characters (UTF-16 units) of text and thinking deltas.
def deltaUnits(event: StreamEvent()) -> Nat:
  match event:
    case Ai.TextDelta{_, delta, _}: Utf16.length(delta)
    case Ai.ThinkingDelta{_, delta, _}: Utf16.length(delta)
    case _: 0n

def abortWhen(hit: Bool, controller: Abort.AbortController<Unit>) -> IO(Unit):
  match hit:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(Unit, controller, None{})
        return Unit{}

# The suites abort once the streamed text reaches `limit` characters and
# keep reading the stream to its end.
@unsafe def drain(next: Events.Iteration<StreamEvent()>, +cursor: Events.Iterator<StreamEvent(), Message()>, +controller: Abort.AbortController<Unit>, +limit: Maybe<&2, Nat>, +seen: Nat, +fired: Bool) -> IO(Unit):
  match next:
    case Events.Yield{+event}:
      +total = seen + deltaUnits(event)
      +hit = Bool.not(fired) && Maybe.default(&2, Bool, Maybe.map(&2, Nat, Bool, bound => Nat.is_ge(total, bound), limit), False{})
      do IO<Unit>:
        IO.print("E " ++ label(event))
        abortWhen(hit, controller)
        following : Events.Iteration<StreamEvent()> <- Events.nextValue(StreamEvent(), Message(), cursor)
        drain(following, cursor, controller, limit, total, fired || hit)
    case Events.End{}: Events.disposeIterator(StreamEvent(), Message(), cursor)

def unitDetails(value: Unit) -> V.Value: V.Null{}

def jsonText(value: J()) -> String: Maybe.default(&2, String, Wire.stringify(value), "null")

# The context-overflow suite's isContextOverflow(message, contextWindow).
def overflowLine(overflow: Bool, message: Message(), window: F64) -> IO(Unit):
  match overflow:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: IO.print("O " ++ Bool.pick(String, Overflow.isContextOverflow(V.Value, Unit, message, window), "true", "false"))

def observed(result: Output(), +controller: Abort.AbortController<Unit>, limit: Maybe<&2, Nat>, overflow: Bool, window: F64) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("T " ++ render(error))
    case Done{Agent.StreamLease{+events, release}}:
      do IO<Unit>:
        +cursor : Events.Iterator<StreamEvent(), Message()> <- Events.iterator(StreamEvent(), Message(), events)
        first : Events.Iteration<StreamEvent()> <- Events.nextValue(StreamEvent(), Message(), cursor)
        drain(first, cursor, controller, limit, 0n, False{})
        +message : Message() <- Events.resultValue(StreamEvent(), Message(), events)
        released : Result<&2, &2, Error(), Unit> <- release
        IO.print("R " ++ Text.showText(jsonText(Convert.toJson(MessageJson.assistantMessage(~Unit, ~unitDetails, message)))))
        overflowLine(overflow, message, window)

def abortFirst(before: Bool, controller: Abort.AbortController<Unit>) -> IO(Unit): abortWhen(before, controller)

def caseContext(+model: Model(), value: V.Value, overflow: Bool) -> Result<&2, &2, String, Context()>:
  match overflow:
    case True{}: Done{overflowContext(model)}
    case False{}: contextOf(Maybe.default(&2, V.Value, field(value, "context"), V.ObjectValue{R.new(V.Value)}))

def runWith(+agent: String, fetch: Fetch.Fetch(Unit), counter: Ref.Ref<Nat>, +value: V.Value, +model: Model(), context: Result<&2, &2, String, Context()>) -> IO(Unit):
  match context:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{+items}:
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        abortFirst(Maybe.default(&2, Bool, flag(field(value, "abortBefore")), False{}), controller)
        result : Output() <- entered(agent, Maybe.default(&2, String, text(field(value, "entry")), "stream"), fetch, counter, model, items, Maybe.default(&2, V.Value, field(value, "options"), V.ObjectValue{R.new(V.Value)}), Abort.signal(Unit, controller))
        observed(result, controller, Maybe.map(&2, F64, Nat, natOf, number(field(value, "abortAfterChars"))), Maybe.default(&2, Bool, flag(field(value, "overflow")), False{}), windowOf(model))
        Abort.dispose(Unit, controller)

# Case `modelOverride`: {provider?, compat? (replaces the catalog compat, as
# the suites' `{ ...model, compat: {...} }`), compatMerge? (spread over it),
# hostPath? (keeps the catalog base URL's host and path after the run, so
# base-URL substring checks such as "openrouter.ai" still see it)}.
def withProvider(model: Model(), provider: Maybe<&2, String>) -> Model():
  match model provider:
    case _ None{}: model
    case Ai.Model{id, name, api, _, url, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat} Some{replaced}:
      Ai.Model{id, name, api, replaced, url, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}

def withCompat(model: Model(), replaced: Maybe<&2, V.Value>, merged: Maybe<&2, V.Value>) -> Model():
  match model replaced merged:
    case _ None{} None{}: model
    case Ai.Model{id, name, +api, provider, url, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, _} Some{value} _:
      Ai.Model{id, name, api, provider, url, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, Composer.mergedCompat(api, None{}, Some{value})}
    case Ai.Model{id, name, +api, provider, url, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat} None{} Some{value}:
      Ai.Model{id, name, api, provider, url, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, Composer.mergedCompat(api, compat, Some{value})}

def baseUrlOf(model: Model()) -> String:
  match model:
    case Ai.Model{_, _, _, _, url, _, _, _, _, _, _, _, _, _, _, _}: url

def withoutScheme(url: String) -> String:
  match url:
    case SCon{'h', SCon{'t', SCon{'t', SCon{'p', SCon{'s', SCon{':', SCon{'/', SCon{'/', rest}}}}}}}}: rest
    case SCon{'h', SCon{'t', SCon{'t', SCon{'p', SCon{':', SCon{'/', SCon{'/', rest}}}}}}}: rest
    case other: other

def runUrl(+base: String, +run: String, hostPath: Bool, logical: Maybe<&2, String>, model: Model()) -> String:
  base ++ "/" ++ run ++ Bool.pick(String, hostPath, "/" ++ withoutScheme(Maybe.default(&2, String, logical, baseUrlOf(model))), "")

def logicalBaseUrl(override: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match override:
    case Some{+value}: text(field(value, "baseUrl"))
    case None{}: None{}

def overriddenModel(+model: Model(), override: Maybe<&2, V.Value>) -> Model():
  match override:
    case None{}: model
    case Some{+value}: withCompat(withProvider(model, text(field(value, "provider"))), field(value, "compat"), field(value, "compatMerge"))

def hostPathOf(override: Maybe<&2, V.Value>) -> Bool:
  match override:
    case Some{+value}: Maybe.default(&2, Bool, flag(field(value, "hostPath")), False{})
    case None{}: False{}

def withModel(+agent: String, fetch: Fetch.Fetch(Unit), counter: Ref.Ref<Nat>, +base: String, +value: V.Value, model: Maybe<&2, Model()>) -> IO(Unit):
  match model:
    case None{}: IO.die(Unit, 1, "unknown model")
    case Some{found}:
      +shaped = overriddenModel(withApi(found, apiNamed(text(field(value, "api")))), field(value, "modelOverride"))
      +configured = withBaseUrl(shaped, runUrl(base, Maybe.default(&2, String, text(field(value, "run")), "run"), hostPathOf(field(value, "modelOverride")), logicalBaseUrl(field(value, "modelOverride")), shaped))
      runWith(agent, fetch, counter, value, configured, caseContext(configured, value, Maybe.default(&2, Bool, flag(field(value, "overflow")), False{})))

def keyOf(+value: V.Value) -> String:
  Maybe.default(&2, String, text(field(value, "provider")), "") ++ "/" ++ Maybe.default(&2, String, text(field(value, "model")), "")

# Case `catalog: <provider>`: prints each built-in model ("M <json>", code
# points) with its supported thinking levels, for the catalog suites.
def catalogList(+provider: String) -> List<&2, Model()>:
  match provider:
    case "xai": CatalogXai.XAI_MODELS()
    case "baseten": CatalogBaseten.BASETEN_MODELS()
    case "fireworks": CatalogFireworks.FIREWORKS_MODELS()
    case "qwen-token-plan": CatalogQwenTokenPlan.QWEN_TOKEN_PLAN_MODELS()
    case "qwen-token-plan-cn": CatalogQwenTokenPlanCn.QWEN_TOKEN_PLAN_CN_MODELS()
    case "qwen-token-plan-individual": CatalogQwenTokenPlanIndividual.QWEN_TOKEN_PLAN_INDIVIDUAL_MODELS()
    case "opencode": CatalogOpencode.OPENCODE_MODELS()
    case "opencode-go": CatalogOpencodeGo.OPENCODE_GO_MODELS()
    case _: Nil{}

def levelNames(levels: List<&2, Ai.ModelThinkingLevel>) -> List<&2, V.Value>:
  match levels:
    case Nil{}: Nil{}
    case level <> rest: V.Text{ModelJson.thinkingLevel(level)} <> levelNames(rest)

def withLevels(json: V.Value, levels: V.Value) -> V.Value:
  match json:
    case V.ObjectValue{fields}: V.ObjectValue{R.set(V.Value, fields, "supportedThinkingLevels", levels)}
    case other: other

def described(+model: Model()) -> V.Value:
  withLevels(ModelJson.model(model), V.ArrayValue{levelNames(AiModels.getSupportedThinkingLevels(J(), model))})

def printCatalog(models: List<&2, Model()>) -> IO(Unit):
  match models:
    case Nil{}: IO.pure(Unit, Unit{})
    case model <> rest:
      do IO<Unit>:
        IO.print("M " ++ Text.showText(jsonText(Convert.toJson(described(model)))))
        printCatalog(rest)

def builtCustom(result: Result<&2, &2, String, Model()>) -> Maybe<&2, Model()>:
  match result:
    case Done{model}: Some{model}
    case Fail{_}: None{}

# Case `customModel`: a model literal as the suites write it, built the way
# the CLI builds a models.json model definition.
def customModel(value: Maybe<&2, V.Value>) -> Maybe<&2, Model()>:
  match value:
    case None{}: None{}
    case Some{+definition}: builtCustom(Composer.modelFromJson(Maybe.default(&2, String, text(field(definition, "provider")), "custom"), ModelConfig.modelOf(definition), ModelConfig.providerOf(V.ObjectValue{R.new(V.Value)}), None{}))

def chosenModel(custom: Maybe<&2, Model()>, +key: String) -> Maybe<&2, Model()>:
  match custom:
    case Some{model}: Some{model}
    case None{}: catalogModel(key)

def catalogOrCase(fetch: Fetch.Fetch(Unit), +base: String, +value: V.Value, catalog: Maybe<&2, String>) -> IO(Unit):
  match catalog:
    case Some{provider}: printCatalog(catalogList(provider))
    case None{}:
      do IO<Unit>:
        counter : Ref.Ref<Nat> <- Ref.new(Nat, 0n)
        +agent : String <- IO.try(String, UserAgent.get())
        withModel(agent, fetch, counter, base, value, chosenModel(customModel(field(value, "customModel")), keyOf(value)))

def runCase(fetch: Fetch.Fetch(Unit), +base: String, parsed: Result<&2, &2, Decode.ParseError, V.Value>) -> IO(Unit):
  match parsed:
    case Fail{_}: IO.die(Unit, 1, "invalid case")
    case Done{+value}: catalogOrCase(fetch, base, value, text(field(value, "catalog")))

# The strict JSON decoder rejects unpaired surrogate escapes (an approved
# native adaptation of JSON.parse), so the check writes U+E000 where a case
# carries the unpaired high surrogate U+D83D; the executor restores it after
# decoding.
def restoredText(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{57344}, rest}: restoredText(rest, SCon{Chr{55357}, reversed})
    case SCon{char, rest}: restoredText(rest, SCon{char, reversed})

# One self-recursive walk over values, value lists and object fields.
type Walk is Data:
  WValue{value: V.Value}
  WValues{values: List<&2, V.Value>}
  WFields{fields: List<&2, R.Property<V.Value>>}

def walkedValue(walk: Walk) -> V.Value:
  match walk:
    case WValue{value}: value
    case _: V.Null{}

def walkedValues(walk: Walk) -> List<&2, V.Value>:
  match walk:
    case WValues{values}: values
    case _: Nil{}

def walkedFields(walk: Walk) -> List<&2, R.Property<V.Value>>:
  match walk:
    case WFields{fields}: fields
    case _: Nil{}

@unsafe def restoredWalk(walk: Walk) -> Walk:
  match walk:
    case WValue{V.Text{text}}: WValue{V.Text{restoredText(text, "")}}
    case WValue{V.ArrayValue{values}}: WValue{V.ArrayValue{walkedValues(restoredWalk(WValues{values}))}}
    case WValue{V.ObjectValue{R.Record{fields}}}: WValue{V.ObjectValue{R.Record{walkedFields(restoredWalk(WFields{fields}))}}}
    case WValue{other}: WValue{other}
    case WValues{Nil{}}: WValues{Nil{}}
    case WValues{value <> rest}: WValues{walkedValue(restoredWalk(WValue{value})) <> walkedValues(restoredWalk(WValues{rest}))}
    case WFields{Nil{}}: WFields{Nil{}}
    case WFields{R.Property{name, value} <> rest}: WFields{R.Property{name, walkedValue(restoredWalk(WValue{value}))} <> walkedFields(restoredWalk(WFields{rest}))}

def restored(value: V.Value) -> V.Value: walkedValue(restoredWalk(WValue{value}))

def restoredCase(parsed: Result<&2, &2, Decode.ParseError, V.Value>) -> Result<&2, &2, Decode.ParseError, V.Value>:
  match parsed:
    case Done{value}: Done{restored(value)}
    case Fail{error}: Fail{error}

def caseText(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> String:
  match result:
    case Done{bytes}: Utf8.decodeBytes(bytes)
    case Fail{_}: ""

def borrowed(+base: String, +path: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (runtime, +fetch):
      do IO<Unit>:
        read : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
        runCase(fetch, base, restoredCase(Decode.parse(caseText(read))))
        Fetch.retire(Unit, fetch)
        Fetch.dispose(runtime)

def initialized(+base: String, +value: String, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
        borrowed(base, value, pair)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case base <> value <> Nil{}:
      do IO<Unit>:
        runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), TestClient.networkOptions())
        initialized(base, value, runtime)
    case _: IO.die(Unit, 1, "usage: live-replay <base> <case>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

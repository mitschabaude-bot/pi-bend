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
    case "anthropic/claude-opus-4-6": Some{CatalogAnthropic.model_claude_opus_4_6()}
    case "anthropic/claude-sonnet-4-5": Some{CatalogAnthropic.model_claude_sonnet_4_5()}
    case "anthropic/claude-sonnet-4-6": Some{CatalogAnthropic.model_claude_sonnet_4_6()}
    case "azure-openai-responses/gpt-4o-mini": Some{CatalogAzureOpenaiResponses.model_gpt_4o_mini()}
    case "baseten/zai-org/GLM-5.2": Some{CatalogBaseten.model_zai_org_GLM_5_2()}
    case "cerebras/gpt-oss-120b": Some{CatalogCerebras.model_gpt_oss_120b()}
    case "cloudflare-ai-gateway/claude-sonnet-4.5": Some{CatalogCloudflareAiGateway.model_claude_sonnet_4_5()}
    case "cloudflare-ai-gateway/gpt-5.1": Some{CatalogCloudflareAiGateway.model_gpt_5_1()}
    case "cloudflare-ai-gateway/workers-ai/@cf/moonshotai/kimi-k2.6": Some{CatalogCloudflareAiGateway.model_workers_ai__cf_moonshotai_kimi_k2_6()}
    case "cloudflare-workers-ai/@cf/moonshotai/kimi-k2.6": Some{CatalogCloudflareWorkersAi.model__cf_moonshotai_kimi_k2_6()}
    case "deepseek/deepseek-flash": Some{CatalogDeepseek.model_deepseek_flash()}
    case "github-copilot/claude-haiku-4.5": Some{CatalogGithubCopilot.model_claude_haiku_4_5()}
    case "github-copilot/claude-sonnet-4.6": Some{CatalogGithubCopilot.model_claude_sonnet_4_6()}
    case "github-copilot/gemini-3.5-flash": Some{CatalogGithubCopilot.model_gemini_3_5_flash()}
    case "github-copilot/gpt-5-mini": Some{CatalogGithubCopilot.model_gpt_5_mini()}
    case "github-copilot/gpt-5.3-codex": Some{CatalogGithubCopilot.model_gpt_5_3_codex()}
    case "google/gemini-2.5-flash": Some{CatalogGoogle.model_gemini_2_5_flash()}
    case "google/gemini-3-flash-preview": Some{CatalogGoogle.model_gemini_3_flash_preview()}
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
    case "openai/gpt-5-mini": Some{CatalogOpenai.model_gpt_5_mini()}
    case "openai/gpt-5.4": Some{CatalogOpenai.model_gpt_5_4()}
    case "openai/gpt-5.4-mini": Some{CatalogOpenai.model_gpt_5_4_mini()}
    case "openai-codex/gpt-5.5": Some{CatalogOpenaiCodex.model_gpt_5_5()}
    case "opencode/big-pickle": Some{CatalogOpencode.model_big_pickle()}
    case "opencode/claude-sonnet-4-5": Some{CatalogOpencode.model_claude_sonnet_4_5()}
    case "opencode/gemini-3-flash": Some{CatalogOpencode.model_gemini_3_flash()}
    case "opencode/gpt-5.2-codex": Some{CatalogOpencode.model_gpt_5_2_codex()}
    case "openrouter/anthropic/claude-sonnet-4": Some{CatalogOpenrouter.model_anthropic_claude_sonnet_4()}
    case "openrouter/deepseek/deepseek-chat": Some{CatalogOpenrouter.model_deepseek_deepseek_chat()}
    case "openrouter/deepseek/deepseek-v3.2": Some{CatalogOpenrouter.model_deepseek_deepseek_v3_2()}
    case "openrouter/google/gemini-2.5-flash": Some{CatalogOpenrouter.model_google_gemini_2_5_flash()}
    case "openrouter/meta-llama/llama-4-scout": Some{CatalogOpenrouter.model_meta_llama_llama_4_scout()}
    case "openrouter/mistralai/mistral-large": Some{CatalogOpenrouter.model_mistralai_mistral_large()}
    case "openrouter/mistralai/mistral-small-3.2-24b-instruct": Some{CatalogOpenrouter.model_mistralai_mistral_small_3_2_24b_instruct()}
    case "openrouter/z-ai/glm-4.5v": Some{CatalogOpenrouter.model_z_ai_glm_4_5v()}
    case "qwen-token-plan/qwen3.7-max": Some{CatalogQwenTokenPlan.model_qwen3_7_max()}
    case "qwen-token-plan-cn/qwen3.7-max": Some{CatalogQwenTokenPlanCn.model_qwen3_7_max()}
    case "qwen-token-plan-individual/deepseek-v4-flash-0731": Some{CatalogQwenTokenPlanIndividual.model_deepseek_v4_flash_0731()}
    case "qwen-token-plan-individual/glm-5.2": Some{CatalogQwenTokenPlanIndividual.model_glm_5_2()}
    case "qwen-token-plan-individual/qwen3.8-max": Some{CatalogQwenTokenPlanIndividual.model_qwen3_8_max()}
    case "together/moonshotai/Kimi-K2.6": Some{CatalogTogether.model_moonshotai_Kimi_K2_6()}
    case "vercel-ai-gateway/anthropic/claude-opus-4.5": Some{CatalogVercelAiGateway.model_anthropic_claude_opus_4_5()}
    case "vercel-ai-gateway/google/gemini-2.5-flash": Some{CatalogVercelAiGateway.model_google_gemini_2_5_flash()}
    case "vercel-ai-gateway/openai/gpt-5.1-codex-max": Some{CatalogVercelAiGateway.model_openai_gpt_5_1_codex_max()}
    case "xai/grok-4.3": Some{CatalogXai.model_grok_4_3()}
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

def baseOptions(+options: V.Value, signal: Abort.AbortSignal<Unit>, fetch: Fetch.Fetch(Unit)) -> Base():
  Ai.StreamOptions{Some{signal}, None{}, text(field(options, "apiKey")), Some{fetch}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, transportOf(text(field(options, "transport"))), None{}, None{}, None{}, None{}}

def simpleOptions(+options: V.Value, signal: Abort.AbortSignal<Unit>, fetch: Fetch.Fetch(Unit)) -> Simple():
  Ai.SimpleStreamOptions{Some{signal}, None{}, text(field(options, "apiKey")), Some{fetch}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, transportOf(text(field(options, "transport"))), None{}, None{}, None{}, None{}, None{}, levelOf(text(field(options, "reasoning"))), None{}, None{}}

def googleThinking(value: Maybe<&2, V.Value>) -> Maybe<&2, Gemini.GoogleThinking>:
  match value:
    case Some{+thinking}: Some{Gemini.GoogleThinking{Maybe.default(&2, Bool, flag(field(thinking, "enabled")), False{}), number(field(thinking, "budgetTokens")), None{}}}
    case None{}: None{}

def responsesOptions(+options: V.Value, signal: Abort.AbortSignal<Unit>, fetch: Fetch.Fetch(Unit)) -> Responses.OpenAIResponsesOptions<Unit, Unit, Error()>:
  Responses.OpenAIResponsesOptions{Some{signal}, None{}, text(field(options, "apiKey")), Some{fetch}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, transportOf(text(field(options, "transport"))), None{}, None{}, None{}, None{}, levelOf(text(field(options, "reasoningEffort"))), None{}, None{}, None{}}

# Opening the stream
# ------------------
def render(error: Error()) -> String: Tools.errorMessage(error)

def failure(cause: Responses.Error<Unit, Error()>) -> Error():
  Tools.Failure{Responses.describe(~Unit, ~Error(), ~render, "openai", cause)}

def selected(-Options: Data, value: Options) -> Options: value

# upstream stream(): the provider's own options.
def opened(+fetch: Fetch.Fetch(Unit), counter: Ref.Ref<Nat>, api: Ai.ModelApi, +model: Model(), +context: Context(), +options: V.Value, signal: Abort.AbortSignal<Unit>) -> IO(Output()):
  match api:
    case Ai.AnthropicMessagesApi{}: Anthropic.openStream(fetch, TestClient.urlContext(), model, context, Messages.AnthropicOptions{baseOptions(options, signal, fetch), flag(field(options, "thinkingEnabled")), number(field(options, "thinkingBudgetTokens")), text(field(options, "effort")), None{}, None{}, None{}, None{}})
    case Ai.GoogleGenerativeAiApi{}: Google.openStream(fetch, TestClient.urlContext(), counter, model, context, Gemini.GoogleOptions{baseOptions(options, signal, fetch), None{}, googleThinking(field(options, "thinking"))})
    case Ai.OpenAICompletionsApi{}: Completions.openStream(fetch, TestClient.urlContext(), model, context, Chat.OpenAICompletionsOptions{baseOptions(options, signal, fetch), None{}, levelOf(text(field(options, "reasoningEffort"))), None{}})
    case Ai.AzureOpenAIResponsesApi{}:
      do IO<Output()>:
        owner : Responses.Run<Unit, Unit, Error()> <- Azure.stream(~Unit, ~Unit, ~Unit, ~Details(), ~Error(), ~render, RP.config(), model, context, Azure.AzureOpenAIResponsesOptions{baseOptions(options, signal, fetch), levelOf(text(field(options, "reasoningEffort"))), None{}, None{}, None{}, None{}, None{}, None{}})
        return Providers.lease(~Unit, ~Error(), ~failure, Responses.borrow(Unit, Unit, Error(), owner))
    case Ai.OpenAICodexResponsesApi{}:
      do IO<Output()>:
        owner : Responses.Run<Unit, Unit, Error()> <- Codex.stream(~Unit, ~Unit, ~Unit, ~Details(), ~Error(), ~render, RP.config(), model, context, responsesOptions(options, signal, fetch))
        return Providers.lease(~Unit, ~Error(), ~failure, Responses.borrow(Unit, Unit, Error(), owner))
    case _:
      do IO<Output()>:
        owner : Responses.Run<Unit, Unit, Error()> <- Responses.stream(~Unit, ~Unit, ~Unit, ~Details(), ~Error(), ~render, RP.config(), model, context, responsesOptions(options, signal, fetch))
        return Providers.lease(~Unit, ~Error(), ~failure, Responses.borrow(Unit, Unit, Error(), owner))

# upstream streamSimple(), as the agent runtime dispatches it.
def openedSimple(+fetch: Fetch.Fetch(Unit), counter: Ref.Ref<Nat>, api: Ai.ModelApi, +model: Model(), +context: Context(), +options: V.Value, signal: Abort.AbortSignal<Unit>) -> IO(Output()):
  match api:
    case Ai.AnthropicMessagesApi{}: Anthropic.open(fetch, TestClient.urlContext(), model, context, Some{simpleOptions(options, signal, fetch)})
    case Ai.GoogleGenerativeAiApi{}: Google.open(fetch, TestClient.urlContext(), counter, model, context, Some{simpleOptions(options, signal, fetch)})
    case Ai.OpenAICompletionsApi{}: Completions.open(fetch, TestClient.urlContext(), model, context, Some{simpleOptions(options, signal, fetch)})
    case _: Providers.openResponses(~Simple(), ~Unit, ~Unit, ~Details(), ~Error(), ~selected(Simple()), ~render, ~failure, RP.config(), Agent.StreamInput{model, context, Some{simpleOptions(options, signal, fetch)}})

def entered(+entry: String, fetch: Fetch.Fetch(Unit), counter: Ref.Ref<Nat>, +model: Model(), +context: Context(), +options: V.Value, signal: Abort.AbortSignal<Unit>) -> IO(Output()):
  match entry:
    case "simple": openedSimple(fetch, counter, apiOf(model), model, context, options, signal)
    case _: opened(fetch, counter, apiOf(model), model, context, options, signal)

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

def runWith(fetch: Fetch.Fetch(Unit), counter: Ref.Ref<Nat>, +value: V.Value, +model: Model(), context: Result<&2, &2, String, Context()>) -> IO(Unit):
  match context:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{+items}:
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        abortFirst(Maybe.default(&2, Bool, flag(field(value, "abortBefore")), False{}), controller)
        result : Output() <- entered(Maybe.default(&2, String, text(field(value, "entry")), "stream"), fetch, counter, model, items, Maybe.default(&2, V.Value, field(value, "options"), V.ObjectValue{R.new(V.Value)}), Abort.signal(Unit, controller))
        observed(result, controller, Maybe.map(&2, F64, Nat, natOf, number(field(value, "abortAfterChars"))), Maybe.default(&2, Bool, flag(field(value, "overflow")), False{}), windowOf(model))
        Abort.dispose(Unit, controller)

def withModel(fetch: Fetch.Fetch(Unit), counter: Ref.Ref<Nat>, +base: String, +value: V.Value, model: Maybe<&2, Model()>) -> IO(Unit):
  match model:
    case None{}: IO.die(Unit, 1, "unknown model")
    case Some{found}:
      +configured = withBaseUrl(withApi(found, apiNamed(text(field(value, "api")))), base ++ "/" ++ Maybe.default(&2, String, text(field(value, "run")), "run"))
      runWith(fetch, counter, value, configured, caseContext(configured, value, Maybe.default(&2, Bool, flag(field(value, "overflow")), False{})))

def keyOf(+value: V.Value) -> String:
  Maybe.default(&2, String, text(field(value, "provider")), "") ++ "/" ++ Maybe.default(&2, String, text(field(value, "model")), "")

def runCase(fetch: Fetch.Fetch(Unit), +base: String, parsed: Result<&2, &2, Decode.ParseError, V.Value>) -> IO(Unit):
  match parsed:
    case Fail{_}: IO.die(Unit, 1, "invalid case")
    case Done{+value}:
      do IO<Unit>:
        counter : Ref.Ref<Nat> <- Ref.new(Nat, 0n)
        withModel(fetch, counter, base, value, catalogModel(keyOf(value)))

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

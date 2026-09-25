import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ./ant-ling.bend as AntLing
import ./anthropic.bend as Anthropic
import ./azure-openai-responses.bend as AzureOpenAIResponses
import ./baseten.bend as Baseten
import ./cerebras.bend as Cerebras
import ./deepseek.bend as Deepseek
import ./fireworks.bend as Fireworks
import ./github-copilot.bend as GithubCopilot
import ./google.bend as Google
import ./groq.bend as Groq
import ./huggingface.bend as Huggingface
import ./kimi-coding.bend as KimiCoding
import ./meta.bend as Meta
import ./minimax.bend as Minimax
import ./minimax-cn.bend as MinimaxCn
import ./moonshotai.bend as Moonshotai
import ./moonshotai-cn.bend as MoonshotaiCn
import ./nvidia.bend as Nvidia
import ./openai.bend as Openai
import ./openai-codex.bend as OpenaiCodex
import ./opencode.bend as Opencode
import ./opencode-go.bend as OpencodeGo
import ./openrouter.bend as Openrouter
import ./qwen-token-plan.bend as QwenTokenPlan
import ./qwen-token-plan-cn.bend as QwenTokenPlanCn
import ./qwen-token-plan-individual.bend as QwenTokenPlanIndividual
import ./together.bend as Together
import ./vercel-ai-gateway.bend as VercelAIGateway
import ./xai.bend as Xai
import ./xiaomi.bend as Xiaomi
import ./xiaomi-token-plan-ams.bend as XiaomiTokenPlanAms
import ./xiaomi-token-plan-cn.bend as XiaomiTokenPlanCn
import ./xiaomi-token-plan-sgp.bend as XiaomiTokenPlanSgp
import ./zai.bend as Zai
import ./zai-coding-cn.bend as ZaiCodingCn

# upstream builtinProviders(), in providers/all.ts order. Omitted:
# amazon-bedrock, google-vertex, mistral and radius,
# whose APIs are not ported, and cloudflare-ai-gateway and
# cloudflare-workers-ai, whose account/gateway auth and base-URL placeholder
# stream wrapper are not ported. OAuth handlers are created by the caller.
# Each provider joins the list as soon as it is created: holding all of them
# in separate binders exceeds the native backend's closure arity (BEND-010).
def prepended(action: IO(Models.Provider), rest: List<&2, Models.Provider>) -> IO(List<&2, Models.Provider>):
  do IO<List<&2, Models.Provider>>:
    provider : Models.Provider <- action
    return provider <> rest

def builtinProviders(codex: Auth.OAuthAuth, anthropicOAuth: Maybe<&2, Auth.OAuthAuth>) -> IO(List<&2, Models.Provider>):
  do IO<List<&2, Models.Provider>>:
    providers : List<&2, Models.Provider> <- prepended(ZaiCodingCn.zaiCodingCnProvider(), Nil{})
    providers : List<&2, Models.Provider> <- prepended(Zai.zaiProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(XiaomiTokenPlanSgp.xiaomiTokenPlanSgpProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(XiaomiTokenPlanCn.xiaomiTokenPlanCnProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(XiaomiTokenPlanAms.xiaomiTokenPlanAmsProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Xiaomi.xiaomiProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Xai.xaiProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(VercelAIGateway.vercelAIGatewayProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Together.togetherProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(QwenTokenPlanIndividual.qwenTokenPlanIndividualProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(QwenTokenPlanCn.qwenTokenPlanCnProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(QwenTokenPlan.qwenTokenPlanProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Openrouter.openrouterProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(OpencodeGo.opencodeGoProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Opencode.opencodeProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(IO.pure(Models.Provider, OpenaiCodex.openaiCodexProvider(codex)), providers)
    providers : List<&2, Models.Provider> <- prepended(Openai.openaiProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Nvidia.nvidiaProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(MoonshotaiCn.moonshotaiCnProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Moonshotai.moonshotaiProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(MinimaxCn.minimaxCnProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Minimax.minimaxProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Meta.metaProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(KimiCoding.kimiCodingProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Huggingface.huggingfaceProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Groq.groqProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Google.googleProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(GithubCopilot.githubCopilotProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Fireworks.fireworksProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Deepseek.deepseekProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Cerebras.cerebrasProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Baseten.basetenProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(AzureOpenAIResponses.azureOpenAIResponsesProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Anthropic.anthropicProvider(anthropicOAuth), providers)
    providers : List<&2, Models.Provider> <- prepended(AntLing.antLingProvider(), providers)
    return providers

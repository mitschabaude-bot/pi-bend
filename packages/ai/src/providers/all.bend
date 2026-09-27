import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ./amazon-bedrock.bend as AmazonBedrock
import ./ant-ling.bend as AntLing
import ./anthropic.bend as Anthropic
import ./azure-openai-responses.bend as AzureOpenAIResponses
import ./baseten.bend as Baseten
import ./cerebras.bend as Cerebras
import ./cloudflare-ai-gateway.bend as CloudflareAIGateway
import ./cloudflare-workers-ai.bend as CloudflareWorkersAI
import ./deepseek.bend as Deepseek
import ./fireworks.bend as Fireworks
import ./github-copilot.bend as GithubCopilot
import ./google.bend as Google
import ./google-vertex.bend as GoogleVertex
import ./groq.bend as Groq
import ./huggingface.bend as Huggingface
import ./kimi-coding.bend as KimiCoding
import ./meta.bend as Meta
import ./minimax.bend as Minimax
import ./minimax-cn.bend as MinimaxCn
import ./mistral.bend as Mistral
import ./moonshotai.bend as Moonshotai
import ./moonshotai-cn.bend as MoonshotaiCn
import ./nvidia.bend as Nvidia
import ./openai.bend as Openai
import ./openai-codex.bend as OpenaiCodex
import ./opencode.bend as Opencode
import ./opencode-go.bend as OpencodeGo
import ./openrouter.bend as Openrouter
import ./openrouter-images.bend as OpenrouterImages
import ../images-models.bend as Images
import ../auth/oauth/xai.bend as XaiOAuth
import ../auth/oauth/meta.bend as MetaOAuth
import ../auth/oauth/kimi-coding.bend as KimiOAuth
import ../auth/oauth/github-copilot.bend as CopilotOAuth
import ../auth/oauth/openrouter.bend as OpenRouterOAuth
import ./model-data.generated.bend as ModelData
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/url.bend as URL
import ./qwen-token-plan.bend as QwenTokenPlan
import ./qwen-token-plan-cn.bend as QwenTokenPlanCn
import ./qwen-token-plan-individual.bend as QwenTokenPlanIndividual
import ./radius.bend as Radius
import ./together.bend as Together
import ./vercel-ai-gateway.bend as VercelAIGateway
import ./xai.bend as Xai
import ./xiaomi.bend as Xiaomi
import ./xiaomi-token-plan-ams.bend as XiaomiTokenPlanAms
import ./xiaomi-token-plan-cn.bend as XiaomiTokenPlanCn
import ./xiaomi-token-plan-sgp.bend as XiaomiTokenPlanSgp
import ./zai.bend as Zai
import ./zai-coding-cn.bend as ZaiCodingCn

# upstream builtinProviders(), in providers/all.ts order. The Codex and
# Anthropic OAuth handlers are created by the caller; Radius, xAI, OpenRouter,
# Meta, Kimi Code and GitHub Copilot create theirs over the given transport
# (upstream's lazyOAuth loads them on first use; creation here fetches nothing).
# Each provider joins the list as soon as it is created: holding all of them
# in separate binders exceeds the native backend's closure arity (BEND-010).
def prepended(action: IO(Models.Provider), rest: List<&2, Models.Provider>) -> IO(List<&2, Models.Provider>):
  do IO<List<&2, Models.Provider>>:
    provider : Models.Provider <- action
    return provider <> rest

def withOAuth(-P: Data, make: Maybe<&2, Auth.OAuthAuth> -> IO(P), oauth: IO(Auth.OAuthAuth)) -> IO(P):
  do IO<P>:
    handler : Auth.OAuthAuth <- oauth
    make(Some{handler})

def builtinProvidersOver(codex: Auth.OAuthAuth, anthropicOAuth: Maybe<&2, Auth.OAuthAuth>, +fetch: Fetch.Fetch(Unit), +url: URL.Context) -> IO(List<&2, Models.Provider>):
  do IO<List<&2, Models.Provider>>:
    +radius : Radius.RadiusTransport <- IO.pure(Radius.RadiusTransport, Radius.RadiusTransport{fetch, url})
    providers : List<&2, Models.Provider> <- prepended(ZaiCodingCn.zaiCodingCnProvider(), Nil{})
    providers : List<&2, Models.Provider> <- prepended(Zai.zaiProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(XiaomiTokenPlanSgp.xiaomiTokenPlanSgpProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(XiaomiTokenPlanCn.xiaomiTokenPlanCnProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(XiaomiTokenPlanAms.xiaomiTokenPlanAmsProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Xiaomi.xiaomiProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(withOAuth(Models.Provider, o => Xai.xaiProvider(o), XaiOAuth.xaiOAuth(fetch, url)), providers)
    providers : List<&2, Models.Provider> <- prepended(VercelAIGateway.vercelAIGatewayProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Together.togetherProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Radius.radiusProvider(Radius.defaultOptions(), radius), providers)
    providers : List<&2, Models.Provider> <- prepended(QwenTokenPlanIndividual.qwenTokenPlanIndividualProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(QwenTokenPlanCn.qwenTokenPlanCnProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(QwenTokenPlan.qwenTokenPlanProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(withOAuth(Models.Provider, o => Openrouter.openrouterProvider(o), OpenRouterOAuth.openRouterOAuth(fetch, url)), providers)
    providers : List<&2, Models.Provider> <- prepended(OpencodeGo.opencodeGoProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Opencode.opencodeProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(IO.pure(Models.Provider, OpenaiCodex.openaiCodexProvider(codex)), providers)
    providers : List<&2, Models.Provider> <- prepended(Openai.openaiProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Nvidia.nvidiaProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(MoonshotaiCn.moonshotaiCnProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Moonshotai.moonshotaiProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Mistral.mistralProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(MinimaxCn.minimaxCnProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Minimax.minimaxProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(withOAuth(Models.Provider, o => Meta.metaProvider(o), MetaOAuth.metaOAuth(fetch, url)), providers)
    providers : List<&2, Models.Provider> <- prepended(withOAuth(Models.Provider, o => KimiCoding.kimiCodingProvider(o), KimiOAuth.kimiCodingOAuth(fetch, url)), providers)
    providers : List<&2, Models.Provider> <- prepended(Huggingface.huggingfaceProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Groq.groqProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(GoogleVertex.googleVertexProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Google.googleProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(withOAuth(Models.Provider, o => GithubCopilot.githubCopilotProvider(o), CopilotOAuth.githubCopilotOAuth(fetch, url)), providers)
    providers : List<&2, Models.Provider> <- prepended(Fireworks.fireworksProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Deepseek.deepseekProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(CloudflareWorkersAI.cloudflareWorkersAIProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(CloudflareAIGateway.cloudflareAIGatewayProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Cerebras.cerebrasProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Baseten.basetenProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(AzureOpenAIResponses.azureOpenAIResponsesProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(Anthropic.anthropicProvider(anthropicOAuth), providers)
    providers : List<&2, Models.Provider> <- prepended(AntLing.antLingProvider(), providers)
    providers : List<&2, Models.Provider> <- prepended(AmazonBedrock.amazonBedrockProvider(), providers)
    return providers

def builtinProviders(codex: Auth.OAuthAuth, anthropicOAuth: Maybe<&2, Auth.OAuthAuth>, radius: Radius.RadiusTransport) -> IO(List<&2, Models.Provider>):
  match radius:
    case Radius.RadiusTransport{fetch, url}: builtinProvidersOver(codex, anthropicOAuth, fetch, url)

# upstream builtinImagesProviders: every built-in image-generation provider,
# freshly constructed, over the given api and OpenRouter OAuth handler.
# upstream getBuiltinModelDataGeneratedAt: when the built-in catalogs were
# generated (the pinned pi-ai data manifest), epoch milliseconds.
def getBuiltinModelDataGeneratedAt() -> Maybe<&2, F64>: ModelData.GENERATED_AT()

def builtinImagesProviders(-E: Data, oauth: Maybe<&2, Auth.OAuthAuth>, openrouter: Images.ProviderImages(E)) -> IO(List<&2, Images.ImagesProvider<E>>):
  do IO<List<&2, Images.ImagesProvider<E>>>:
    provider : Images.ImagesProvider<E> <- OpenrouterImages.openrouterImagesProvider(E, oauth, openrouter)
    return [provider]

def registered(-E: Data, providers: List<&2, Images.ImagesProvider<E>>, models: Images.ImagesModels<E>) -> Images.ImagesModels<E>:
  match providers:
    case Nil{}: models
    case provider <> rest: registered(E, rest, Images.setProvider(E, models, provider))

# upstream builtinImagesModels: an ImagesModels collection with every
# built-in image-generation provider registered.
def builtinImagesModels(-E: Data, credentials: Auth.CredentialStore, context: Auth.AuthContext, oauth: Maybe<&2, Auth.OAuthAuth>, openrouter: Images.ProviderImages(E)) -> IO(Images.ImagesModels<E>):
  do IO<Images.ImagesModels<E>>:
    providers : List<&2, Images.ImagesProvider<E>> <- builtinImagesProviders(E, oauth, openrouter)
    return registered(E, providers, Images.createImagesModels(E, credentials, context))

import Base
import ../models.bend as Models
import ../types.bend as T
import ../auth/types.bend as Auth
import ./cloudflare-auth.bend as CloudflareAuth
import ./cloudflare-workers-ai.models.bend as Catalog

def cloudflareWorkersAIProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- CloudflareAuth.cloudflareWorkersAIAuth()
    return Models.Provider{"cloudflare-workers-ai", "Cloudflare Workers AI", "", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.CLOUDFLARE_WORKERS_AI_MODELS(), Models.CloudflareStreams{[T.OpenAICompletionsApi{}]}}

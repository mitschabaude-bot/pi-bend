import Base
import ../models.bend as Models
import ../types.bend as T
import ../auth/types.bend as Auth
import ./cloudflare-auth.bend as CloudflareAuth
import ./cloudflare-ai-gateway.models.bend as Catalog

# The wrapped APIs are pinned to all three: models.dev's gateway catalog drops
# and restores `workers-ai/*` (openai-completions) entries over time.
def cloudflareAIGatewayProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- CloudflareAuth.cloudflareAIGatewayAuth()
    return Models.Provider{"cloudflare-ai-gateway", "Cloudflare AI Gateway", "", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.CLOUDFLARE_AI_GATEWAY_MODELS(), Models.CloudflareStreams{[T.AnthropicMessagesApi{}, T.OpenAICompletionsApi{}, T.OpenAIResponsesApi{}]}, None{}}

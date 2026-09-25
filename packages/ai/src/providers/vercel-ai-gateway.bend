import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./vercel-ai-gateway.models.bend as Catalog

def vercelAIGatewayProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Vercel AI Gateway API key", ["AI_GATEWAY_API_KEY"])
    return Models.Provider{"vercel-ai-gateway", "Vercel AI Gateway", "https://ai-gateway.vercel.sh", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.VERCEL_AI_GATEWAY_MODELS(), Models.ApiStreams{}, None{}}

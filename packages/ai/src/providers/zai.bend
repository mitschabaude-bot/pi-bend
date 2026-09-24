import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./zai.models.bend as Catalog

def zaiProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Z.AI API key", ["ZAI_API_KEY"])
    return Models.Provider{"zai", "Z.AI", "https://api.z.ai/api/coding/paas/v4", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.ZAI_MODELS()}

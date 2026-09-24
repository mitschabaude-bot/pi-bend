import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./openrouter.models.bend as Catalog

# Upstream also offers lazyOAuth "OpenRouter OAuth" (not ported).
def openrouterProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("OpenRouter API key", ["OPENROUTER_API_KEY"])
    return Models.Provider{"openrouter", "OpenRouter", "https://openrouter.ai/api/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.OPENROUTER_MODELS()}

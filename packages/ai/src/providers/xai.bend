import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./xai.models.bend as Catalog

# Upstream also offers lazyOAuth "xAI (Grok/X subscription)" (not ported).
def xaiProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("xAI API key", ["XAI_API_KEY"])
    return Models.Provider{"xai", "xAI", "https://api.x.ai/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.XAI_MODELS(), Models.ApiStreams{}, None{}}

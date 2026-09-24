import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./kimi-coding.models.bend as Catalog

# Upstream also offers lazyOAuth "Kimi Code (subscription)" (not ported).
def kimiCodingProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Kimi API key", ["KIMI_API_KEY"])
    return Models.Provider{"kimi-coding", "Kimi For Coding", "https://api.kimi.com/coding", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.KIMI_CODING_MODELS()}

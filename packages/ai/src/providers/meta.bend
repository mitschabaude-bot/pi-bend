import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./meta.models.bend as Catalog

# Upstream also offers lazyOAuth "Meta (Muse subscription)" (not ported).
def metaProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Meta Model API key", ["META_API_KEY"])
    return Models.Provider{"meta", "Meta", "https://api.meta.ai/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.META_MODELS(), Models.ApiStreams{}}

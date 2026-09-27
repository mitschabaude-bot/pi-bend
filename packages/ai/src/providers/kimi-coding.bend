import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./kimi-coding.models.bend as Catalog

# The OAuth handler (auth/oauth/kimi-coding.bend, "Kimi Code (subscription)")
# is created by the caller over its fetch, as upstream's lazyOAuth loads it.
def kimiCodingProvider(oauth: Maybe<&2, Auth.OAuthAuth>) -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Kimi API key", ["KIMI_API_KEY"])
    return Models.Provider{"kimi-coding", "Kimi For Coding", "https://api.kimi.com/coding", Auth.ProviderAuth{Some{apiKey}, oauth}, Catalog.KIMI_CODING_MODELS(), Models.ApiStreams{}, None{}}

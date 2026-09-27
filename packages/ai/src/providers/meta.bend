import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./meta.models.bend as Catalog

# The OAuth handler (auth/oauth/meta.bend, "Meta (Muse subscription)") is
# created by the caller over its fetch, as upstream's lazyOAuth loads it.
def metaProvider(oauth: Maybe<&2, Auth.OAuthAuth>) -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Meta Model API key", ["META_API_KEY"])
    return Models.Provider{"meta", "Meta", "https://api.meta.ai/v1", Auth.ProviderAuth{Some{apiKey}, oauth}, Catalog.META_MODELS(), Models.ApiStreams{}, None{}}

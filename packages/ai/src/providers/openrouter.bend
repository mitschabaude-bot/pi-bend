import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./openrouter.models.bend as Catalog

# The OAuth handler (auth/oauth/openrouter.bend, "OpenRouter OAuth") is
# created by the caller over its fetch, as upstream's lazyOAuth loads it.
def openrouterProvider(oauth: Maybe<&2, Auth.OAuthAuth>) -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("OpenRouter API key", ["OPENROUTER_API_KEY"])
    return Models.Provider{"openrouter", "OpenRouter", "https://openrouter.ai/api/v1", Auth.ProviderAuth{Some{apiKey}, oauth}, Catalog.OPENROUTER_MODELS(), Models.ApiStreams{}, None{}}

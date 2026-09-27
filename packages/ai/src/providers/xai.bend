import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./xai.models.bend as Catalog

# The OAuth handler (auth/oauth/xai.bend, "xAI (Grok/X subscription)") is
# created by the caller over its fetch, as upstream's lazyOAuth loads it.
def xaiProvider(oauth: Maybe<&2, Auth.OAuthAuth>) -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("xAI API key", ["XAI_API_KEY"])
    return Models.Provider{"xai", "xAI", "https://api.x.ai/v1", Auth.ProviderAuth{Some{apiKey}, oauth}, Catalog.XAI_MODELS(), Models.ApiStreams{}, None{}, None{}}

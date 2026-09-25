import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./anthropic.models.bend as Catalog

# The OAuth handler ("Anthropic (Claude Pro/Max)") is created by the caller.
# Upstream anthropicApiKeyAuth first sends ANTHROPIC_AUTH_TOKEN as a Bearer
# Authorization header; that step is not ported.
def anthropicProvider(oauth: Maybe<&2, Auth.OAuthAuth>) -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Anthropic API key", ["ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY"])
    return Models.Provider{"anthropic", "Anthropic", "https://api.anthropic.com", Auth.ProviderAuth{Some{apiKey}, oauth}, Catalog.ANTHROPIC_MODELS(), Models.ApiStreams{}, None{}}

import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./github-copilot.models.bend as Catalog

# The OAuth handler (auth/oauth/github-copilot.bend, "GitHub Copilot") is
# created by the caller over its fetch, as upstream's lazyOAuth loads it.
# Upstream's filterModels, which narrows the catalog to an OAuth credential's
# availableModelIds, is not carried by Models.Provider yet.
def githubCopilotProvider(oauth: Maybe<&2, Auth.OAuthAuth>) -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("GitHub Copilot token", ["COPILOT_GITHUB_TOKEN"])
    return Models.Provider{"github-copilot", "GitHub Copilot", "https://api.individual.githubcopilot.com", Auth.ProviderAuth{Some{apiKey}, oauth}, Catalog.GITHUB_COPILOT_MODELS(), Models.ApiStreams{}, None{}}

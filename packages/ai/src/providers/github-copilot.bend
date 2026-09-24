import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./github-copilot.models.bend as Catalog

# Upstream also offers lazyOAuth "GitHub Copilot" (not ported) and filterModels,
# which narrows the catalog only for OAuth credentials; with API key auth
# every model is available.
def githubCopilotProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("GitHub Copilot token", ["COPILOT_GITHUB_TOKEN"])
    return Models.Provider{"github-copilot", "GitHub Copilot", "https://api.individual.githubcopilot.com", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.GITHUB_COPILOT_MODELS()}

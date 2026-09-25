import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./opencode-go.models.bend as Catalog

# Upstream has no provider baseUrl (Provider.baseUrl "" here). Its
# withOpenCodeSessionHeader stream wrapper, which adds x-opencode-session
# from the request sessionId, is not ported.
def opencodeGoProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("OpenCode API key", ["OPENCODE_API_KEY"])
    return Models.Provider{"opencode-go", "OpenCode Go", "", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.OPENCODE_GO_MODELS(), Models.ApiStreams{}}

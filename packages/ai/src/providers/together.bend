import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./together.models.bend as Catalog

def togetherProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Together API key", ["TOGETHER_API_KEY"])
    return Models.Provider{"together", "Together", "https://api.together.ai/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.TOGETHER_MODELS(), Models.ApiStreams{}}

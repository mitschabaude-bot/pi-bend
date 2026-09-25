import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./openai.models.bend as Catalog

def openaiProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("OpenAI API key", ["OPENAI_API_KEY"])
    return Models.Provider{"openai", "OpenAI", "https://api.openai.com/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.OPENAI_MODELS(), Models.ApiStreams{}, None{}}

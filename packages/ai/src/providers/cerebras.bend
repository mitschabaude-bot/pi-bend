import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./cerebras.models.bend as Catalog

def cerebrasProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Cerebras API key", ["CEREBRAS_API_KEY"])
    return Models.Provider{"cerebras", "Cerebras", "https://api.cerebras.ai/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.CEREBRAS_MODELS(), Models.ApiStreams{}, None{}}

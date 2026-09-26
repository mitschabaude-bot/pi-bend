import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./mistral.models.bend as Catalog

def mistralProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Mistral API key", ["MISTRAL_API_KEY"])
    return Models.Provider{"mistral", "Mistral", "https://api.mistral.ai", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.MISTRAL_MODELS(), Models.ApiStreams{}, None{}}

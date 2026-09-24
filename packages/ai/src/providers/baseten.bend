import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./baseten.models.bend as Catalog

def basetenProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Baseten API key", ["BASETEN_API_KEY"])
    return Models.Provider{"baseten", "Baseten", "https://inference.baseten.co/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.BASETEN_MODELS()}

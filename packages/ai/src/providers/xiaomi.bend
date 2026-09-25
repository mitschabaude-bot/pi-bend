import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./xiaomi.models.bend as Catalog

def xiaomiProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Xiaomi API key", ["XIAOMI_API_KEY"])
    return Models.Provider{"xiaomi", "Xiaomi", "https://api.xiaomimimo.com/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.XIAOMI_MODELS(), Models.ApiStreams{}}

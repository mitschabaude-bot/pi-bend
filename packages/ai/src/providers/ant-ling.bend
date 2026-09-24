import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./ant-ling.models.bend as Catalog

def antLingProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Ant Ling API key", ["ANT_LING_API_KEY"])
    return Models.Provider{"ant-ling", "Ant Ling", "https://api.ant-ling.com/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.ANT_LING_MODELS()}

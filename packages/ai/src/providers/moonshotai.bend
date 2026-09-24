import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./moonshotai.models.bend as Catalog

def moonshotaiProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Moonshot AI API key", ["MOONSHOT_API_KEY"])
    return Models.Provider{"moonshotai", "Moonshot AI", "https://api.moonshot.ai/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.MOONSHOTAI_MODELS()}

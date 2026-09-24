import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./fireworks.models.bend as Catalog

def fireworksProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Fireworks API key", ["FIREWORKS_API_KEY"])
    return Models.Provider{"fireworks", "Fireworks", "https://api.fireworks.ai/inference", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.FIREWORKS_MODELS()}

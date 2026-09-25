import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./google.models.bend as Catalog

def googleProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Gemini API key", ["GEMINI_API_KEY"])
    return Models.Provider{"google", "Google", "https://generativelanguage.googleapis.com/v1beta", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.GOOGLE_MODELS(), Models.ApiStreams{}}

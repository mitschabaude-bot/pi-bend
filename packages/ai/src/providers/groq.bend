import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./groq.models.bend as Catalog

def groqProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Groq API key", ["GROQ_API_KEY"])
    return Models.Provider{"groq", "Groq", "https://api.groq.com/openai/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.GROQ_MODELS(), Models.ApiStreams{}, None{}}

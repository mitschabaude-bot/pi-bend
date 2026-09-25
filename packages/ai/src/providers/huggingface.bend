import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./huggingface.models.bend as Catalog

def huggingfaceProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Hugging Face token", ["HF_TOKEN"])
    return Models.Provider{"huggingface", "Hugging Face", "https://router.huggingface.co/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.HUGGINGFACE_MODELS(), Models.ApiStreams{}, None{}}

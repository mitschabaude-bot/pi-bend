import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./nvidia.models.bend as Catalog

def nvidiaProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("NVIDIA API key", ["NVIDIA_API_KEY"])
    return Models.Provider{"nvidia", "NVIDIA", "https://integrate.api.nvidia.com/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.NVIDIA_MODELS(), Models.ApiStreams{}, None{}}

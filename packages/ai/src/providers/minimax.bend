import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./minimax.models.bend as Catalog

def minimaxProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("MiniMax API key", ["MINIMAX_API_KEY"])
    return Models.Provider{"minimax", "MiniMax", "https://api.minimax.io/anthropic", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.MINIMAX_MODELS(), Models.ApiStreams{}}

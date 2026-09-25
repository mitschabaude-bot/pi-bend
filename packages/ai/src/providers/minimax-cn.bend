import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./minimax-cn.models.bend as Catalog

def minimaxCnProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("MiniMax CN API key", ["MINIMAX_CN_API_KEY"])
    return Models.Provider{"minimax-cn", "MiniMax CN", "https://api.minimaxi.com/anthropic", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.MINIMAX_CN_MODELS(), Models.ApiStreams{}, None{}}

import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./moonshotai-cn.models.bend as Catalog

def moonshotaiCnProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Moonshot AI API key", ["MOONSHOT_API_KEY"])
    return Models.Provider{"moonshotai-cn", "Moonshot AI CN", "https://api.moonshot.cn/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.MOONSHOTAI_CN_MODELS()}

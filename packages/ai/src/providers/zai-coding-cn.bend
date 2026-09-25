import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./zai-coding-cn.models.bend as Catalog

def zaiCodingCnProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Z.AI Coding CN API key", ["ZAI_CODING_CN_API_KEY"])
    return Models.Provider{"zai-coding-cn", "Z.AI Coding CN", "https://open.bigmodel.cn/api/coding/paas/v4", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.ZAI_CODING_CN_MODELS(), Models.ApiStreams{}}

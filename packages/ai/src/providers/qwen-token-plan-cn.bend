import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./qwen-token-plan-cn.models.bend as Catalog

def qwenTokenPlanCnProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Qwen Token Plan CN API key", ["QWEN_TOKEN_PLAN_CN_API_KEY"])
    return Models.Provider{"qwen-token-plan-cn", "Qwen Token Plan CN", "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.QWEN_TOKEN_PLAN_CN_MODELS(), Models.ApiStreams{}, None{}}

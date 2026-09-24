import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./xiaomi-token-plan-cn.models.bend as Catalog

def xiaomiTokenPlanCnProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Xiaomi Token Plan CN API key", ["XIAOMI_TOKEN_PLAN_CN_API_KEY"])
    return Models.Provider{"xiaomi-token-plan-cn", "Xiaomi Token Plan CN", "https://token-plan-cn.xiaomimimo.com/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.XIAOMI_TOKEN_PLAN_CN_MODELS()}

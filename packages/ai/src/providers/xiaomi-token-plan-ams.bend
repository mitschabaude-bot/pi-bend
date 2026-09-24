import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./xiaomi-token-plan-ams.models.bend as Catalog

def xiaomiTokenPlanAmsProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Xiaomi Token Plan AMS API key", ["XIAOMI_TOKEN_PLAN_AMS_API_KEY"])
    return Models.Provider{"xiaomi-token-plan-ams", "Xiaomi Token Plan AMS", "https://token-plan-ams.xiaomimimo.com/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.XIAOMI_TOKEN_PLAN_AMS_MODELS()}

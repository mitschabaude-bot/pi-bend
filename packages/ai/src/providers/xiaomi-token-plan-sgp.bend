import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./xiaomi-token-plan-sgp.models.bend as Catalog

def xiaomiTokenPlanSgpProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Xiaomi Token Plan SGP API key", ["XIAOMI_TOKEN_PLAN_SGP_API_KEY"])
    return Models.Provider{"xiaomi-token-plan-sgp", "Xiaomi Token Plan SGP", "https://token-plan-sgp.xiaomimimo.com/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.XIAOMI_TOKEN_PLAN_SGP_MODELS(), Models.ApiStreams{}, None{}}

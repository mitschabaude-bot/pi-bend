import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./qwen-token-plan.models.bend as Catalog

def qwenTokenPlanProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Qwen Token Plan API key", ["QWEN_TOKEN_PLAN_API_KEY"])
    return Models.Provider{"qwen-token-plan", "Qwen Token Plan", "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.QWEN_TOKEN_PLAN_MODELS(), Models.ApiStreams{}}

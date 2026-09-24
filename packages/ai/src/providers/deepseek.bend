import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./deepseek.models.bend as Catalog

def deepseekProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("DeepSeek API key", ["DEEPSEEK_API_KEY"])
    return Models.Provider{"deepseek", "DeepSeek", "https://api.deepseek.com", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.DEEPSEEK_MODELS()}

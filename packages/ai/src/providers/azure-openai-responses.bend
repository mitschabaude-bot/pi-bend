import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ../auth/helpers.bend as Helpers
import ./azure-openai-responses.models.bend as Catalog

# Upstream passes no provider base URL: requests resolve it from the options,
# AZURE_OPENAI_BASE_URL / AZURE_OPENAI_RESOURCE_NAME or the model.
def azureOpenAIResponsesProvider() -> IO(Models.Provider):
  do IO<Models.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Azure OpenAI API key", ["AZURE_OPENAI_API_KEY"])
    return Models.Provider{"azure-openai-responses", "Azure OpenAI", "", Auth.ProviderAuth{Some{apiKey}, None{}}, Catalog.AZURE_OPENAI_RESPONSES_MODELS()}

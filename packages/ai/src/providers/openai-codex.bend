import Base
import ../models.bend as Models
import ../auth/types.bend as Auth
import ./openai-codex.models.bend as Catalog

# The OAuth handler ("OpenAI (ChatGPT Plus/Pro)") is created by the caller.
def openaiCodexProvider(oauth: Auth.OAuthAuth) -> Models.Provider:
  Models.Provider{"openai-codex", "OpenAI Codex", "https://chatgpt.com/backend-api", Auth.ProviderAuth{None{}, Some{oauth}}, Catalog.OPENAI_CODEX_MODELS(), Models.ApiStreams{}}

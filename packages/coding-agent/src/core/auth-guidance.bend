import Base
import ../../../runtime/src/posix-path.bend as Path

# pi v0.87.1 core/auth-guidance.ts. Upstream reads the docs directory from its
# package location (config.ts getDocsPath); callers here pass that directory.

def unknownProvider() -> String: "unknown"

def getProviderLoginHelp(+docsPath: String) -> String:
  "Use /login to log into a provider via OAuth or API key. See:\n  " ++ Path.join(docsPath,"providers.md") ++ "\n  " ++ Path.join(docsPath,"models.md")

def formatNoModelsAvailableMessage(docsPath: String) -> String:
  "No models available. " ++ getProviderLoginHelp(docsPath)

def formatNoModelSelectedMessage(docsPath: String) -> String:
  "No model selected.\n\n" ++ getProviderLoginHelp(docsPath) ++ "\n\nThen use /model to select a model."

def formatNoApiKeyFoundMessage(+provider: String,docsPath: String) -> String:
  "No API key found for " ++ Bool.pick(String,String.eq(provider,unknownProvider()),"the selected model",provider) ++ ".\n\n" ++ getProviderLoginHelp(docsPath)

import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/helpers.bend as Helpers
import ../packages/ai/src/auth/context.bend as Context
import ../packages/runtime/src/record.bend as Rec
import ../packages/coding-agent/src/core/auth-storage.bend as AuthStorage
import ../packages/ai/src/models.bend as AiModels
import ../packages/coding-agent/src/core/model-runtime.bend as Models

# A model runtime for session fixtures: in-memory credentials and providers
# whose API key is the named environment variable, so the check script
# decides which providers are available.
def storeOf(pair: AuthStorage.AuthStorageOwner & AuthStorage.AuthStorage) -> IO(Auth.CredentialStore):
  match pair:
    case (_, storage): AuthStorage.store(storage)

type Source is Data:
  Source{provider: String, envVar: String, models: List<&2, Ai.Model<Ai.JsonValue>>}

def providers(sources: List<&2, Source>) -> IO(List<&2, AiModels.Provider>):
  match sources:
    case Nil{}: IO.pure(List<&2, AiModels.Provider>, Nil{})
    case Source{+provider, envVar, models} <> rest:
      do IO<List<&2, AiModels.Provider>>:
        apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Test API key", envVar <> Nil{})
        others : List<&2, AiModels.Provider> <- providers(rest)
        return AiModels.Provider{provider, provider, "https://faux.invalid", Auth.ProviderAuth{Some{apiKey}, None{}}, models} <> others

def create(sources: List<&2, Source>) -> IO(Models.ModelRuntime):
  do IO<Models.ModelRuntime>:
    owner : AuthStorage.AuthStorageOwner <- AuthStorage.inMemory(Rec.new(Auth.Credential))
    store : Auth.CredentialStore <- storeOf(AuthStorage.borrow(owner))
    available : List<&2, AiModels.Provider> <- providers(sources)
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    Models.fromProviders(available, store, context)

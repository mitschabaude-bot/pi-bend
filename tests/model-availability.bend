import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/models.bend as AiModels
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/helpers.bend as Helpers
import ../packages/ai/src/auth/context.bend as Context
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref

# The upstream model-runtime-auth-options test exercises a scoped credential
# read, an error visible through getError, and clearing that error on success.
# This also checks that a scoped query does not replace the shared snapshot.
type State is Data:
  State{reads: List<&2, String>, fail: Bool, secondEnabled: Bool}

def recorded(reads: List<&2, String>, fail: Bool, enabled: Bool, id: String) -> State:
  State{id <> reads, fail, enabled}

def observed(state: State, +id: String) -> State & Auth.StoreResult(Maybe<&2, Auth.Credential>):
  match state:
    case State{reads, +fail, +secondEnabled}:
      +next = recorded(reads, fail, secondEnabled, id)
      Bool.pick(State & Auth.StoreResult(Maybe<&2, Auth.Credential>), fail && String.eq(id, "a"),
        (next, Fail{"read failed for a"}),
        (next, Done{Bool.pick(Maybe<&2, Auth.Credential>, String.eq(id, "b") && Bool.not(secondEnabled), None{}, Some{Auth.ApiKeyCredential{Some{"stored-key"}, None{}}})}))

def readStore(state: Ref.Ref<State>, request: Auth.Request) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  match request:
    case Auth.Request{id, _}: Ref.modify(State, Auth.StoreResult(Maybe<&2, Auth.Credential>), state, current => observed(current, id))

def listStore(_: Unit, _: Auth.Signal()) -> IO(Auth.StoreResult(List<&2, Auth.CredentialInfo>)):
  IO.pure(Auth.StoreResult(List<&2, Auth.CredentialInfo>), Done{Nil{}})

def modifyStore(_: Unit, _: Auth.Modify) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)):
  IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Fail{"unused"})

def deleteStore(_: Unit, _: Auth.Request) -> IO(Auth.StoreResult(Unit)):
  IO.pure(Auth.StoreResult(Unit), Fail{"unused"})

def credentials(state: Ref.Ref<State>) -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    reader : C.Callback<Auth.Request, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Ref.Ref<State>, ~Auth.Request, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~readStore, state)
    lister : C.Callback<Auth.Signal(), Auth.StoreResult(List<&2, Auth.CredentialInfo>)> <- C.create(~Unit, ~(Auth.Signal()), ~(Auth.StoreResult(List<&2, Auth.CredentialInfo>)), ~listStore, Unit{})
    modifier : C.Callback<Auth.Modify, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Unit, ~Auth.Modify, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~modifyStore, Unit{})
    deleter : C.Callback<Auth.Request, Auth.StoreResult(Unit)> <- C.create(~Unit, ~Auth.Request, ~(Auth.StoreResult(Unit)), ~deleteStore, Unit{})
    return Auth.CredentialStore{reader, lister, modifier, deleter}

def model(id: String) -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"only", "Only", Ai.OpenAIResponsesApi{}, id, "https://faux.invalid", False{}, None{}, [Ai.InputText{}], None{}, Ai.ModelCost{U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), None{}}, None{}, U32.to_f64(1000), U32.to_f64(100), None{}, None{}, None{}}

def provider(+id: String) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    apiKey : Auth.ApiKeyAuth <- Helpers.envApiKeyAuth("Test API key", ["PI_AVAILABILITY_TEST_UNUSED"])
    return AiModels.Provider{id, id, "https://faux.invalid", Auth.ProviderAuth{Some{apiKey}, None{}}, [model(id)], AiModels.ApiStreams{}, None{}, None{}}

def updated(state: State, fail: Bool, enabled: Bool) -> State & Unit:
  match state:
    case State{_, _, _}: (State{Nil{}, fail, enabled}, Unit{})

def require(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def successfulCount(result: AiModels.AvailableResult(), count: Nat) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{models}: Nat.is_eq(List.length(&2, AiModels.Model(), models), count)

def failed(result: AiModels.AvailableResult()) -> Bool:
  match result:
    case Fail{_}: True{}
    case Done{_}: False{}

def errorContains(value: Maybe<&2, String>, needle: String) -> Bool:
  match value:
    case None{}: False{}
    case Some{text}: String.contains(text, needle)

def allB(reads: List<&2, String>) -> Bool:
  match reads:
    case Nil{}: True{}
    case id <> rest: String.eq(id, "b") && allB(rest)

def onlyB(state: State) -> Bool:
  match state:
    case State{Nil{}, _, _}: False{}
    case State{reads, _, _}: allB(reads)

def check(+runtime: Models.ModelRuntime, +state: Ref.Ref<State>) -> IO(Unit):
  do IO<Unit>:
    Ref.modify(State, Unit, state, current => updated(current, False{}, False{}))
    scoped : AiModels.AvailableResult() <- Models.getAvailable(runtime, Some{"b"}, None{})
    require(successfulCount(scoped, 0n), "scoped query should see changed credentials")
    reads : State <- Ref.read(State, state)
    require(onlyB(reads), "scoped query should read only b")
    snapshot : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(Nat.is_eq(List.length(&2, AiModels.Model(), snapshot), 2n), "scoped query changed the snapshot")
    Ref.modify(State, Unit, state, current => updated(current, True{}, False{}))
    failure : AiModels.AvailableResult() <- Models.getAvailable(runtime, Some{"a"}, None{})
    require(failed(failure), "credential read failure was swallowed")
    error : Maybe<&2, String> <- Models.getError(runtime)
    require(errorContains(error, "Availability refresh: Credential store read failed for a"), "availability error missing")
    Ref.modify(State, Unit, state, current => updated(current, False{}, False{}))
    fresh : AiModels.AvailableResult() <- Models.getAvailable(runtime, None{}, None{})
    require(successfulCount(fresh, 1n), "full query did not refresh the snapshot")
    cleared : Maybe<&2, String> <- Models.getError(runtime)
    require(Maybe.is_none(&2, String, cleared), "successful refresh did not clear error")
    final : List<&2, AiModels.Model()> <- Models.getAvailableSnapshot(runtime)
    require(Nat.is_eq(List.length(&2, AiModels.Model(), final), 1n), "full query did not publish snapshot")

def main() -> IO(Unit):
  do IO<Unit>:
    +state : Ref.Ref<State> <- Ref.new(State, State{Nil{}, False{}, True{}})
    +store : Auth.CredentialStore <- credentials(state)
    context : Auth.AuthContext <- Context.defaultProviderAuthContext()
    a : AiModels.Provider <- provider("a")
    b : AiModels.Provider <- provider("b")
    +runtime : Models.ModelRuntime <- Models.fromProviders([a, b], store, context)
    check(runtime, state)
    Models.dispose(runtime)
    Auth.disposeStore(store)
    previous : State <- Ref.dispose(State, state)
    IO.print("model availability: scoped reads, errors, and snapshots pass")

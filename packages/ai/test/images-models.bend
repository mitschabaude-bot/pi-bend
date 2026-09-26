import Base
import ../src/types.bend as T
import ../src/auth/types.bend as Auth
import ../src/auth/resolve.bend as Resolve
import ../src/images-models.bend as Images
import ../src/providers/all.bend as All
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as R
import ../../runtime/src/ref.bend as Ref

# upstream images-models.test.ts ("ImagesModels"). Upstream mutates one
# collection; here each setProvider/deleteProvider returns the next value.
# The collection takes an empty credential store and the fake auth context
# explicitly (upstream's default in-memory store). Generate calls are recorded
# in a reference as `model|apiKey|env` lines, env keys sorted (upstream
# compares with toEqual, which ignores key order).

def Error() -> Data: String

def Model() -> Data: T.ImagesModel<T.JsonValue>

def Env() -> Data: R.Record<String>

def Calls() -> Data: Ref.Ref<List<&2, String>>

def Provider() -> Data: Images.ImagesProvider<Error()>

def Collection() -> Data: Images.ImagesModels<Error()>

def zero() -> F64: F.fromU32(0)

def expect(+name: String, +actual: String, +expected: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(actual, expected), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ actual ++ " != " ++ expected))

# Fakes
# -----

def lookup(env: Env(), name: String) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, R.get(String, env, name))

def noFile(env: Env(), path: String) -> IO(Bool): IO.pure(Bool, False{})

def fakeAuthContext(+env: Env()) -> IO(Auth.AuthContext):
  do IO<Auth.AuthContext>:
    environment : C.Callback<String, Maybe<&2, String>> <- C.create(~Env(), ~String, ~Maybe<&2, String>, ~lookup, env)
    exists : C.Callback<String, Bool> <- C.create(~Env(), ~String, ~Bool, ~noFile, env)
    return Auth.AuthContext{environment, exists}

def nothingStored(unused: Unit, request: Auth.Request) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)): IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{None{}})

def noneListed(unused: Unit, signal: Auth.Signal()) -> IO(Auth.StoreResult(List<&2, Auth.CredentialInfo>)): IO.pure(Auth.StoreResult(List<&2, Auth.CredentialInfo>), Done{Nil{}})

def unmodified(unused: Unit, request: Auth.Modify) -> IO(Auth.StoreResult(Maybe<&2, Auth.Credential>)): IO.pure(Auth.StoreResult(Maybe<&2, Auth.Credential>), Done{None{}})

def deleted(unused: Unit, request: Auth.Request) -> IO(Auth.StoreResult(Unit)): IO.pure(Auth.StoreResult(Unit), Done{Unit{}})

def emptyStore() -> IO(Auth.CredentialStore):
  do IO<Auth.CredentialStore>:
    reader : C.Callback<Auth.Request, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Unit, ~Auth.Request, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~nothingStored, Unit{})
    lister : C.Callback<Auth.Signal(), Auth.StoreResult(List<&2, Auth.CredentialInfo>)> <- C.create(~Unit, ~(Auth.Signal()), ~(Auth.StoreResult(List<&2, Auth.CredentialInfo>)), ~noneListed, Unit{})
    modifier : C.Callback<Auth.Modify, Auth.StoreResult(Maybe<&2, Auth.Credential>)> <- C.create(~Unit, ~Auth.Modify, ~(Auth.StoreResult(Maybe<&2, Auth.Credential>)), ~unmodified, Unit{})
    deleter : C.Callback<Auth.Request, Auth.StoreResult(Unit)> <- C.create(~Unit, ~Auth.Request, ~(Auth.StoreResult(Unit)), ~deleted, Unit{})
    return Auth.CredentialStore{reader, lister, modifier, deleter}

def context() -> T.ImagesContext: T.ImagesContext{[T.TextImageText{T.TextContent{"a red circle", None{}}}]}

def collection(+env: Env()) -> IO(Collection()):
  do IO<Collection()>:
    store : Auth.CredentialStore <- emptyStore()
    context : Auth.AuthContext <- fakeAuthContext(env)
    return Images.createImagesModels(Error(), store, context)

def vars(entries: List<&2, R.Property<String>>) -> Env(): R.Record{entries}

def testImageModel(provider: String, +id: String) -> Model():
  T.ImagesModel{id, id, "test-images", provider, "https://example.test/v1", None{}, [T.InputText{}], None{}, T.ModelCost{zero(), zero(), zero(), zero(), None{}}, None{}, None{}, None{}, [T.InputImage{}]}

def modelId(model: Model()) -> String:
  match model:
    case T.ImagesModel{id, _, _, _, _, _, _, _, _, _, _, _, _}: id

def okResult(model: Model()) -> T.AssistantImages:
  match model:
    case T.ImagesModel{id, _, api, provider, _, _, _, _, _, _, _, _, _}: T.AssistantImages{api, provider, id, [T.TextImageImage{T.ImageContent{"aGk=", "image/png"}}], None{}, None{}, T.ImagesStop{}, None{}, zero()}

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case Some{text}: text
    case None{}: "-"

def propertyName(entry: R.Property<String>) -> String:
  match entry:
    case R.Property{name, _}: name

def insertSorted(+entry: R.Property<String>, sorted: List<&2, R.Property<String>>) -> List<&2, R.Property<String>>:
  match sorted:
    case Nil{}: [entry]
    case +head <> +rest: Bool.pick(Unit -> List<&2, R.Property<String>>, String.is_lt(propertyName(entry), propertyName(head)), _ => entry <> head <> rest, _ => head <> insertSorted(entry, rest))(Unit{})

def sortEntries(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<String>>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: insertSorted(entry, sortEntries(rest))

def entryTexts(entries: List<&2, R.Property<String>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: (name ++ "=" ++ value) <> entryTexts(rest)

def envText(env: Maybe<&2, Env()>) -> String:
  match env:
    case None{}: "-"
    case Some{R.Record{entries}}: String.join(entryTexts(sortEntries(entries)), ",")

def callText(model: Model(), options: Maybe<&2, Images.Options(Error())>) -> String:
  match options:
    case None{}: modelId(model) ++ "|-|-"
    case Some{T.ImagesOptions{_, _, apiKey, _, env, _, _, _, _, _, _, _}}: modelId(model) ++ "|" ++ optional(apiKey) ++ "|" ++ envText(env)

# upstream testProvider's api: records the call and succeeds.
def recordCall(calls: Calls(), request: Images.ImagesRequest<Error()>) -> IO(T.AssistantImages):
  match request:
    case Images.ImagesRequest{+model, _, options}:
      do IO<T.AssistantImages>:
        Ref.modify(List<&2, String>, Unit, calls, list => (List.append(&2, String, list, [callText(model, options)]), Unit{}))
        return okResult(model)

def recordingApi(calls: Calls()) -> IO(Images.ProviderImages(Error())):
  C.create(~Calls(), ~(Images.ImagesRequest<Error()>), ~T.AssistantImages, ~recordCall, calls)

def okBody(unused: Unit, request: Images.ImagesRequest<Error()>) -> IO(T.AssistantImages):
  match request:
    case Images.ImagesRequest{model, _, _}: IO.pure(T.AssistantImages, okResult(model))

def okApi() -> IO(Images.ProviderImages(Error())):
  C.create(~Unit, ~(Images.ImagesRequest<Error()>), ~T.AssistantImages, ~okBody, Unit{})

# upstream testProvider's resolve: without an env var the provider is
# configured with no auth; otherwise the stored or ambient key.
def resolveKey(credential: Maybe<&2, String>, ambient: Maybe<&2, String>, envVar: String) -> Auth.AuthOutcome():
  match credential ambient:
    case Some{key} _: Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{key}, None{}, None{}}, None{}, Some{"stored"}}}}
    case None{} Some{SCon{c, cs}}: Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{SCon{c, cs}}, None{}, None{}}, None{}, Some{envVar}}}}
    case None{} _: Done{None{}}

def storedKey(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, String>:
  match credential:
    case Some{Auth.ApiKeyCredential{key, _}}: key
    case _: None{}

def envResolve(envVar: Maybe<&2, String>, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match envVar input:
    case None{} _: IO.pure(Auth.AuthOutcome(), Done{Some{Auth.AuthResult{Auth.ModelAuth{None{}, None{}, None{}}, None{}, None{}}}})
    case Some{+name} Auth.ResolveInput{context, credential, _}:
      do IO<Auth.AuthOutcome()>:
        ambient : Maybe<&2, String> <- Auth.envValue(context, name)
        return resolveKey(storedKey(credential), ambient, name)

def keyAuth(envVar: Maybe<&2, String>) -> IO(Auth.ProviderAuth):
  do IO<Auth.ProviderAuth>:
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Maybe<&2, String>, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~envResolve, envVar)
    return Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Test key", None{}, resolve}}, None{}}

def testProvider(+id: String, models: List<&2, Model()>, envVar: Maybe<&2, String>, api: Images.ProviderImages(Error())) -> IO(Provider()):
  do IO<Provider()>:
    auth : Auth.ProviderAuth <- keyAuth(envVar)
    Images.createImagesProvider(Error(), Images.CreateImagesProviderOptions{id, None{}, auth, models, None{}, api})

def providerIds(providers: List<&2, Provider()>) -> List<&2, String>:
  match providers:
    case Nil{}: Nil{}
    case provider <> rest: Images.providerId(Error(), provider) <> providerIds(rest)

def modelIds(models: List<&2, Model()>) -> String:
  match models:
    case Nil{}: ""
    case model <> Nil{}: modelId(model)
    case model <> rest: modelId(model) ++ "," ++ modelIds(rest)

def maybeModel(model: Maybe<&2, Model()>) -> String:
  match model:
    case Some{value}: modelId(value)
    case None{}: "undefined"

def authKey(resolution: Resolve.Resolution()) -> String:
  match resolution:
    case Fail{error}: "error:" ++ Resolve.errorMessage(error)
    case Done{None{}}: "undefined"
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{key, _, _}, _, _}}}: optional(key)

def stopText(result: T.AssistantImages) -> String:
  match result:
    case T.AssistantImages{_, _, _, _, _, _, T.ImagesStop{}, _, _}: "stop"
    case T.AssistantImages{_, _, _, _, _, _, T.ImagesError{}, error, _}: "error:" ++ optional(error)
    case T.AssistantImages{_, _, _, _, _, _, T.ImagesAborted{}, error, _}: "aborted:" ++ optional(error)

def requestOptions(key: Maybe<&2, String>, env: Maybe<&2, Env()>) -> Maybe<&2, Images.Options(Error())>:
  Some{T.ImagesOptions{None{}, None{}, key, None{}, env, None{}, None{}, None{}, None{}, None{}, None{}, None{}}}

def overrides(key: Maybe<&2, String>) -> Resolve.AuthResolutionOverrides: Resolve.AuthResolutionOverrides{key, None{}, None{}, None{}}

def callLines(calls: Calls()) -> IO(String):
  do IO<String>:
    list : List<&2, String> <- Ref.read(List<&2, String>, calls)
    return String.join(list, ";")

# Cases
# -----

def registersProviders() -> IO(Unit):
  do IO<Unit>:
    empty : Collection() <- collection(vars(Nil{}))
    api1 : Images.ProviderImages(Error()) <- okApi()
    api2 : Images.ProviderImages(Error()) <- okApi()
    p1 : Provider() <- testProvider("p1", [testImageModel("p1", "m1"), testImageModel("p1", "m2")], None{}, api1)
    p2 : Provider() <- testProvider("p2", [testImageModel("p2", "m3")], None{}, api2)
    +models : Collection() <- IO.pure(Collection(), Images.setProvider(Error(), Images.setProvider(Error(), empty, p1), p2))
    all : List<&2, Model()> <- Images.getModels(Error(), models, None{})
    first : List<&2, Model()> <- Images.getModels(Error(), models, Some{"p1"})
    m3 : Maybe<&2, Model()> <- Images.getModel(Error(), models, "p2", "m3")
    missing : Maybe<&2, Model()> <- Images.getModel(Error(), models, "p2", "missing")
    +remaining : Collection() <- IO.pure(Collection(), Images.deleteProvider(Error(), models, "p1"))
    expect("registers providers and reads models synchronously", String.join(providerIds(Images.getProviders(Error(), models)), ",") ++ "|" ++ modelIds(all) ++ "|" ++ modelIds(first) ++ "|" ++ maybeModel(m3) ++ "|" ++ maybeModel(missing) ++ "|" ++ Bool.pick(String, Maybe.is_none(&2, Provider(), Images.getProvider(Error(), remaining, "p1")), "deleted", "present"), "p1,p2|m1,m2,m3|m1,m2|m3|undefined|deleted")

def resolvesAuth() -> IO(Unit):
  do IO<Unit>:
    empty : Collection() <- collection(vars([R.Property{"TEST_KEY", "env-key"}]))
    +calls : Calls() <- Ref.new(List<&2, String>, Nil{})
    api : Images.ProviderImages(Error()) <- recordingApi(calls)
    provider : Provider() <- testProvider("p1", [testImageModel("p1", "model-a")], Some{"TEST_KEY"}, api)
    +models : Collection() <- IO.pure(Collection(), Images.setProvider(Error(), empty, provider))
    +model : Model() <- IO.pure(Model(), testImageModel("p1", "model-a"))
    byModel : Resolve.Resolution() <- Images.getModelAuth(Error(), models, model, Resolve.noOverrides())
    byId : Resolve.Resolution() <- Images.getAuth(Error(), models, "p1", Resolve.noOverrides())
    explicit : Resolve.Resolution() <- Images.getModelAuth(Error(), models, model, overrides(Some{"explicit-key"}))
    first : T.AssistantImages <- Images.generateImages(Error(), models, model, context(), None{})
    second : T.AssistantImages <- Images.generateImages(Error(), models, model, context(), requestOptions(Some{"explicit"}, None{}))
    recorded : String <- callLines(calls)
    expect("resolves auth through the provider and merges it into requests; explicit options win", authKey(byModel) ++ "|" ++ authKey(byId) ++ "|" ++ authKey(explicit) ++ "|" ++ stopText(first) ++ "|" ++ recorded, "env-key|env-key|explicit-key|stop|model-a|env-key|-;model-a|explicit|-")

def providerEnvResolve(unused: Unit, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  IO.pure(Auth.AuthOutcome(), Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{"provider-key"}, None{}, None{}}, Some{vars([R.Property{"PROVIDER_ONLY", "provider"}, R.Property{"SHARED", "provider"}])}, None{}}}})

def mergesEnv() -> IO(Unit):
  do IO<Unit>:
    empty : Collection() <- collection(vars(Nil{}))
    +calls : Calls() <- Ref.new(List<&2, String>, Nil{})
    api : Images.ProviderImages(Error()) <- recordingApi(calls)
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~providerEnvResolve, Unit{})
    provider : Provider() <- Images.createImagesProvider(Error(), Images.CreateImagesProviderOptions{"p1", None{}, Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Test key", None{}, resolve}}, None{}}, [testImageModel("p1", "model-a")], None{}, api})
    +models : Collection() <- IO.pure(Collection(), Images.setProvider(Error(), empty, provider))
    result : T.AssistantImages <- Images.generateImages(Error(), models, testImageModel("p1", "model-a"), context(), requestOptions(Some{"request-key"}, Some{vars([R.Property{"REQUEST_ONLY", "request"}, R.Property{"SHARED", "request"}])}))
    recorded : String <- callLines(calls)
    expect("merges provider-resolved env into image options", recorded, "model-a|request-key|PROVIDER_ONLY=provider,REQUEST_ONLY=request,SHARED=request")

def unknownProviders() -> IO(Unit):
  do IO<Unit>:
    +empty : Collection() <- collection(vars(Nil{}))
    ghost : T.AssistantImages <- Images.generateImages(Error(), empty, testImageModel("ghost", "m"), context(), None{})
    +calls : Calls() <- Ref.new(List<&2, String>, Nil{})
    api : Images.ProviderImages(Error()) <- recordingApi(calls)
    provider : Provider() <- testProvider("p1", [testImageModel("p1", "model-a")], Some{"MISSING"}, api)
    +models : Collection() <- IO.pure(Collection(), Images.setProvider(Error(), empty, provider))
    unconfigured : Resolve.Resolution() <- Images.getModelAuth(Error(), models, testImageModel("p1", "model-a"), Resolve.noOverrides())
    dispatched : T.AssistantImages <- Images.generateImages(Error(), models, testImageModel("p1", "model-a"), context(), None{})
    recorded : String <- callLines(calls)
    expect("returns an error result for unknown providers and unconfigured auth rejections", stopText(ghost) ++ "|" ++ authKey(unconfigured) ++ "|" ++ recorded, "error:Unknown provider: ghost|undefined|model-a|-|-")

# upstream's dynamic provider: counts fetches and answers after 5 ms.
def listed(fetches: Ref.Ref<Nat>, unused: Unit) -> IO(Result<&2, &2, String, List<&2, Model()>>):
  do IO<Result<&2, &2, String, List<&2, Model()>>>:
    Ref.modify(Nat, Unit, fetches, n => (1n + n, Unit{}))
    IO.sleep(5)
    return Done{[testImageModel("dyn", "listed")]}

def flaky(unused: Unit, input: Unit) -> IO(Result<&2, &2, String, List<&2, Model()>>):
  IO.pure(Result<&2, &2, String, List<&2, Model()>>, Fail{"fetch failed"})

def noAuthResolve(unused: Unit, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  IO.pure(Auth.AuthOutcome(), Done{Some{Auth.AuthResult{Auth.ModelAuth{None{}, None{}, None{}}, None{}, None{}}}})

def noAuth() -> IO(Auth.ProviderAuth):
  do IO<Auth.ProviderAuth>:
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~noAuthResolve, Unit{})
    return Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Test", None{}, resolve}}, None{}}

def dynamicProvider(+id: String, fetch: Images.RefreshImagesModels()) -> IO(Provider()):
  do IO<Provider()>:
    auth : Auth.ProviderAuth <- noAuth()
    api : Images.ProviderImages(Error()) <- okApi()
    Images.createImagesProvider(Error(), Images.CreateImagesProviderOptions{id, None{}, auth, Nil{}, Some{fetch}, api})

def errorCode(result: Result<&2, &2, Resolve.ModelsError, Unit>) -> String:
  match result:
    case Fail{Resolve.ModelsError{Resolve.ModelSource{}, message}}: "model_source:" ++ message
    case Fail{Resolve.ModelsError{_, message}}: "other:" ++ message
    case Done{_}: "resolved"

def refreshes() -> IO(Unit):
  do IO<Unit>:
    empty : Collection() <- collection(vars(Nil{}))
    +fetches : Ref.Ref<Nat> <- Ref.new(Nat, 0n)
    fetch : Images.RefreshImagesModels() <- C.create(~Ref.Ref<Nat>, ~Unit, ~Result<&2, &2, String, List<&2, Model()>>, ~listed, fetches)
    provider : Provider() <- dynamicProvider("dyn", fetch)
    +models : Collection() <- IO.pure(Collection(), Images.setProvider(Error(), empty, provider))
    before : List<&2, Model()> <- Images.getModels(Error(), models, Some{"dyn"})
    first : Chan(Result<&2, &2, Resolve.ModelsError, Unit>) <- IO.fork(Result<&2, &2, Resolve.ModelsError, Unit>, Images.refresh(Error(), models, Some{"dyn"}))
    second : Chan(Result<&2, &2, Resolve.ModelsError, Unit>) <- IO.fork(Result<&2, &2, Resolve.ModelsError, Unit>, Images.refresh(Error(), models, Some{"dyn"}))
    a : Result<&2, &2, Resolve.ModelsError, Unit> <- IO.join(Result<&2, &2, Resolve.ModelsError, Unit>, first)
    b : Result<&2, &2, Resolve.ModelsError, Unit> <- IO.join(Result<&2, &2, Resolve.ModelsError, Unit>, second)
    count : Nat <- Ref.read(Nat, fetches)
    found : Maybe<&2, Model()> <- Images.getModel(Error(), models, "dyn", "listed")
    failing : Images.RefreshImagesModels() <- C.create(~Unit, ~Unit, ~Result<&2, &2, String, List<&2, Model()>>, ~flaky, Unit{})
    flakyProvider : Provider() <- dynamicProvider("flaky", failing)
    +withFlaky : Collection() <- IO.pure(Collection(), Images.setProvider(Error(), models, flakyProvider))
    rejected : Result<&2, &2, Resolve.ModelsError, Unit> <- Images.refresh(Error(), withFlaky, Some{"flaky"})
    all : Result<&2, &2, Resolve.ModelsError, Unit> <- Images.refresh(Error(), withFlaky, None{})
    expect("supports dynamic providers via refresh with in-flight dedupe", modelIds(before) ++ "|" ++ Nat.show(count) ++ "|" ++ maybeModel(found) ++ "|" ++ errorCode(rejected) ++ "|" ++ errorCode(all), "|1|listed|model_source:Model refresh failed for flaky: fetch failed|resolved")

def allOpenRouter(models: List<&2, Model()>) -> Bool:
  match models:
    case Nil{}: True{}
    case T.ImagesModel{_, _, api, _, _, _, _, _, _, _, _, _, _} <> rest: String.eq(api, "openrouter-images") && allOpenRouter(rest)

def builtins() -> IO(Unit):
  do IO<Unit>:
    store : Auth.CredentialStore <- emptyStore()
    context : Auth.AuthContext <- fakeAuthContext(vars([R.Property{"OPENROUTER_API_KEY", "or-key"}]))
    api : Images.ProviderImages(Error()) <- okApi()
    +models : Collection() <- All.builtinImagesModels(Error(), store, context, api)
    +list : List<&2, Model()> <- Images.getModels(Error(), models, Some{"openrouter"})
    auth : Resolve.Resolution() <- Images.getAuth(Error(), models, "openrouter", Resolve.noOverrides())
    expect("builtinImagesModels registers the openrouter provider with its catalog", String.join(providerIds(Images.getProviders(Error(), models)), ",") ++ "|" ++ Bool.pick(String, List.is_empty(&2, Model(), list), "empty", "listed") ++ "|" ++ Bool.pick(String, allOpenRouter(list), "openrouter-images", "other") ++ "|" ++ authKey(auth), "openrouter|listed|openrouter-images|or-key")

def main() -> IO(Unit):
  do IO<Unit>:
    registersProviders()
    resolvesAuth()
    mergesEnv()
    unknownProviders()
    refreshes()
    builtins()

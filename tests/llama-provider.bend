import Base
import ./loopback-fetch.bend as Network
import ../packages/coding-agent/src/extensions/llama/provider.bend as Llama
import ../packages/coding-agent/src/extensions/llama/client.bend as Client
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/models.bend as Models
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/model-json.bend as ModelJson
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/ai/src/utils/json.bend as Encode
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V

def checked(-A: Data, result: Result<&2, &2, String, A>) -> IO(A):
  match result:
    case Done{value}: IO.pure(A, value)
    case Fail{error}: IO.die(A, 1, error)

def printModels(values: List<&2, Llama.Model()>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case model <> rest:
      do IO<Unit>:
        IO.print(Maybe.default(&2, String, Encode.stringify(SchemaJson.toJson(ModelJson.model(model))), "invalid model"))
        printModels(rest)

def catalog(value: Result<&2, &2, Json.ParseError, V.Value>) -> IO(List<&2, Client.LlamaModelInfo>):
  match value:
    case Fail{_}: IO.die(List<&2, Client.LlamaModelInfo>, 1, "invalid fixture JSON")
    case Done{json}: checked(List<&2, Client.LlamaModelInfo>, Client.catalog(json))

def envValue(values: R.Record<String>, name: String) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, R.get(String, values, name))
def exists(unused: Unit, path: String) -> IO(Bool): IO.pure(Bool, False{})
def context(values: R.Record<String>) -> IO(Auth.AuthContext):
  do IO<Auth.AuthContext>:
    env : C.Callback<String, Maybe<&2, String>> <- C.create(~R.Record<String>, ~String, ~Maybe<&2, String>, ~envValue, values)
    file : C.Callback<String, Bool> <- C.create(~Unit, ~String, ~Bool, ~exists, Unit{})
    return Auth.AuthContext{env, file}

def prompt(base: String, question: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>):
  match question:
    case Auth.TextPrompt{message, placeholder, _}:
      do IO<Result<&2, &2, String, String>>:
        IO.print("prompt|" ++ message ++ "|" ++ Maybe.default(&2, String, placeholder, "-"))
        return Done{base ++ "/v1/"}
    case Auth.SecretPrompt{message, _, _}:
      do IO<Result<&2, &2, String, String>>:
        IO.print("prompt|" ++ message ++ "|-")
        return Done{" key "}
    case _: IO.pure(Result<&2, &2, String, String>, Fail{"unexpected prompt"})
def notify(unused: Unit, event: Auth.AuthEvent) -> IO(Unit): IO.pure(Unit, Unit{})

def printCredential(value: Auth.Credential) -> IO(Unit):
  match value:
    case Auth.ApiKeyCredential{key, env}: IO.print("credential|" ++ Maybe.default(&2, String, key, "-") ++ "|" ++ Maybe.default(&2, String, R.get(String, Maybe.default(&2, R.Record<String>, env, R.new(String)), "LLAMA_BASE_URL"), "-"))
    case _: IO.die(Unit, 1, "unexpected OAuth credential")

def loginCase(transport: Llama.Transport, +base: String, +signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  do IO<Unit>:
    +ask : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~String, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~prompt, base)
    +event : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Unit, ~Auth.AuthEvent, ~Unit, ~notify, Unit{})
    result : Auth.LoginOutcome() <- Llama.login(transport, Auth.ProviderAuthInteraction{signal, ask, event})
    credential : Auth.Credential <- checked(Auth.Credential, result)
    printCredential(credential)
    C.dispose(Auth.AuthPrompt, Result<&2, &2, String, String>, ask)
    C.dispose(Auth.AuthEvent, Unit, event)

def published(unused: Unit, publication: Models.ModelsPublication) -> IO(Bool):
  match publication:
    case Models.ModelsPublication{_, Some{models}}:
      do IO<Bool>:
        printModels(models)
        return True{}
    case _: IO.pure(Bool, True{})

def refreshCase(transport: Llama.Transport, base: String, +signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  do IO<Unit>:
    +callback : C.Callback<Models.ModelsPublication, Bool> <- C.create(~Unit, ~Models.ModelsPublication, ~Bool, ~published, Unit{})
    value : Result<&2, &2, String, Unit> <- Llama.refresh(transport, Models.RefreshModelsContext{Some{Auth.ApiKeyCredential{Some{"local"}, Some{R.Record{[R.Property{"LLAMA_BASE_URL", base}]}}}}, None{}, callback, True{}, None{}, signal})
    checked(Unit, value)
    C.dispose(Models.ModelsPublication, Bool, callback)

def resolution(value: Auth.AuthOutcome()) -> IO(Unit):
  match value:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{None{}}: IO.print("none")
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{key, _, url}, _, source}}}: IO.print("auth|" ++ Maybe.default(&2, String, key, "-") ++ "|" ++ Maybe.default(&2, String, url, "-") ++ "|" ++ Maybe.default(&2, String, source, "-"))

def exercise(+transport: Llama.Transport, +base: String, mode: String, data: String, +env: Auth.AuthContext, +signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  match mode:
    case "login": loginCase(transport, base, signal)
    case "resolve":
      do IO<Unit>:
        result : Auth.AuthOutcome() <- Llama.resolve(transport, Auth.ResolveInput{env, None{}, signal})
        resolution(result)
    case "refresh": refreshCase(transport, base, signal)
    case "thinking": refreshCase(transport, base, signal)
    case other:
      do IO<Unit>:
        models : List<&2, Client.LlamaModelInfo> <- catalog(Json.parse(data))
        printModels(Llama.catalogModels(models, base, String.eq(other, "autoload")))

def run(+base: String, mode: String, data: String, fetch: Fetch.Fetch(Unit)) -> IO(Unit):
  do IO<Unit>:
    +env : Auth.AuthContext <- context(R.Record{[R.Property{"LLAMA_BASE_URL", base}, R.Property{"LLAMA_API_KEY", "env-key"}]})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    exercise(Llama.Transport{fetch, Network.urlContext(), env}, base, mode, data, env, Abort.signal(Unit, controller))
    Abort.dispose(Unit, controller)
    Auth.disposeContext(env)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case base <> mode <> data <> Nil{}: Network.withNetwork(fetch => run(base, mode, data, fetch))
    case _: IO.die(Unit, 1, "usage: llama-provider <base> <mode> <catalog>")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

import Base
import ./loopback-fetch.bend as Network
import ../packages/coding-agent/src/extensions/llama/client.bend as Llama
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V


def checked(-A: Data, result: Result<&2, &2, String, A>) -> IO(A):
  match result:
    case Done{value}: IO.pure(A, value)
    case Fail{error}: IO.die(A, 1, error)

def expect(+label: String, valid: Bool) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), valid, _ => IO.print(label), _ => IO.die(Unit, 1, "failed: " ++ label))(Unit{})

def normalized(input: String, +expected: String) -> IO(Unit):
  do IO<Unit>:
    result : String <- checked(String, Llama.normalizeLlamaServerUrl(Network.urlContext(), input))
    expect("url " ++ expected, String.eq(result, expected))

def rejected(-A: Data, result: Result<&2, &2, String, A>) -> Bool:
  match result:
    case Fail{_}: True{}
    case Done{_}: False{}

def modelsValid(result: List<&2, Llama.LlamaModelInfo>) -> Bool:
  match result:
    case Llama.LlamaModelInfo{"qwen", Some{"alias" <> Nil{}}, Llama.Status{Llama.Loaded{}, Some{"server" <> Nil{}}, Some{False{}}, None{}, None{}}, Some{Llama.Architecture{Some{"text" <> "image" <> Nil{}}, None{}}}, Some{"preset"}, Some{Llama.Metadata{Some{_}, Some{_}, None{}, Some{"Q4"}}}} <> Nil{}: True{}
    case _: False{}

def propsValid(result: Llama.LlamaServerProps) -> Bool:
  match result:
    case Llama.LlamaServerProps{Some{True{}}, Some{"enable_thinking"}}: True{}
    case _: False{}

def errorText(-A: Data, result: Result<&2, &2, String, A>) -> String:
  match result:
    case Fail{error}: error
    case Done{_}: "unexpected success"

def run(+base: String, +fetch: Fetch.Fetch(Unit)) -> IO(Unit):
  do IO<Unit>:
    normalized(" http://127.0.0.1:8080/v1/ ", "http://127.0.0.1:8080")
    normalized("https://EXAMPLE.com/prefix/v1?secret=gone#gone", "https://example.com/prefix")
    expect("reject protocol", rejected(String, Llama.normalizeLlamaServerUrl(Network.urlContext(), "file:///tmp/llama")))
    +client : Llama.LlamaClient <- checked(Llama.LlamaClient, Llama.create(fetch, Network.urlContext(), base ++ "/v1/", Some{"test-key"}))
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +signal : Abort.AbortSignal<Unit> <- IO.pure(Abort.AbortSignal<Unit>, Abort.signal(Unit, controller))
    listed : Result<&2, &2, String, List<&2, Llama.LlamaModelInfo>> <- Llama.list(client, False{}, signal)
    models : List<&2, Llama.LlamaModelInfo> <- checked(List<&2, Llama.LlamaModelInfo>, listed)
    expect("typed catalog", modelsValid(models))
    reload : Result<&2, &2, String, List<&2, Llama.LlamaModelInfo>> <- Llama.list(client, True{}, signal)
    reloaded : List<&2, Llama.LlamaModelInfo> <- checked(List<&2, Llama.LlamaModelInfo>, reload)
    expect("reloaded catalog", modelsValid(reloaded))
    properties : Result<&2, &2, String, Llama.LlamaServerProps> <- Llama.props(client, Some{"qwen + coder"}, signal)
    props : Llama.LlamaServerProps <- checked(Llama.LlamaServerProps, properties)
    expect("typed props", propsValid(props))
    loaded : Result<&2, &2, String, Unit> <- Llama.load(client, "qwen\"\\雪", signal)
    checked(Unit, loaded)
    unloaded : Result<&2, &2, String, Unit> <- Llama.unloadAndWait(client, "qwen", signal)
    checked(Unit, unloaded)
    downloaded : Result<&2, &2, String, Unit> <- Llama.download(client, "owner/model:Q4", signal)
    checked(Unit, downloaded)
    failure : Llama.LlamaClient <- checked(Llama.LlamaClient, Llama.create(fetch, Network.urlContext(), base ++ "/failure", None{}))
    failed : Result<&2, &2, String, List<&2, Llama.LlamaModelInfo>> <- Llama.list(failure, False{}, signal)
    expect("server error", String.eq(errorText(List<&2, Llama.LlamaModelInfo>, failed), "router unavailable"))
    aborted : Bool <- Abort.abort(Unit, controller, None{})
    expect("abort settled", aborted)
    cancelled : Result<&2, &2, String, List<&2, Llama.LlamaModelInfo>> <- Llama.list(client, False{}, signal)
    expect("cancelled", rejected(List<&2, Llama.LlamaModelInfo>, cancelled))
    Abort.dispose(Unit, controller)
    IO.print("llama management requests passed")

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case base <> Nil{}: Network.withNetwork(fetch => run(base, fetch))
    case _: IO.die(Unit, 1, "usage: llama-client <base>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

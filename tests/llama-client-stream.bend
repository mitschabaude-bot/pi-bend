import Base
import ./loopback-fetch.bend as Network
import ../packages/coding-agent/src/extensions/llama/client.bend as Llama
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/f64.bend as F

# The fixture prints typed progress and result values; Python compares them
# with the pinned client and also checks that SSE connections close on exit.
def progressText(value: Llama.LlamaProgress) -> String:
  match value:
    case Llama.LlamaProgress{message, ratio, detail}:
      message ++ "|" ++ Maybe.default(&2, String, Maybe.map(&2, F64, String, value => F64.show(value), ratio), "-") ++ "|" ++ Maybe.default(&2, String, detail, "-")

def progress(log: Ref.Ref<List<&2, String>>, value: Llama.LlamaProgress) -> IO(Unit):
  +text = progressText(value)
  Ref.modify(List<&2, String>, Unit, log, lines => (List.append(&2, String, lines, [text]), Unit{}))

def checked(-A: Data, value: Result<&2, &2, String, A>) -> IO(A):
  match value:
    case Done{result}: IO.pure(A, result)
    case Fail{error}: IO.die(A, 1, error)

def modelText(value: Llama.LlamaModelInfo) -> String:
  match value:
    case Llama.LlamaModelInfo{id, _, Llama.Status{Llama.Loaded{}, _, _, _, _}, _, _, _}: id ++ "|loaded"
    case Llama.LlamaModelInfo{id, _, Llama.Status{Llama.Unloaded{}, _, _, _, _}, _, _, _}: id ++ "|unloaded"
    case _: "unexpected status"

def modelsText(values: List<&2, Llama.LlamaModelInfo>) -> String:
  match values:
    case Nil{}: ""
    case item <> rest: modelText(item) ++ "\n" ++ modelsText(rest)

def lines(values: List<&2, String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        IO.print(text)
        lines(rest)

def abortedAfter(+controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(150)
    settled : Bool <- Abort.abort(Unit, controller, None{})
    return Unit{}

def errorText(-A: Data, value: Result<&2, &2, String, A>) -> String:
  match value:
    case Fail{error}: "error|" ++ error
    case Done{_}: "unexpected success"

def exercise(mode: String, +client: Llama.LlamaClient, +callback: C.Callback<Llama.LlamaProgress, Unit>, +controller: Abort.AbortController<Unit>) -> IO(Unit):
  match mode:
    case "download":
      do IO<Unit>:
        result : Result<&2, &2, String, List<&2, Llama.LlamaModelInfo>> <- Llama.downloadAndWait(client, "owner/repo:Q4_K_M", callback, Abort.signal(Unit, controller))
        models : List<&2, Llama.LlamaModelInfo> <- checked(List<&2, Llama.LlamaModelInfo>, result)
        IO.print(String.trim(modelsText(models)))
    case "failure":
      do IO<Unit>:
        result : Result<&2, &2, String, Llama.LlamaModelInfo> <- Llama.loadAndWait(client, "test-model", callback, Abort.signal(Unit, controller))
        IO.print(errorText(Llama.LlamaModelInfo, result))
    case "cancel":
      do IO<Unit>:
        task : Chan(Unit) <- IO.fork(Unit, abortedAfter(controller))
        result : Result<&2, &2, String, Llama.LlamaModelInfo> <- Llama.loadAndWait(client, "test-model", callback, Abort.signal(Unit, controller))
        IO.join(Unit, task)
        IO.print(errorText(Llama.LlamaModelInfo, result))
    case _:
      do IO<Unit>:
        result : Result<&2, &2, String, Llama.LlamaModelInfo> <- Llama.loadAndWait(client, "test-model", callback, Abort.signal(Unit, controller))
        model : Llama.LlamaModelInfo <- checked(Llama.LlamaModelInfo, result)
        IO.print(modelText(model))

def run(base: String, mode: String, fetch: Fetch.Fetch(Unit)) -> IO(Unit):
  do IO<Unit>:
    +client : Llama.LlamaClient <- checked(Llama.LlamaClient, Llama.create(fetch, Network.urlContext(), base, Some{"test-key"}))
    +log : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, Nil{})
    +callback : C.Callback<Llama.LlamaProgress, Unit> <- C.create(~Ref.Ref<List<&2, String>>, ~Llama.LlamaProgress, ~Unit, ~progress, log)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    exercise(mode, client, callback, controller)
    C.dispose(Llama.LlamaProgress, Unit, callback)
    Abort.dispose(Unit, controller)
    reports : List<&2, String> <- Ref.dispose(List<&2, String>, log)
    lines(reports)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case base <> mode <> Nil{}: Network.withNetwork(fetch => run(base, mode, fetch))
    case _: IO.die(Unit, 1, "usage: llama-client-stream <base> <mode>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

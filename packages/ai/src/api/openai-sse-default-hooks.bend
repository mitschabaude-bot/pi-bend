import Base
import ./openai-sse-reader.bend as SSE
import ./openai-sse-json.bend as Json
import ../../../runtime/src/json-string.bend as StringJSON
import ../../../runtime/src/callback.bend as C

# Defaults for the owning native body reader. Both SDK diagnostic targets use
# stderr by default. Native diagnostics render raw lines as a JSON string list,
# preserving their contents/order without reproducing a JS object inspector.
def quoted(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case first <> rest: StringJSON.quote(first) <> quoted(rest)

def raw(lines: List<&2, String>) -> String:
  "[" ++ String.join(quoted(lines), ",") ++ "]"

def messages(error: Json.Error) -> List<&2, String>:
  match error:
    case Json.InvalidJson{_, data, lines, _}:
      ("Could not parse message into JSON: " ++ data) <> ("From chunk: " ++ raw(lines)) <> Nil{}
    case Json.ApiErrorPayload{_}: Nil{}

def print(lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print_err(first)
        print(rest)

# The scoped source closes its owned body/fetch scope before notifying this
# hook. No independent controller remains to cancel, and the caller's signal
# must never be aborted as a side effect of iterator closure.
def abort(environment: Unit, unused: Unit) -> IO(Unit): IO.pure(Unit, Unit{})

def diagnostic(~E: Data, environment: Unit, error: Json.Error) -> IO(Result<&2, &2, SSE.ReadError<E>, Unit>):
  do IO<Result<&2, &2, SSE.ReadError<E>, Unit>>:
    print(messages(error))
    return Done{Unit{}}

type Owner<-E: Data> is Type:
  Owner{hooks: SSE.Hooks<E>}

def create(~E: Data) -> IO(Owner<E>):
  do IO<Owner<E>>:
    cancel : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~abort, Unit{})
    report : C.Callback<Json.Error, Result<&2, &2, SSE.ReadError<E>, Unit>> <- C.create(~Unit, ~Json.Error, ~Result<&2, &2, SSE.ReadError<E>, Unit>, ~(diagnostic(~E)), Unit{})
    return Owner{SSE.Hooks{cancel, report}}

def borrow(-E: Data, owner: Owner<E>) -> Owner<E> & SSE.Hooks<E>:
  match owner:
    case Owner{+hooks}: (Owner{hooks}, hooks)

# Call after body processing has stopped borrowing both callbacks. The default
# retains no diagnostic history; the decoder supplies only its current block.
def dispose(-E: Data, owner: Owner<E>) -> IO(Unit):
  match owner:
    case Owner{SSE.Hooks{cancel, report}}:
      do IO<Unit>:
        C.dispose(Json.Error, Result<&2, &2, SSE.ReadError<E>, Unit>, report)
        C.dispose(Unit, Unit, cancel)

import Base
import ../src/api/openai-responses-fetch.bend as Fetch
import ../src/api/openai-responses-envelope.bend as Envelope
import ../../runtime/src/http-fetch-scope.bend as Scope
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/http-response-metadata.bend as Metadata
import ../../runtime/src/http-head.bend as Head
import ../../runtime/src/http-status.bend as Status
import ../../runtime/src/url-record.bend as URL
import ../../runtime/src/url-scheme.bend as Scheme
import ../../runtime/src/url-host.bend as Host
import ../../runtime/src/headers.bend as Headers
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/f64.bend as F
import ../../runtime/src/callback.bend as C

# The supplied transports return a closed body: full open-body lifetime and
# error/cleanup ordering are exercised by runtime/test/http-fetch-scope.bend.
def fetched(label: String, input: Fetch.Input<String>) -> IO(Result<&2, &1, String, Response.Response<Unit>>):
  match input:
    case Fetch.Input{_, method, _, body, _}:
      do IO<Result<&2, &1, String, Response.Response<Unit>>>:
        IO.print(label ++ ":" ++ method ++ ":" ++ body)
        return Done{Response.Response{Metadata.fromHead(Head.ResponseHead{Status.StatusLine{1, 1, 200, Nil{}}, Nil{}}, False{}), Response.Closed{Some{Nil{}}}}}

def request(mode: String) -> Envelope.Request:
  Envelope.Request{URL.URL{Scheme.Https{}, "", "", Some{Host.Domain{"example.invalid"}}, None{}, URL.Hierarchical{"responses" <> Nil{}}, None{}, None{}}, "post", Headers.new(), "{\"stream\":true}", Bool.pick(F.F64, String.eq(mode, "invalid"), F.fromBits(1106247680, 0), F.fromU32(600000))}

def show(result: Result<&2, &1, Fetch.Error<String, String>, Response.Response<Scope.State<String, Unit>>>) -> IO(Unit):
  match result:
    case Fail{Fetch.InvalidTimeout{_}}: IO.print("invalid-timeout")
    case Fail{Fetch.FetchFailure{Scope.Aborted{_}}}: IO.print("aborted")
    case Done{Response.Response{_, Response.Closed{_}}}: IO.print("closed")
    case _: IO.die(Unit, 1, "unexpected fetch result")

def pre(mode: String, parent: Abort.AbortController<String>) -> IO(Unit):
  match mode:
    case "pre":
      do IO<Unit>:
        won : Bool <- Abort.abort(String, parent, Some{"stop"})
        return Unit{}
    case _: IO.pure(Unit, Unit{})

def run(+mode: String) -> IO(Unit):
  do IO<Unit>:
    +parent : Abort.AbortController<String> <- Abort.new(String)
    +native : C.Callback<Fetch.Input<String>, Result<&2, &1, String, Response.Response<Unit>>> <- C.create(~String, ~Fetch.Input<String>, ~Result<&2, &1, String, Response.Response<Unit>>, ~fetched, "native")
    +custom : C.Callback<Fetch.Input<String>, Result<&2, &1, String, Response.Response<Unit>>> <- C.create(~String, ~Fetch.Input<String>, ~Result<&2, &1, String, Response.Response<Unit>>, ~fetched, "custom")
    pre(mode, parent)
    result : Result<&2, &1, Fetch.Error<String, String>, Response.Response<Scope.State<String, Unit>>> <- Fetch.run(String, String, Unit, request(mode), Abort.signal(String, parent), Fetch.choose(String, String, Unit, native, Bool.pick(Maybe<&2, C.Callback<Fetch.Input<String>, Result<&2, &1, String, Response.Response<Unit>>>>, String.eq(mode, "native"), None{}, Some{custom})))
    show(result)
    # Caller-owned callbacks remain valid and are retired only by their caller.
    C.dispose(Fetch.Input<String>, Result<&2, &1, String, Response.Response<Unit>>, native)
    C.dispose(Fetch.Input<String>, Result<&2, &1, String, Response.Response<Unit>>, custom)
    Abort.dispose(String, parent)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> Nil{}: run(mode)
    case _: IO.die(Unit, 1, "mode required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

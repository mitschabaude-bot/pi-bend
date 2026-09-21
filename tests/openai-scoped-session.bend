import Base
import ../packages/ai/src/api/openai-responses-scoped-session.bend as ScopedSession
import ../packages/ai/src/api/openai-responses-session.bend as Session
import ../packages/ai/src/api/openai-responses-lifecycle.bend as Life
import ../packages/ai/src/api/openai-responses-scoped-reader.bend as Reader
import ../packages/ai/src/api/openai-body-responses-reader.bend as BodyReader
import ../packages/ai/src/api/openai-responses-cleartext-attempt.bend as Attempt
import ../packages/ai/src/api/openai-responses-stream.bend as Stream
import ../packages/ai/src/api/openai-responses-stream-pricing.bend as Pricing
import ../packages/ai/src/api/openai-sse-reader.bend as SSE
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/http-fetch-scope.bend as Scope
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-buffered-body.bend as Body
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/test/utf8-runner.bend as Text
import ./openai-scoped-responses-reader.bend as Source
import ./openai-provider-driver.bend as Display
import ./openai-provider-session.bend as Observe

# Fixture error renderings only; the production adapters retain typed causes.
def processingText(value: Maybe<&2, String>) -> String:
  match value:
    case Some{text}: text
    case None{}: "processing"

def processing(value: Stream.Error<String>) -> String: processingText(Display.processingError(Some{value}))

def disposal(value: BodyReader.CloseError<Reader.TransportError(String)>) -> String: "cleanup"
def releaseError(value: Progress.Error<Attempt.ReadError(String)>) -> String: "release"

def acquired(value: Result<&2, &1, Scope.Error<String, String>, Response.Response<Attempt.State(String)>>) -> Result<&2, &1, String, Response.Response<Attempt.State(String)>>:
  match value:
    case Fail{_}: Fail{"fetch"}
    case Done{owner}: Done{owner}

def prepared(port: U32, signal: A.AbortSignal<String>, value: Result<&2, &2, Request.RequestError, Request.Prepared>) -> IO(Result<&2, &1, String, Response.Response<Attempt.State(String)>>):
  match value:
    case Fail{_}: IO.pure(Result<&2, &1, String, Response.Response<Attempt.State(String)>>, Fail{"prepare"})
    case Done{request}:
      do IO<Result<&2, &1, String, Response.Response<Attempt.State(String)>>>:
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        result : Result<&2, &1, Scope.Error<String, String>, Response.Response<Attempt.State(String)>> <- Scope.start(String, String, Attempt.Transport(String), 1000, signal, child => Source.dispatch(socket, request, child))
        return acquired(result)

def acquire(port: U32, signal: A.AbortSignal<String>) -> IO(Result<&2, &1, String, Response.Response<Attempt.State(String)>>):
  prepared(port, signal, Request.prepare("GET", "/sse", Headers.appendField(Headers.new(), Header.Header{"host", "localhost"}), Body.Absent{}))

def model() -> T.Model<T.JsonValue>:
  T.Model{"test", "Test", T.OpenAIResponsesApi{}, "openai", "http://localhost", False{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{F.fromU32(1000000), F.fromU32(2000000), F.fromU32(3000000), F.fromU32(4000000), None{}}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}

def run(port: U32) -> IO(Unit):
  do IO<Unit>:
    +controller : A.AbortController<String> <- A.new(String)
    +hooks : SSE.Hooks<Reader.TransportError(String)> <- Source.createHooks(controller)
    +signal : C.Callback<Unit, Bool> <- C.create(~A.AbortController<String>, ~Unit, ~Bool, ~Display.aborted, controller)
    owner : Session.Run<V.Value, Unit, String> <- ScopedSession.start(~String, ~Unit, ~String, ~Source.mapError, ~Display.identity, Life.initial(V.Value, Unit, T.JsonValue, model(), F.fromU32(123)), signal, acquire(port, A.signal(String, controller)), model(), Pricing.defaultOptions(String), hooks, False{}, processing, disposal, releaseError)
    Observe.observe(Session.borrow(V.Value, Unit, String, owner))
    C.dispose(Unit, Bool, signal)
    Source.retireHooks(hooks)
    A.dispose(String, controller)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case port <> Nil{}: run(Text.decimal(port, 0))
    case _: IO.die(Unit, 1, "expected port")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

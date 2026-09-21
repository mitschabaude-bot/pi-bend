import Base
import ./openai-responses-envelope.bend as Envelope
import ../../../runtime/src/url-record.bend as URL
import ../../../runtime/src/headers.bend as Headers
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/timer-milliseconds.bend as Duration
import ../../../runtime/src/http-fetch-scope.bend as Scope
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/callback.bend as C

type Input<-Reason: Data> is Data:
  Input{url: URL.URL, method: String, headers: Headers.Headers, body: String, signal: Abort.AbortSignal<Deadline.Cause<Reason>>}

type Error<-Reason: Data, -E: Data> is Data:
  InvalidTimeout{cause: Duration.Error}
  FetchFailure{cause: Scope.Error<Reason, E>}

def input(-Reason: Data, request: Envelope.Request, signal: Abort.AbortSignal<Deadline.Cause<Reason>>) -> Input<Reason>:
  match request:
    case Envelope.Request{url, method, headers, body, _}:
      Input{url, String.to_upper(method), headers, body, signal}

def timeout(request: Envelope.Request) -> Result<&2, &2, Duration.Error, U32>:
  match request:
    case Envelope.Request{_, _, _, _, milliseconds}: Duration.milliseconds(milliseconds)

# Both callbacks are borrowed. The caller gives native and custom transports
# the same explicit response-owner interface; neither is called during choice.
def choose(-Reason: Data, -E: Data, -Transport: Type, native: C.Callback<Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>>, custom: Maybe<&2, C.Callback<Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>>>) -> C.Callback<Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>>:
  match custom:
    case None{}: native
    case Some{fetch}: fetch

def dispatch(-Reason: Data, -E: Data, -Transport: Type, fetch: C.Callback<Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>>, request: Envelope.Request, signal: Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Result<&2, &1, E, Response.Response<Transport>>):
  C.call(Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>, fetch, input(Reason, request, signal))

def acquired(-Reason: Data, -E: Data, -Transport: Type, result: Result<&2, &1, Scope.Error<Reason, E>, Response.Response<Scope.State<Reason, Transport>>>) -> Result<&2, &1, Error<Reason, E>, Response.Response<Scope.State<Reason, Transport>>>:
  match result:
    case Fail{cause}: Fail{FetchFailure{cause}}
    case Done{response}: Done{response}

def validated(-Reason: Data, -E: Data, -Transport: Type, request: Envelope.Request, parent: Abort.AbortSignal<Reason>, fetch: C.Callback<Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>>, duration: Result<&2, &2, Duration.Error, U32>) -> IO(Result<&2, &1, Error<Reason, E>, Response.Response<Scope.State<Reason, Transport>>>):
  match duration:
    case Fail{cause}: IO.pure(Result<&2, &1, Error<Reason, E>, Response.Response<Scope.State<Reason, Transport>>>, Fail{InvalidTimeout{cause}})
    case Done{milliseconds}:
      do IO<Result<&2, &1, Error<Reason, E>, Response.Response<Scope.State<Reason, Transport>>>>:
        result : Result<&2, &1, Scope.Error<Reason, E>, Response.Response<Scope.State<Reason, Transport>>> <- Scope.start(Reason, E, Transport, milliseconds, parent, signal => dispatch(Reason, E, Transport, fetch, request, signal))
        return acquired(Reason, E, Transport, result)

# The envelope already contains the hook-selected, serialized payload. Hooks,
# HTTP status interpretation and retries remain in their surrounding layers.
def run(-Reason: Data, -E: Data, -Transport: Type, +request: Envelope.Request, parent: Abort.AbortSignal<Reason>, fetch: C.Callback<Input<Reason>, Result<&2, &1, E, Response.Response<Transport>>>) -> IO(Result<&2, &1, Error<Reason, E>, Response.Response<Scope.State<Reason, Transport>>>):
  validated(Reason, E, Transport, request, parent, fetch, timeout(request))

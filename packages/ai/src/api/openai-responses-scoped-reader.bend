import Base
import ./openai-body-responses-reader.bend as Body
import ./openai-responses-reader.bend as Reader
import ./openai-responses-cleartext-attempt.bend as Attempt
import ./openai-http-errors.bend as Errors
import ./openai-sse-reader.bend as SSE
import ../../../runtime/src/http-body-source.bend as Source
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response-stream.bend as Stream
import ../../../runtime/src/http-fetch-scope.bend as Scope
import ../../../runtime/src/http-exchange-response.bend as HTTP
import ../../../runtime/src/http-socket-exchange.bend as Exchange
import ../../../runtime/src/deadline.bend as Deadline

def TransportError(-Reason: Data) -> Data:
  Errors.TransportError(Deadline.Cause<Reason>)

def read(-Reason: Data, state: Attempt.State(Reason)) -> IO(Attempt.State(Reason) & Result<&2, &2, Attempt.ReadError(Reason), Maybe<&2, Stream.Event>>):
  Scope.read(Reason, Attempt.ReadError(Reason), Attempt.Transport(Reason), HTTP.read(Deadline.Cause<Reason>), state)

def close(-Reason: Data, state: Attempt.State(Reason)) -> IO(Result<&2, &2, Attempt.ReadError(Reason), Unit>):
  Scope.close(Reason, Attempt.ReadError(Reason), Attempt.Transport(Reason), Exchange.close(Deadline.Cause<Reason>), state)

# The source owns the fetch scope along with its transport. Its final release
# closes transport before disposing the retained caller-cancellation scope.
# Header deadlines have already been disarmed by successful acquisition.
def create(~Reason: Data, ~E: Data, ~map: Reader.Error<TransportError(Reason)> -> E, body: Response.Body<Attempt.State(Reason)>, hooks: SSE.Hooks<TransportError(Reason)>, synthesize: Bool) -> IO(Body.Owner<Attempt.State(Reason), TransportError(Reason), E>):
  do IO<Body.Owner<Attempt.State(Reason), TransportError(Reason), E>>:
    source : Source.Owner<Attempt.State(Reason), SSE.ReadError<TransportError(Reason)>> <- Source.create(~Attempt.ReadError(Reason), ~Attempt.State(Reason), ~SSE.ReadError<TransportError(Reason)>, ~(Errors.classify(Deadline.Cause<Reason>)), ~(read(Reason)), ~(close(Reason)), body)
    Body.fromSource(~Attempt.State(Reason), ~TransportError(Reason), ~E, ~map, source, hooks, synthesize)

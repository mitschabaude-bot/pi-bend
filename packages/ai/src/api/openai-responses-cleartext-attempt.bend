import Base
import ./openai-responses-attempt.bend as Attempt
import ./openai-responses-native-error.bend as Policy
import ./openai-responses-cleartext-fetch.bend as Native
import ./openai-responses-fetch.bend as Fetch
import ./openai-responses-envelope.bend as Envelope
import ../utils/provider-retry.bend as Retry
import ../../../runtime/src/http-fetch-scope.bend as Scope
import ../../../runtime/src/http-socket-exchange.bend as Exchange
import ../../../runtime/src/http-exchange-response.bend as Reader
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/callback.bend as C

def Transport(-Reason: Data) -> Type: Exchange.Exchange<Deadline.Cause<Reason>>
def State(-Reason: Data) -> Type: Scope.State<Reason, Transport(Reason)>
def ReadError(-Reason: Data) -> Data: Exchange.ReadError<Deadline.Cause<Reason>>
def Error(-Reason: Data, -SourceError: Data) -> Data: Attempt.Error<Reason, Native.Error<Reason, SourceError>, ReadError(Reason)>
def FetchResult(-Reason: Data, -SourceError: Data) -> Type: Result<&2, &1, Native.Error<Reason, SourceError>, Response.Response<Transport(Reason)>>
def Outcome(-Reason: Data, -SourceError: Data) -> Type: Result<&2, &1, Retry.RequestFailure<Error(Reason, SourceError)>, Response.Response<State(Reason)>>

# The native fetch callback and resolver remain caller-owned across retries
# and returned bodies. This layer performs exactly one cleartext HTTP attempt;
# caller hooks, retry budgets/delays and response streaming remain composable.
def run(~Reason: Data, ~SourceError: Data, request: Envelope.Request, parent: Abort.AbortSignal<Reason>, fetch: C.Callback<Fetch.Input<Reason>, FetchResult(Reason, SourceError)>, diagnosticLimit: Nat) -> IO(Outcome(Reason, SourceError)):
  Attempt.run(~Reason, ~(Native.Error<Reason, SourceError>), ~(ReadError(Reason)), ~(Transport(Reason)), ~(Reader.read(Deadline.Cause<Reason>)), ~(Exchange.close(Deadline.Cause<Reason>)), request, parent, fetch, Policy.classify(Reason, SourceError), diagnosticLimit)

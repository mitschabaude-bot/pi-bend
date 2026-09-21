import Base
import ./openai-responses-cleartext-attempt.bend as Attempt
import ./openai-responses-envelope.bend as Envelope
import ./openai-responses-fetch.bend as Fetch
import ../utils/provider-retry.bend as Retry
import ../utils/provider-retry-map.bend as Map
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C

# This request callback plugs into openai-responses-acquire.run. It owns no
# resolver or fetch callback: those and the parent signal are borrowed. Embed
# the native attempt error into the surrounding provider/session error domain.
def Outcome(-Reason: Data, -E: Data) -> Type:
  Result<&2, &1, Retry.RequestFailure<E>, Response.Response<Attempt.State(Reason)>>

type Environment<-Reason: Data, -SourceError: Data> is Data:
  Environment{parent: Abort.AbortSignal<Reason>, fetch: C.Callback<Fetch.Input<Reason>, Attempt.FetchResult(Reason, SourceError)>, diagnosticLimit: Nat}

def invoke(~Reason: Data, ~SourceError: Data, ~E: Data, ~embed: Attempt.Error(Reason, SourceError) -> E, environment: Environment<Reason, SourceError>, request: Envelope.Request) -> IO(Outcome(Reason, E)):
  match environment:
    case Environment{parent, fetch, diagnosticLimit}:
      do IO<Outcome(Reason, E)>:
        value : Attempt.Outcome(Reason, SourceError) <- Attempt.run(~Reason, ~SourceError, request, parent, fetch, diagnosticLimit)
        return Map.result(Attempt.Error(Reason, SourceError), E, Response.Response<Attempt.State(Reason)>, embed, value)

# Dispose this callback after acquisition/retries finish. Returned bodies own
# their transport state independently; borrowed fetch/resolver/signal owners
# must follow their own documented lifetimes through response consumption.
def create(~Reason: Data, ~SourceError: Data, ~E: Data, ~embed: Attempt.Error(Reason, SourceError) -> E, parent: Abort.AbortSignal<Reason>, fetch: C.Callback<Fetch.Input<Reason>, Attempt.FetchResult(Reason, SourceError)>, diagnosticLimit: Nat) -> IO(C.Callback<Envelope.Request, Outcome(Reason, E)>):
  C.create(~Environment<Reason, SourceError>, ~Envelope.Request, ~Outcome(Reason, E), ~(invoke(~Reason, ~SourceError, ~E, ~embed)), Environment{parent, fetch, diagnosticLimit})

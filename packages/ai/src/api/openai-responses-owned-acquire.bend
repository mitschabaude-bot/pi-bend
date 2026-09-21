import Base
import ../types.bend as T
import ./openai-responses-payload-plan.bend as Plan
import ./openai-responses-prepare.bend as Preparation
import ./openai-responses-prepared-acquire.bend as Ready
import ./openai-responses-cleartext-system-runtime.bend as System
import ./openai-responses-cleartext-runtime.bend as Runtime
import ./openai-responses-cleartext-attempt.bend as Attempt
import ./openai-responses-cleartext-request.bend as Request
import ./openai-responses-configured-acquire.bend as Acquire
import ./openai-responses-native-session.bend as Native
import ./openai-responses-native-session-error.bend as Errors
import ./openai-responses-scoped-process.bend as Process
import ./openai-responses-envelope.bend as Envelope
import ./openai-request-headers.bend as Headers
import ../utils/provider-owned-acquire.bend as Owned
import ../utils/provider-request.bend as ProviderRequest
import ../utils/provider-response-view.bend as View
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/http-resolved-exchange.bend as HTTP
import ../../../runtime/src/url-absolute.bend as URL

def Inner(-Reason: Data, -Hook: Data) -> Data: Errors.Error<Reason, System.SourceError(), Hook>
def Error(-Reason: Data, -Hook: Data) -> Data: Owned.Error<System.Error, Inner(Reason, Hook)>
def Owner(-Reason: Data) -> Type: Owned.Owner<System.Owner<Reason>, Ready.Owner<Attempt.State(Reason)>>

type Context is Data:
  Context{url: URL.Context, headers: Headers.Defaults, files: System.Files, transport: HTTP.Options, diagnosticLimit: Nat}

# Payload selection has completed before this function can borrow a runtime.
# The inner acquisition still owns its request bridge and response hook policy.
def borrowed(~Reason: Data, ~Hook: Data, ~Telemetry: Data, ~Fetch: Data, context: Context, +parent: Abort.AbortSignal<Reason>, model: T.Model<T.JsonValue>, plan: Plan.Wire<Reason, System.SourceError(), Hook>, pair: System.Owner<Reason> & Runtime.Borrowed<Reason, System.SourceError()>) -> IO(System.Owner<Reason> & Result<&2, &1, Inner(Reason, Hook), Ready.Owner<Attempt.State(Reason)>>):
  match context plan pair:
    case Context{_, _, _, _, limit} Plan.Wire{original, wire, responseHook, retryOptions} Tuple{owner, Runtime.Borrowed{fetch, retry}}:
      do IO<System.Owner<Reason> & Result<&2, &1, Inner(Reason, Hook), Ready.Owner<Attempt.State(Reason)>>>:
        +request : C.Callback<Envelope.Request, Request.Outcome(Reason, Inner(Reason, Hook))> <- Request.create(~Reason, ~(System.SourceError()), ~(Inner(Reason, Hook)), ~(Errors.attempt(Reason, System.SourceError(), Hook)), parent, fetch, limit)
        result : Result<&2, &1, ProviderRequest.Error<Inner(Reason, Hook)>, Response.Response<Attempt.State(Reason)>> <- ProviderRequest.prepared(~Reason, ~Envelope.Request, ~(T.Model<T.JsonValue>), ~(Inner(Reason, Hook)), ~(Response.Response<Attempt.State(Reason)>), model, responseHook, request, retry, retryOptions, View.inspect(Attempt.State(Reason)), Process.release(Reason, Inner(Reason, Hook), Errors.release(Reason, System.SourceError(), Hook)), Done{wire})
        C.dispose(Envelope.Request, Request.Outcome(Reason, Inner(Reason, Hook)), request)
        return (owner, Ready.acquired(Inner(Reason, Hook), Attempt.State(Reason), original, Native.acquired(Reason, System.SourceError(), Hook, Acquire.completed(Inner(Reason, Hook), Attempt.State(Reason), result))))

def acquire(~Reason: Data, ~Hook: Data, ~Telemetry: Data, ~Fetch: Data, context: Context, parent: Abort.AbortSignal<Reason>, model: T.Model<T.JsonValue>, plan: Plan.Wire<Reason, System.SourceError(), Hook>, owner: System.Owner<Reason>) -> IO(System.Owner<Reason> & Result<&2, &1, Inner(Reason, Hook), Ready.Owner<Attempt.State(Reason)>>):
  borrowed(~Reason, ~Hook, ~Telemetry, ~Fetch, context, parent, model, plan, System.borrow(Reason, owner))

def initialized(~Reason: Data, context: Context) -> IO(Result<&2, &1, System.Error, System.Owner<Reason>>):
  match context:
    case Context{_, _, files, transport, _}: System.create(~Reason, files, transport)

def prepared(-Reason: Data, -Hook: Data, -Telemetry: Data, -Fetch: Data, context: Context, model: T.Model<T.JsonValue>, options: Native.Options(Reason, System.SourceError(), Hook, Telemetry, Fetch), result: Result<&2, &2, Preparation.Error, Preparation.Prepared>) -> IO(Result<&2, &2, Inner(Reason, Hook), Plan.Wire<Reason, System.SourceError(), Hook>>):
  match context result:
    case _ Fail{cause}: IO.pure(Result<&2, &2, Inner(Reason, Hook), Plan.Wire<Reason, System.SourceError(), Hook>>, Fail{Errors.PreparationFailure{cause}})
    case Context{url, headers, _, _, _} Done{original}:
      do IO<Result<&2, &2, Inner(Reason, Hook), Plan.Wire<Reason, System.SourceError(), Hook>>>:
        selected : Result<&2, &2, Inner(Reason, Hook), Plan.Plan<Reason, System.SourceError(), Hook, Telemetry, Fetch>> <- Plan.prepare(Reason, System.SourceError(), Hook, Telemetry, Fetch, model, original, options)
        Plan.seal(Reason, System.SourceError(), Hook, Telemetry, Fetch, url, headers, selected)

def prepare(-Reason: Data, -Hook: Data, -Telemetry: Data, -Fetch: Data, context: Context, model: T.Model<T.JsonValue>, options: Native.Options(Reason, System.SourceError(), Hook, Telemetry, Fetch), preparation: IO(Result<&2, &2, Preparation.Error, Preparation.Prepared>)) -> IO(Result<&2, &2, Inner(Reason, Hook), Plan.Wire<Reason, System.SourceError(), Hook>>):
  do IO<Result<&2, &2, Inner(Reason, Hook), Plan.Wire<Reason, System.SourceError(), Hook>>>:
    result : Result<&2, &2, Preparation.Error, Preparation.Prepared> <- preparation
    prepared(Reason, Hook, Telemetry, Fetch, context, model, options, result)

def run(~Reason: Data, ~Hook: Data, ~Telemetry: Data, ~Fetch: Data, +context: Context, +parent: Abort.AbortSignal<Reason>, +model: T.Model<T.JsonValue>, options: Native.Options(Reason, System.SourceError(), Hook, Telemetry, Fetch), preparation: IO(Result<&2, &2, Preparation.Error, Preparation.Prepared>)) -> IO(Result<&2, &1, Error(Reason, Hook), Owner(Reason)>):
  Owned.run(Plan.Wire<Reason, System.SourceError(), Hook>, System.Error, Inner(Reason, Hook), System.Owner<Reason>, Ready.Owner<Attempt.State(Reason)>, prepare(Reason, Hook, Telemetry, Fetch, context, model, Native.withSignal(Reason, System.SourceError(), Hook, Telemetry, Fetch, parent, options), preparation), initialized(~Reason, context), acquire(~Reason, ~Hook, ~Telemetry, ~Fetch, context, parent, model), System.dispose(Reason))

def release(-Reason: Data, -Hook: Data, owner: Owner(Reason)) -> IO(Result<&2, &2, Inner(Reason, Hook), Unit>):
  Owned.release(Inner(Reason, Hook), System.Owner<Reason>, Ready.Owner<Attempt.State(Reason)>, Ready.release(Inner(Reason, Hook), Attempt.State(Reason), Process.release(Reason, Inner(Reason, Hook), Errors.release(Reason, System.SourceError(), Hook))), System.dispose(Reason), owner)

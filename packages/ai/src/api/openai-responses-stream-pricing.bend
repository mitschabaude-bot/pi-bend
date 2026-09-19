import Base
import ../types.bend as T
import ./openai-responses-terminal.bend as Terminal
import ./openai-responses-stream-state.bend as Stream
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/callback.bend as Callback

type ServiceTierRequest is Data:
  ServiceTierRequest{responseServiceTier: Maybe<&2, String>, requestServiceTier: Maybe<&2, String>}

type PricingRequest is Data:
  PricingRequest{usage: T.Usage, serviceTier: Maybe<&2, String>}

# Callbacks are borrowed. Their owner keeps them alive through finalization and
# disposes them after the stream; no callback is captured in returned state.
# An immutable Usage return replaces the upstream callback's in-place update.
type OpenAIResponsesStreamOptions<-E: Data> is Data:
  OpenAIResponsesStreamOptions{serviceTier: Maybe<&2, String>, grammarToolInputProperties: Maybe<&2, R.Record<String>>, resolveServiceTier: Maybe<&2, Callback.Callback<ServiceTierRequest, Result<&2, &2, E, Maybe<&2, String>>>>, applyServiceTierPricing: Maybe<&2, Callback.Callback<PricingRequest, Result<&2, &2, E, T.Usage>>>}

def defaultOptions(-E: Data) -> OpenAIResponsesStreamOptions<E>:
  OpenAIResponsesStreamOptions{None{}, None{}, None{}, None{}}

type Error<-E: Data> is Data:
  TerminalFailure{error: Terminal.Error}
  ResolveServiceTierFailure{error: E}
  ApplyServiceTierPricingFailure{error: E}

type Update<-G: Data, -E: Data> is Data:
  Update{state: Stream.State<G>, error: Maybe<&2, Error<E>>}

def terminalUpdate(-G: Data, -E: Data, update: Terminal.Update<G>) -> Update<G, E>:
  match update:
    case Terminal.Update{state, None{}}: Update{state, None{}}
    case Terminal.Update{state, Some{error}}: Update{state, Some{TerminalFailure{error}}}

def priced(-G: Data, -E: Data, +state: Stream.State<G>, status: Maybe<&2, String>, reason: Maybe<&2, String>, result: Result<&2, &2, E, T.Usage>) -> Update<G, E>:
  match result:
    case Fail{error}: Update{state, Some{ApplyServiceTierPricingFailure{error}}}
    case Done{usage}: terminalUpdate(G, E, Terminal.finish(G, Terminal.withOutput(G, state, Terminal.withUsage(G, Stream.output(G, state), usage)), status, reason))

def resolved(-G: Data, -E: Data, +state: Stream.State<G>, status: Maybe<&2, String>, reason: Maybe<&2, String>, pricing: Callback.Callback<PricingRequest, Result<&2, &2, E, T.Usage>>, result: Result<&2, &2, E, Maybe<&2, String>>) -> IO(Update<G, E>):
  match result:
    case Fail{error}: IO.pure(Update<G, E>, Update{state, Some{ResolveServiceTierFailure{error}}})
    case Done{tier}:
      do IO<Update<G, E>>:
        usage : Result<&2, &2, E, T.Usage> <- Callback.call(PricingRequest, Result<&2, &2, E, T.Usage>, pricing, PricingRequest{Terminal.getUsage(G, Stream.output(G, state)), tier})
        return priced(G, E, state, status, reason, usage)

def resolve(-E: Data, response: Maybe<&2, String>, requested: Maybe<&2, String>, callback: Maybe<&2, Callback.Callback<ServiceTierRequest, Result<&2, &2, E, Maybe<&2, String>>>>) -> IO(Result<&2, &2, E, Maybe<&2, String>>):
  match callback:
    case None{}: IO.pure(Result<&2, &2, E, Maybe<&2, String>>, Done{Terminal.resolveServiceTier(response, requested)})
    case Some{value}: Callback.call(ServiceTierRequest, Result<&2, &2, E, Maybe<&2, String>>, value, ServiceTierRequest{response, requested})

def apply(-G: Data, -E: Data, state: Stream.State<G>, status: Maybe<&2, String>, reason: Maybe<&2, String>, responseTier: Maybe<&2, String>, options: OpenAIResponsesStreamOptions<E>) -> IO(Update<G, E>):
  match options:
    # Upstream does not invoke a resolver unless there is also a pricing hook.
    case OpenAIResponsesStreamOptions{_, _, _, None{}}: IO.pure(Update<G, E>, terminalUpdate(G, E, Terminal.finish(G, state, status, reason)))
    case OpenAIResponsesStreamOptions{requested, _, resolver, Some{pricing}}:
      do IO<Update<G, E>>:
        tier : Result<&2, &2, E, Maybe<&2, String>> <- resolve(E, responseTier, requested, resolver)
        resolved(G, E, state, status, reason, pricing, tier)

def prepared(-G: Data, -E: Data, status: Maybe<&2, String>, reason: Maybe<&2, String>, responseTier: Maybe<&2, String>, options: OpenAIResponsesStreamOptions<E>, update: Terminal.Update<G>) -> IO(Update<G, E>):
  match update:
    case Terminal.Update{state, Some{error}}: IO.pure(Update<G, E>, Update{state, Some{TerminalFailure{error}}})
    case Terminal.Update{state, None{}}: apply(G, E, state, status, reason, responseTier, options)

def finalizeResponse(-G: Data, -E: Data, state: Stream.State<G>, response: Terminal.Response, cost: T.ModelCost, options: OpenAIResponsesStreamOptions<E>) -> IO(Update<G, E>):
  match response:
    case Terminal.Response{id, +status, +reason, output, usage, +tier}:
      prepared(G, E, status, reason, tier, options, Terminal.prepare(G, state, Terminal.Response{id, status, reason, output, usage, tier}, cost))

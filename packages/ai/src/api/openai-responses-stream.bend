import Base
import ../types.bend as T
import ./openai-responses-stream-content.bend as Content
import ./openai-responses-stream-state.bend as Stream
import ./openai-responses-terminal.bend as Terminal
import ./openai-responses-stream-pricing.bend as Pricing
import ./constrained-sampling.bend as Sampling
import ../utils/cost.bend as Cost
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/callback.bend as Callback

# JSON/SSE decoding supplies typed wire events. Unknown provider event kinds
# have no content effect but still pass through the asynchronous reader.
type ResponseStreamEvent is Data:
  ContentEvent{value: Stream.ContentEvent}
  ResponseCreated{id: String}
  ResponseCompleted{response: Terminal.Response}
  ResponseIncomplete{response: Terminal.Response}
  ResponseFailed{status: Maybe<&2, String>, error: Maybe<&2, Terminal.ProviderError>, reason: Maybe<&2, String>}
  ResponseError{code: Maybe<&2, String>, message: String}
  IgnoredEvent{}

# One acquired async iteration. close models iterator.return on an early
# processor failure; EOF and a rejected next call do not invoke it. Handles are
# borrowed and remain caller-owned even after the iteration has been closed.
type Reader<-E: Data> is Data:
  Reader{next: Callback.Callback<Unit, Result<&2, &2, E, Maybe<&2, ResponseStreamEvent>>>, close: Callback.Callback<Unit, Result<&2, &2, E, Unit>>}

type Error<-E: Data> is Data:
  ReadFailure{error: E}
  EmitFailure{error: E}
  ContentFailure{error: Sampling.Error}
  TerminalFailure{error: Terminal.Error}
  ResolveServiceTierFailure{error: E}
  ApplyServiceTierPricingFailure{error: E}

type RunResult<-G: Data, -E: Data> is Data:
  RunResult{output: T.AssistantMessage<V.Value, G>, error: Maybe<&2, Error<E>>}

type RunState<-G: Data> is Data:
  RunState{content: Stream.State<G>, sawTerminalResponse: Bool}

type Step<-G: Data, -E: Data> is Data:
  Step{state: RunState<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, error: Maybe<&2, Error<E>>}

def finishRun(-G: Data, -E: Data, state: RunState<G>, error: Maybe<&2, Error<E>>) -> RunResult<G, E>:
  match state:
    case RunState{content, _}: RunResult{Stream.output(G, content), error}

def contentStep(-G: Data, -E: Data, terminal: Bool, update: Stream.Update<G>) -> Step<G, E>:
  match update:
    case Stream.Update{state, events, None{}}: Step{RunState{state, terminal}, events, None{}}
    case Stream.Update{state, events, Some{error}}: Step{RunState{state, terminal}, events, Some{ContentFailure{error}}}

def terminalStep(-G: Data, -E: Data, update: Terminal.Update<G>) -> Step<G, E>:
  match update:
    case Terminal.Update{state, None{}}: Step{RunState{state, True{}}, Nil{}, None{}}
    case Terminal.Update{state, Some{error}}: Step{RunState{state, True{}}, Nil{}, Some{TerminalFailure{error}}}

def pricingError(-E: Data, error: Pricing.Error<E>) -> Error<E>:
  match error:
    case Pricing.TerminalFailure{value}: TerminalFailure{value}
    case Pricing.ResolveServiceTierFailure{value}: ResolveServiceTierFailure{value}
    case Pricing.ApplyServiceTierPricingFailure{value}: ApplyServiceTierPricingFailure{value}

def pricingStep(-G: Data, -E: Data, update: Pricing.Update<G, E>) -> Step<G, E>:
  match update:
    case Pricing.Update{state, None{}}: Step{RunState{state, True{}}, Nil{}, None{}}
    case Pricing.Update{state, Some{error}}: Step{RunState{state, True{}}, Nil{}, Some{pricingError(E, error)}}

def finalize(-G: Data, -E: Data, state: Stream.State<G>, response: Terminal.Response, cost: T.ModelCost, options: Pricing.OpenAIResponsesStreamOptions<E>) -> IO(Step<G, E>):
  do IO<Step<G, E>>:
    update : Pricing.Update<G, E> <- Pricing.finalizeResponse(G, E, state, response, cost, options)
    return pricingStep(G, E, update)

def step(-G: Data, -E: Data, state: RunState<G>, event: ResponseStreamEvent, cost: T.ModelCost, options: Pricing.OpenAIResponsesStreamOptions<E>) -> IO(Step<G, E>):
  match state event:
    case RunState{content, terminal} ContentEvent{value}: IO.pure(Step<G, E>, contentStep(G, E, terminal, Stream.step(G, content, value)))
    case RunState{+content, terminal} ResponseCreated{id}: IO.pure(Step<G, E>, Step{RunState{Terminal.withOutput(G, content, Terminal.withResponseId(G, Stream.output(G, content), Some{id})), terminal}, Nil{}, None{}})
    case RunState{content, _} ResponseCompleted{response}: finalize(G, E, content, response, cost, options)
    case RunState{content, _} ResponseIncomplete{response}: finalize(G, E, content, response, cost, options)
    case RunState{content, _} ResponseFailed{status, error, reason}: IO.pure(Step<G, E>, terminalStep(G, E, Terminal.failed(G, content, status, error, reason)))
    case value ResponseError{code, message}: IO.pure(Step<G, E>, Step{value, Nil{}, Some{TerminalFailure{Terminal.streamError(code, message)}}})
    case value IgnoredEvent{}: IO.pure(Step<G, E>, Step{value, Nil{}, None{}})

def eventSnapshot(-G: Data, event: T.AssistantMessageEvent<V.Value, G>) -> T.AssistantMessage<V.Value, G>:
  match event:
    case T.Start{message}: message
    case T.TextStart{_, message}: message
    case T.TextDelta{_, _, message}: message
    case T.TextEnd{_, _, message}: message
    case T.ThinkingStart{_, message}: message
    case T.ThinkingDelta{_, _, message}: message
    case T.ThinkingEnd{_, _, message}: message
    case T.ToolcallStart{_, message}: message
    case T.ToolcallDelta{_, _, message}: message
    case T.ToolcallEnd{_, _, message}: message
    case T.StreamDone{_, message}: message
    case T.StreamError{_, message}: message

# A failed sink can interrupt a two-event item completion. Return the snapshot
# at that emission, not the reducer's already-computed later namespace/content.
def deliveryResult(-G: Data, -E: Data, event: T.AssistantMessageEvent<V.Value, G>, result: Result<&2, &2, E, Unit>) -> Result<&2, &2, RunResult<G, E>, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{RunResult{eventSnapshot(G, event), Some{EmitFailure{error}}}}

def deliver(-G: Data, -E: Data, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, +sink: Callback.Callback<T.AssistantMessageEvent<V.Value, G>, Result<&2, &2, E, Unit>>, previous: Result<&2, &2, RunResult<G, E>, Unit>) -> IO(Result<&2, &2, RunResult<G, E>, Unit>):
  match events previous:
    case _ Fail{failure}: IO.pure(Result<&2, &2, RunResult<G, E>, Unit>, Fail{failure})
    case Nil{} Done{_}: IO.pure(Result<&2, &2, RunResult<G, E>, Unit>, Done{Unit{}})
    case +head <> rest Done{_}:
      do IO<Result<&2, &2, RunResult<G, E>, Unit>>:
        result : Result<&2, &2, E, Unit> <- Callback.call(T.AssistantMessageEvent<V.Value, G>, Result<&2, &2, E, Unit>, sink, head)
        deliver(G, E, rest, sink, deliveryResult(G, E, head, result))

type Decision<-G: Data, -E: Data> is Data:
  Continue{state: RunState<G>}
  Finished{result: RunResult<G, E>, close: Bool}

def delivered(-G: Data, -E: Data, state: RunState<G>, error: Maybe<&2, Error<E>>, delivery: Result<&2, &2, RunResult<G, E>, Unit>) -> Decision<G, E>:
  match error delivery:
    case _ Fail{failure}: Finished{failure, True{}}
    case Some{failure} Done{_}: Finished{finishRun(G, E, state, Some{failure}), True{}}
    case None{} Done{_}: Continue{state}

def publish(-G: Data, -E: Data, sink: Callback.Callback<T.AssistantMessageEvent<V.Value, G>, Result<&2, &2, E, Unit>>, next: Step<G, E>) -> IO(Decision<G, E>):
  match next:
    case Step{state, events, error}:
      do IO<Decision<G, E>>:
        result : Result<&2, &2, RunResult<G, E>, Unit> <- deliver(G, E, events, sink, Done{Unit{}})
        return delivered(G, E, state, error, result)

def exhausted(-G: Data, -E: Data, state: RunState<G>) -> Decision<G, E>:
  match state:
    case RunState{content, True{}}: Finished{RunResult{Stream.output(G, content), None{}}, False{}}
    case RunState{content, False{}}: Finished{RunResult{Stream.output(G, content), Some{TerminalFailure{Terminal.MissingTerminalResponse{}}}}, False{}}

def received(-G: Data, -E: Data, state: RunState<G>, sink: Callback.Callback<T.AssistantMessageEvent<V.Value, G>, Result<&2, &2, E, Unit>>, cost: T.ModelCost, options: Pricing.OpenAIResponsesStreamOptions<E>, result: Result<&2, &2, E, Maybe<&2, ResponseStreamEvent>>) -> IO(Decision<G, E>):
  match result:
    case Fail{error}: IO.pure(Decision<G, E>, Finished{finishRun(G, E, state, Some{ReadFailure{error}}), False{}})
    case Done{None{}}: IO.pure(Decision<G, E>, exhausted(G, E, state))
    case Done{Some{event}}:
      do IO<Decision<G, E>>:
        next : Step<G, E> <- step(G, E, state, event, cost, options)
        publish(G, E, sink, next)

def read(-E: Data, source: Reader<E>) -> IO(Result<&2, &2, E, Maybe<&2, ResponseStreamEvent>>):
  match source:
    case Reader{next, _}: Callback.call(Unit, Result<&2, &2, E, Maybe<&2, ResponseStreamEvent>>, next, Unit{})

def closeIteration(-G: Data, -E: Data, source: Reader<E>, result: RunResult<G, E>, close: Bool) -> IO(RunResult<G, E>):
  match source close:
    case _ False{}: IO.pure(RunResult<G, E>, result)
    case Reader{_, cleanup} True{}:
      do IO<RunResult<G, E>>:
        # AsyncIteratorClose preserves an existing throw if return also fails.
        ignored : Result<&2, &2, E, Unit> <- Callback.call(Unit, Result<&2, &2, E, Unit>, cleanup, Unit{})
        return result

# The external async iterator determines termination. Like the generic event
# stream, this loop has no artificial event/fuel limit.
@unsafe def loop(-G: Data, -E: Data, +source: Reader<E>, +sink: Callback.Callback<T.AssistantMessageEvent<V.Value, G>, Result<&2, &2, E, Unit>>, +cost: T.ModelCost, +options: Pricing.OpenAIResponsesStreamOptions<E>, decision: Decision<G, E>) -> IO(RunResult<G, E>):
  match decision:
    case Finished{result, close}: closeIteration(G, E, source, result, close)
    case Continue{state}:
      do IO<RunResult<G, E>>:
        result : Result<&2, &2, E, Maybe<&2, ResponseStreamEvent>> <- read(E, source)
        next : Decision<G, E> <- received(G, E, state, sink, cost, options, result)
        loop(G, E, source, sink, cost, options, next)

def grammarProperties(-E: Data, options: Pricing.OpenAIResponsesStreamOptions<E>) -> R.Record<String>:
  match options:
    case Pricing.OpenAIResponsesStreamOptions{_, Some{properties}, _, _}: properties
    case _: R.new(String)

def processResponsesStream(-G: Data, -E: Data, -J: Data, source: Reader<E>, output: T.AssistantMessage<V.Value, G>, sink: Callback.Callback<T.AssistantMessageEvent<V.Value, G>, Result<&2, &2, E, Unit>>, model: T.Model<J>, +options: Pricing.OpenAIResponsesStreamOptions<E>) -> IO(RunResult<G, E>):
  loop(G, E, source, sink, Cost.modelCost(J, model), options, Continue{RunState{Stream.create(G, output, grammarProperties(E, options)), False{}}})

import Base
import ../../src/api/openai-responses-shared.bend as Shared
import ../../src/api/openai-responses-stream.bend as D
import ../../src/api/openai-responses-stream-pricing.bend as Pricing
import ../../src/api/openai-responses-terminal.bend as Terminal
import ../../src/api/constrained-sampling.bend as Sampling
import ../../src/types.bend as T
import ../../src/utils/json.bend as Json
import ../../src/utils/schema-json.bend as SchemaJson
import ./responses-stream-content.bend as Content
import ./responses-stream-state.bend as State
import ./responses-terminal.bend as TerminalTest
import ./responses-messages.bend as Fixture
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/callback.bend as Cb
import ../../../runtime/test/schema.bend as A

type Mode is Data:
  NoHooks{}
  ResolverOnly{}
  PriceOnly{}
  Both{}
  ResolverFails{}
  PricingFails{}
  ReadFails{index: Nat}
  SinkFails{index: Nat}
  CloseFails{index: Nat}

type Capture is Data:
  Capture{remaining: List<&2, D.ResponseStreamEvent>, reads: Nat, emits: Nat, reversed: List<&2, V.Value>}

type Environment is Data:
  Environment{capture: Ref.Ref<Capture>, mode: Mode}

def readFailure(mode: Mode, index: Nat) -> Bool:
  match mode:
    case ReadFails{at}: Nat.is_eq(at, index)
    case _: False{}

def sinkFailure(mode: Mode, index: Nat) -> Bool:
  match mode:
    case SinkFails{at}: Nat.is_eq(at, index)
    case CloseFails{at}: Nat.is_eq(at, index)
    case _: False{}

def readValue(remaining: List<&2, D.ResponseStreamEvent>, failed: Bool) -> Result<&2, &2, String, Maybe<&2, D.ResponseStreamEvent>>:
  match remaining failed:
    case _ True{}: Fail{"read failed"}
    case Nil{} False{}: Done{None{}}
    case head <> _ False{}: Done{Some{head}}

def tail(events: List<&2, D.ResponseStreamEvent>) -> List<&2, D.ResponseStreamEvent>:
  match events:
    case Nil{}: Nil{}
    case _ <> rest: rest

def readStep(mode: Mode, state: Capture) -> Capture & Result<&2, &2, String, Maybe<&2, D.ResponseStreamEvent>>:
  match state:
    case Capture{+remaining, +reads, emits, trace}: (Capture{tail(remaining), 1n+reads, emits, V.Text{"read"} <> trace}, readValue(remaining, readFailure(mode, reads)))

def readCallback(env: Environment, unused: Unit) -> IO(Result<&2, &2, String, Maybe<&2, D.ResponseStreamEvent>>):
  match env:
    case Environment{capture, mode}: Ref.modify(Capture, Result<&2, &2, String, Maybe<&2, D.ResponseStreamEvent>>, capture, state => readStep(mode, state))

def sinkStep(mode: Mode, event: T.AssistantMessageEvent<V.Value, Unit>, state: Capture) -> Capture & Result<&2, &2, String, Unit>:
  match state:
    case Capture{remaining, reads, +emits, trace}: (Capture{remaining, reads, 1n+emits, V.ObjectValue{R.Record{R.Property{"emit", State.event(event)} <> Nil{}}} <> trace}, Bool.pick(Result<&2, &2, String, Unit>, sinkFailure(mode, emits), Fail{"sink failed"}, Done{Unit{}}))

def sinkCallback(env: Environment, event: T.AssistantMessageEvent<V.Value, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match env:
    case Environment{capture, mode}: Ref.modify(Capture, Result<&2, &2, String, Unit>, capture, state => sinkStep(mode, event, state))

def logged(state: Capture, value: V.Value) -> Capture & Unit:
  match state:
    case Capture{remaining, reads, emits, trace}: (Capture{remaining, reads, emits, value <> trace}, Unit{})

def log(capture: Ref.Ref<Capture>, value: V.Value) -> IO(Unit):
  Ref.modify(Capture, Unit, capture, state => logged(state, value))

def closeResult(mode: Mode) -> Result<&2, &2, String, Unit>:
  match mode:
    case CloseFails{_}: Fail{"close failed"}
    case _: Done{Unit{}}

def closeCallback(env: Environment, unused: Unit) -> IO(Result<&2, &2, String, Unit>):
  match env:
    case Environment{capture, mode}:
      do IO<Result<&2, &2, String, Unit>>:
        log(capture, V.Text{"close"})
        return closeResult(mode)

def optionalText(value: Maybe<&2, String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{text}: V.Text{text}

def resolverTrace(request: Pricing.ServiceTierRequest) -> V.Value:
  match request:
    case Pricing.ServiceTierRequest{response, requested}: V.ObjectValue{R.Record{R.Property{"resolve", V.ArrayValue{optionalText(response) <> optionalText(requested) <> Nil{}}} <> Nil{}}}

def resolverResult(mode: Mode) -> Result<&2, &2, String, Maybe<&2, String>>:
  match mode:
    case ResolverFails{}: Fail{"resolver failed"}
    case _: Done{Some{"resolved"}}

def resolveCallback(env: Environment, request: Pricing.ServiceTierRequest) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match env:
    case Environment{capture, mode}:
      do IO<Result<&2, &2, String, Maybe<&2, String>>>:
        log(capture, resolverTrace(request))
        return resolverResult(mode)

def pricedUsage(value: T.Usage) -> T.Usage:
  match value:
    case T.Usage{_, output, read, write, longWrite, reasoning, total, T.UsageCost{inputPrice, outputPrice, readPrice, writePrice, _}}:
      T.Usage{F.fromU32(777), output, read, write, longWrite, reasoning, total, T.UsageCost{inputPrice, outputPrice, readPrice, writePrice, F.fromU32(123)}}

def pricingTrace(request: Pricing.PricingRequest) -> V.Value:
  match request:
    case Pricing.PricingRequest{usage, tier}: V.ObjectValue{R.Record{R.Property{"price", V.ObjectValue{R.Record{R.Property{"usage", TerminalTest.encodeUsage(usage)} <> R.Property{"tier", optionalText(tier)} <> Nil{}}}} <> Nil{}}}

def pricingResult(mode: Mode, request: Pricing.PricingRequest) -> Result<&2, &2, String, T.Usage>:
  match mode request:
    case PricingFails{} _: Fail{"pricing failed"}
    case _ Pricing.PricingRequest{usage, _}: Done{pricedUsage(usage)}

def priceHandler(env: Environment, +request: Pricing.PricingRequest) -> IO(Result<&2, &2, String, T.Usage>):
  match env:
    case Environment{capture, mode}:
      do IO<Result<&2, &2, String, T.Usage>>:
        log(capture, pricingTrace(request))
        return pricingResult(mode, request)

def priceCallback(env: Environment, request: Pricing.PricingRequest) -> IO(Result<&2, &2, String, T.Usage>):
  priceHandler(env, request)

def hasResolver(mode: Mode) -> Bool:
  match mode:
    case ResolverOnly{}: True{}
    case Both{}: True{}
    case ResolverFails{}: True{}
    case PricingFails{}: True{}
    case _: False{}

def hasPricing(mode: Mode) -> Bool:
  match mode:
    case PriceOnly{}: True{}
    case Both{}: True{}
    case ResolverFails{}: True{}
    case PricingFails{}: True{}
    case _: False{}

def errorText(error: D.Error<String>) -> String:
  match error:
    case D.ReadFailure{text}: text
    case D.EmitFailure{text}: text
    case D.ContentFailure{value}: Sampling.errorMessage(value)
    case D.TerminalFailure{value}: Terminal.errorMessage(value)
    case D.ResolveServiceTierFailure{text}: text
    case D.ApplyServiceTierPricingFailure{text}: text

def resultError(fields: R.Record<V.Value>, error: Maybe<&2, D.Error<String>>) -> V.Value:
  match error:
    case None{}: V.ObjectValue{fields}
    case Some{value}: V.ObjectValue{R.set(V.Value, fields, "error", V.Text{errorText(value)})}

def resultValue(result: D.RunResult<Unit, String>, capture: Capture) -> V.Value:
  match result capture:
    case D.RunResult{output, error} Capture{_, _, _, reversed}: resultError(R.Record{R.Property{"output", TerminalTest.snapshot(output)} <> R.Property{"trace", V.ArrayValue{List.reverse(&2, V.Value, reversed)}} <> Nil{}}, error)

type Execution is Data:
  Execution{result: D.RunResult<Unit, String>, capture: Capture}

def execute(events: List<&2, D.ResponseStreamEvent>, +mode: Mode, requested: Maybe<&2, String>, initial: T.AssistantMessage<V.Value, Unit>, model: T.Model<Unit>) -> IO(Execution):
  do IO<Execution>:
    +capture : Ref.Ref<Capture> <- Ref.new(Capture, Capture{events, 0n, 0n, Nil{}})
    +env : Environment = Environment{capture, mode}
    +reader : Cb.Callback<Unit, Result<&2, &2, String, Maybe<&2, D.ResponseStreamEvent>>> <- Cb.create(~Environment, ~Unit, ~Result<&2, &2, String, Maybe<&2, D.ResponseStreamEvent>>, ~readCallback, env)
    +close : Cb.Callback<Unit, Result<&2, &2, String, Unit>> <- Cb.create(~Environment, ~Unit, ~Result<&2, &2, String, Unit>, ~closeCallback, env)
    +sink : Cb.Callback<T.AssistantMessageEvent<V.Value, Unit>, Result<&2, &2, String, Unit>> <- Cb.create(~Environment, ~T.AssistantMessageEvent<V.Value, Unit>, ~Result<&2, &2, String, Unit>, ~sinkCallback, env)
    +resolver : Cb.Callback<Pricing.ServiceTierRequest, Result<&2, &2, String, Maybe<&2, String>>> <- Cb.create(~Environment, ~Pricing.ServiceTierRequest, ~Result<&2, &2, String, Maybe<&2, String>>, ~resolveCallback, env)
    +pricing : Cb.Callback<Pricing.PricingRequest, Result<&2, &2, String, T.Usage>> <- Cb.create(~Environment, ~Pricing.PricingRequest, ~Result<&2, &2, String, T.Usage>, ~priceCallback, env)
    options : Pricing.OpenAIResponsesStreamOptions<String> = Pricing.OpenAIResponsesStreamOptions{requested, None{}, Bool.pick(Maybe<&2, Cb.Callback<Pricing.ServiceTierRequest, Result<&2, &2, String, Maybe<&2, String>>>>, hasResolver(mode), Some{resolver}, None{}), Bool.pick(Maybe<&2, Cb.Callback<Pricing.PricingRequest, Result<&2, &2, String, T.Usage>>>, hasPricing(mode), Some{pricing}, None{})}
    result : D.RunResult<Unit, String> <- Shared.processResponsesStream(Unit, String, Unit, D.Reader{reader, close}, initial, sink, model, Some{options})
    Cb.dispose(Unit, Result<&2, &2, String, Maybe<&2, D.ResponseStreamEvent>>, reader)
    Cb.dispose(Unit, Result<&2, &2, String, Unit>, close)
    Cb.dispose(T.AssistantMessageEvent<V.Value, Unit>, Result<&2, &2, String, Unit>, sink)
    Cb.dispose(Pricing.ServiceTierRequest, Result<&2, &2, String, Maybe<&2, String>>, resolver)
    Cb.dispose(Pricing.PricingRequest, Result<&2, &2, String, T.Usage>, pricing)
    final : Capture <- Ref.dispose(Capture, capture)
    return Execution{result, final}

def checked(execution: Execution, expected: String, label: String) -> IO(Unit):
  match execution:
    case Execution{result, capture}: A.assertion(Content.encoded(Json.stringify(SchemaJson.toJson(resultValue(result, capture))), expected), label)

def check(events: List<&2, D.ResponseStreamEvent>, mode: Mode, requested: Maybe<&2, String>, expected: String, label: String) -> IO(Unit):
  do IO<Unit>:
    result : Execution <- execute(events, mode, requested, TerminalTest.initial(), Fixture.model(False{}, False{}, None{}))
    checked(result, expected, label)

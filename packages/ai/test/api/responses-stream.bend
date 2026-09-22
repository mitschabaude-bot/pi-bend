import Base
import ../../src/api/openai-responses-stream.bend as D
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
import ../../../runtime/test/schema.bend as A

# Drives processResponsesStream over an in-memory event list. The iterator
# state records every read, emission and close in order, so traces compare
# with the pinned upstream processor's observed effects.
type Mode is Data:
  NoHooks{}
  Priced{}
  ReadFails{index: Nat}
  SinkFails{index: Nat}
  CloseFails{index: Nat}

type Capture is Data:
  Capture{mode: Mode, remaining: List<&2, D.ResponseStreamEvent>, reads: Nat, emits: Nat, reversed: List<&2, V.Value>}

def Step() -> Type: Capture & Result<&2, &2, String, Maybe<&2, D.ResponseStreamEvent>>
def Effect() -> Type: Capture & Result<&2, &2, String, Unit>

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

def rest(events: List<&2, D.ResponseStreamEvent>) -> List<&2, D.ResponseStreamEvent>:
  match events:
    case Nil{}: Nil{}
    case _ <> tail: tail

def next(state: Capture) -> IO(Step()):
  match state:
    case Capture{+mode, +remaining, +reads, emits, trace}:
      IO.pure(Step(), (Capture{mode, rest(remaining), 1n+reads, emits, V.Text{"read"} <> trace}, readValue(remaining, readFailure(mode, reads))))

def emit(state: Capture, event: T.AssistantMessageEvent<V.Value, Unit>) -> IO(Effect()):
  match state:
    case Capture{+mode, remaining, reads, +emits, trace}:
      IO.pure(Effect(), (Capture{mode, remaining, reads, 1n+emits, V.ObjectValue{R.Record{R.Property{"emit", State.event(event)} <> Nil{}}} <> trace}, Bool.pick(Result<&2, &2, String, Unit>, sinkFailure(mode, emits), Fail{"sink failed"}, Done{Unit{}})))

def closeResult(mode: Mode) -> Result<&2, &2, String, Unit>:
  match mode:
    case CloseFails{_}: Fail{"close failed"}
    case _: Done{Unit{}}

def close(state: Capture) -> IO(Effect()):
  match state:
    case Capture{+mode, remaining, reads, emits, trace}: IO.pure(Effect(), (Capture{mode, remaining, reads, emits, V.Text{"close"} <> trace}, closeResult(mode)))

# Pure stand-ins for the upstream tier hooks: the resolver always answers
# "resolved" and pricing rewrites the input count and cost total.
def testResolve(response: Maybe<&2, String>, requested: Maybe<&2, String>) -> Maybe<&2, String>: Some{"resolved"}

def testPricing(-J: Data, model: T.Model<J>, serviceTier: Maybe<&2, String>, value: T.Usage) -> T.Usage:
  match value:
    case T.Usage{_, output, read, write, longWrite, reasoning, total, T.UsageCost{inputPrice, outputPrice, readPrice, writePrice, _}}:
      T.Usage{F.fromU32(777), output, read, write, longWrite, reasoning, total, T.UsageCost{inputPrice, outputPrice, readPrice, writePrice, F.fromU32(123)}}

def errorText(error: D.Error<String>) -> String:
  match error:
    case D.ReadFailure{text}: text
    case D.EmitFailure{text}: text
    case D.ContentFailure{value}: Sampling.errorMessage(value)
    case D.TerminalFailure{value}: D.terminalMessage(value)

def resultError(fields: R.Record<V.Value>, error: Maybe<&2, D.Error<String>>) -> V.Value:
  match error:
    case None{}: V.ObjectValue{fields}
    case Some{value}: V.ObjectValue{R.set(V.Value, fields, "error", V.Text{errorText(value)})}

def resultValue(result: D.RunResult<Unit, String>, capture: Capture) -> V.Value:
  match result capture:
    case D.RunResult{output, error} Capture{_, _, _, _, reversed}: resultError(R.Record{R.Property{"output", TerminalTest.snapshot(output)} <> R.Property{"trace", V.ArrayValue{List.reverse(&2, V.Value, reversed)}} <> Nil{}}, error)

type Execution is Data:
  Execution{result: D.RunResult<Unit, String>, capture: Capture}

def executed(pair: Capture & D.RunResult<Unit, String>) -> Execution:
  match pair:
    case (capture, result): Execution{result, capture}

def priced(mode: Mode) -> Bool:
  match mode:
    case Priced{}: True{}
    case _: False{}

def process(+pricing: Bool, source: Capture, initial: T.AssistantMessage<V.Value, Unit>, model: T.Model<Unit>, options: D.OpenAIResponsesStreamOptions) -> IO(Capture & D.RunResult<Unit, String>):
  match pricing:
    case True{}: D.processResponsesStream(~Capture, ~String, ~Unit, ~Unit, ~next, ~close, ~emit, ~testResolve, ~(testPricing(Unit)), source, initial, model, options)
    case False{}: D.processResponsesStream(~Capture, ~String, ~Unit, ~Unit, ~next, ~close, ~emit, ~D.defaultResolveServiceTier, ~(D.noServiceTierPricing(Unit)), source, initial, model, options)

def executeWithGrammar(events: List<&2, D.ResponseStreamEvent>, +mode: Mode, requested: Maybe<&2, String>, properties: Maybe<&2, R.Record<String>>, initial: T.AssistantMessage<V.Value, Unit>, model: T.Model<Unit>) -> IO(Execution):
  do IO<Execution>:
    pair : Capture & D.RunResult<Unit, String> <- process(priced(mode), Capture{mode, events, 0n, 0n, Nil{}}, initial, model, D.OpenAIResponsesStreamOptions{requested, Maybe.default(&2, R.Record<String>, properties, R.new(String))})
    return executed(pair)

def execute(events: List<&2, D.ResponseStreamEvent>, mode: Mode, requested: Maybe<&2, String>, initial: T.AssistantMessage<V.Value, Unit>, model: T.Model<Unit>) -> IO(Execution):
  executeWithGrammar(events, mode, requested, None{}, initial, model)

def checked(execution: Execution, expected: String, label: String) -> IO(Unit):
  match execution:
    case Execution{result, capture}: A.assertion(Content.encoded(Json.stringify(SchemaJson.toJson(resultValue(result, capture))), expected), label)

def check(events: List<&2, D.ResponseStreamEvent>, mode: Mode, requested: Maybe<&2, String>, expected: String, label: String) -> IO(Unit):
  do IO<Unit>:
    result : Execution <- execute(events, mode, requested, TerminalTest.initial(), Fixture.model(False{}, False{}, None{}))
    checked(result, expected, label)

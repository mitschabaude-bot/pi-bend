import Base
import ../../src/api/openai-responses-stream.bend as D
import ../../src/api/constrained-sampling.bend as Sampling
import ../../src/types.bend as T
import ../../src/utils/json.bend as Json
import ../../src/utils/schema-json.bend as SchemaJson
import ./responses-stream-content.bend as Content
import ./responses-stream-state.bend as State
import ./responses-messages.bend as Fixture
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/test/schema.bend as A

type Action is Data:
  ContentEvent{value: D.ContentEvent}
  Created{id: String}
  Completed{response: D.Response}
  Failed{status: Maybe<&2, String>, error: Maybe<&2, D.ProviderError>, reason: Maybe<&2, String>}
  WireError{code: Maybe<&2, String>, message: String}

type Run is Data:
  Run{state: D.State<Unit>, events: List<&2, T.AssistantMessageEvent<V.Value, Unit>>, terminal: Bool, error: Maybe<&2, D.TerminalError>}

def optionalNumber(fields: R.Record<V.Value>, key: String, value: Maybe<&2, F.F64>) -> R.Record<V.Value>:
  match value:
    case None{}: fields
    case Some{number}: R.set(V.Value, fields, key, V.Number{number})

def cost(value: T.UsageCost) -> V.Value:
  match value:
    case T.UsageCost{input, output, read, write, total}: V.ObjectValue{R.Record{R.Property{"input", V.Number{input}} <> R.Property{"output", V.Number{output}} <> R.Property{"cacheRead", V.Number{read}} <> R.Property{"cacheWrite", V.Number{write}} <> R.Property{"total", V.Number{total}} <> Nil{}}}

def encodeUsage(value: T.Usage) -> V.Value:
  match value:
    case T.Usage{input, output, read, write, longWrite, reasoning, total, prices}:
      V.ObjectValue{optionalNumber(optionalNumber(R.Record{R.Property{"input", V.Number{input}} <> R.Property{"output", V.Number{output}} <> R.Property{"cacheRead", V.Number{read}} <> R.Property{"cacheWrite", V.Number{write}} <> R.Property{"totalTokens", V.Number{total}} <> R.Property{"cost", cost(prices)} <> Nil{}}, "cacheWrite1h", longWrite), "reasoning", reasoning)}

def snapshot(message: T.AssistantMessage<V.Value, Unit>) -> V.Value:
  match message:
    case T.AssistantMessage{blocks, _, _, _, _, id, _, _, tokens, stop, _, error, raw, _, _}:
      V.ObjectValue{Content.optional(Content.optional(Content.optional(R.Record{R.Property{"content", V.ArrayValue{State.contents(blocks)}} <> R.Property{"usage", encodeUsage(tokens)} <> R.Property{"stopReason", V.Text{State.reason(stop)}} <> Nil{}}, "responseId", id), "errorMessage", error), "rawStopReason", raw)}

def errorField(fields: R.Record<V.Value>, error: Maybe<&2, D.TerminalError>) -> V.Value:
  match error:
    case None{}: V.ObjectValue{fields}
    case Some{value}: V.ObjectValue{R.set(V.Value, fields, "error", V.Text{D.terminalMessage(value)})}

def outcomeFields(fields: R.Record<V.Value>, terminal: Bool, error: Maybe<&2, D.TerminalError>) -> V.Value:
  match error:
    case None{}: errorField(fields, D.endOfStream(terminal))
    case some: errorField(fields, some)

def outcome(run: Run) -> V.Value:
  match run:
    case Run{state, events, terminal, error}: outcomeFields(R.Record{R.Property{"output", snapshot(D.stateOutput(Unit, state))} <> R.Property{"events", V.ArrayValue{State.events(events)}} <> Nil{}}, terminal, error)

def contentResult(previous: List<&2, T.AssistantMessageEvent<V.Value, Unit>>, terminal: Bool, update: D.Update<Unit>) -> Run:
  match update:
    case D.Update{state, events, None{}}: Run{state, List.append(&2, T.AssistantMessageEvent<V.Value, Unit>, previous, events), terminal, None{}}
    case D.Update{state, events, Some{error}}: Run{state, List.append(&2, T.AssistantMessageEvent<V.Value, Unit>, previous, events), terminal, Some{D.ProviderFailure{Sampling.errorMessage(error)}}}

def terminalResult(events: List<&2, T.AssistantMessageEvent<V.Value, Unit>>, update: D.Terminal<Unit>) -> Run:
  match update:
    case D.Terminal{state, error}: Run{state, events, True{}, error}

# The pricing hooks are pure defaults here; finalization consumes the model
# only for its cost table.
def costModel(prices: T.ModelCost) -> T.Model<Unit>:
  T.Model{"test", "Test", T.OpenAIResponsesApi{}, "openai", "https://example.test", False{}, None{}, T.InputText{} <> Nil{}, prices, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}

def apply(run: Run, action: Action, prices: T.ModelCost) -> Run:
  match run action:
    case Run{state, events, terminal, _} ContentEvent{value}: contentResult(events, terminal, D.contentStep(Unit, state, value))
    case Run{+state, events, terminal, _} Created{id}: Run{D.withOutput(Unit, state, D.withResponseId(Unit, D.stateOutput(Unit, state), Some{id})), events, terminal, None{}}
    case Run{state, events, _, _} Completed{response}: terminalResult(events, D.finalizeResponse(~Unit, ~Unit, ~D.defaultResolveServiceTier, ~(D.noServiceTierPricing(Unit)), costModel(prices), None{}, state, response))
    case Run{state, events, _, _} Failed{status, error, reason}: terminalResult(events, D.failedResponse(Unit, state, status, error, reason))
    case Run{state, events, terminal, _} WireError{code, message}: Run{state, events, terminal, Some{D.streamError(code, message)}}

def run(actions: List<&2, Action>, current: Run, +prices: T.ModelCost) -> V.Value:
  match actions current:
    case _ Run{state, events, terminal, Some{error}}: outcome(Run{state, events, terminal, Some{error}})
    case Nil{} value: outcome(value)
    case head <> rest value: run(rest, apply(value, head, prices), prices)

def initialUsage() -> T.Usage:
  +old = F.fromU32(99)
  T.Usage{F.fromU32(11), F.fromU32(3), F.fromU32(7), F.fromU32(2), Some{F.fromU32(1)}, Some{F.fromU32(9)}, F.fromU32(23), T.UsageCost{old, old, old, old, old}}

def initial() -> T.AssistantMessage<V.Value, Unit>:
  +zero = F.fromU32(0)
  T.AssistantMessage{Nil{}, "openai-responses", "openai", "test", None{}, Some{"initial"}, None{}, None{}, initialUsage(), T.ToolUse{}, None{}, Some{"old error"}, Some{"old raw"}, None{}, zero}

def check(actions: List<&2, Action>, prices: T.ModelCost, expected: String, label: String) -> IO(Unit):
  state = D.create(Unit, initial(), R.new(String))
  actual = run(actions, Run{state, Nil{}, False{}, None{}}, prices)
  A.assertion(Content.encoded(Json.stringify(SchemaJson.toJson(actual)), expected), label)

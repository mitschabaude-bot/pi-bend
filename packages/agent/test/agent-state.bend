import Base
import ../src/agent.bend as State
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/transcript.bend as Transcript
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Record
import ../../runtime/src/string.bend as Set
import ../../runtime/src/f64.bend as F
import ../../runtime/src/callback.bend as C
import ./main-loop.bend as H
import ./validated-tool-execution.bend as Validation
import ./message-events.bend as Test

def Value() -> Data: T.AgentState<Unit, String, String, String>
def Initial() -> Data: State.AgentInitialState<Unit, String, String, String>
def StateEvent() -> Data: T.AgentEvent<Unit, String, String, Unit, Unit>
def user() -> T.AgentMessage<Unit, String, String>:
  T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"user"}, F.fromU32(0)}}}
def assistant(error: Maybe<&2, String>) -> H.Assistant():
  +zero = F.fromU32(0)
  Ai.AssistantMessage{H.text("reply"), "custom-api", "custom-provider", "model", None{}, None{}, None{}, None{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.Stop{}, None{}, error, None{}, None{}, zero}
def toolNames(tools: List<&2, T.AgentTool<String, String>>) -> List<&2, String>:
  match tools:
    case Nil{}: Nil{}
    case T.AgentTool{name, _, _, _, _, _, _, _, _} <> rest: name <> toolNames(rest)
def modelId(model: Ai.Model<Ai.JsonValue>) -> String:
  match model:
    case Ai.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _}: id

def thinking(level: T.ThinkingLevel()) -> String:
  match level:
    case Ai.Off{}: "off"
    case Ai.Thinking{Ai.Low{}}: "low"
    case _: "unexpected"
def partial(value: Maybe<&2, T.AgentMessage<Unit, String, String>>) -> String:
  match value:
    case None{}: "none"
    case Some{message}: H.names(message <> Nil{})
def declaredList(tools: List<&2, Ai.Tool<V.Value>>) -> List<&2, String>:
  match tools:
    case Nil{}: Nil{}
    case Ai.Tool{name, _, _, _} <> rest: name <> declaredList(rest)
def declaredNames(tools: List<&2, Ai.Tool<V.Value>>) -> String:
  String.join(declaredList(tools), ",")
def keyFields(prompt: String, state: Value()) -> String:
  match state:
    case T.AgentState{model, level, tools, +messages, streaming, message, pending, error}:
      modelId(model) ++ ";" ++ thinking(level) ++ ";" ++ String.join(toolNames(tools), ",") ++ ";" ++ prompt ++ ";" ++ H.names(messages) ++ ";" ++ Bool.pick(String, streaming, "1", "0") ++ ";" ++ partial(message) ++ ";" ++ String.join(Set.toList(pending), ",") ++ ";" ++ Maybe.default(&2, String, error, "none") ++ ";" ++ declaredNames(Transcript.getCurrentTools(V.Value, V.Value, Unit, String, H.converted(messages))) ++ ";" ++ H.llmNames(State.defaultConvertToLlm(Unit, String, String, String, messages))
def key(+state: Value()) -> String:
  keyFields(State.systemPromptState(Unit, String, String, String, state), state)

def messages(mode: U32) -> Maybe<&2, Validation.Messages()>:
  match mode:
    case 3: Some{T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"existing"}, None{}, None{}, None{}, F.fromU32(1)}}} <> Nil{}}
    case 4: Some{user() <> Nil{}}
    case 5: Some{T.CustomMessage{"custom"} <> Nil{}}
    case _: None{}
def prompt(mode: U32) -> Maybe<&2, String>:
  match mode:
    case 0: None{}
    case 2: Some{""}
    case 5: None{}
    case _: Some{"seed"}
def executor(unused: Unit, input: Validation.ExecuteInput()) -> IO(Validation.ExecuteOutput()):
  IO.die(Validation.ExecuteOutput(), 1, "state operations must not execute tools")
def initial(+mode: U32, callback: C.Callback<Validation.ExecuteInput(), Validation.ExecuteOutput()>) -> Initial():
  State.AgentInitialState{prompt(mode), Bool.pick(Maybe<&2, Ai.Model<Ai.JsonValue>>, U32.is_eq(mode, 5), Some{Model.model(Ai.CustomModelApi{"custom"}, None{})}, None{}), Bool.pick(Maybe<&2, T.ThinkingLevel()>, U32.is_eq(mode, 5), Some{Ai.Thinking{Ai.Low{}}}, None{}), Bool.pick(Maybe<&2, List<&2, T.AgentTool<String, String>>>, U32.is_eq(mode, 6), Some{T.AgentTool{"echo", "Echo", V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Nil{}}}, None{}, "Echo", None{}, callback, None{}, None{}} <> Nil{}}, None{}), messages(mode)}
def event(index: U32) -> StateEvent():
  match index:
    case 0: T.AgentStart{}
    case 1: T.TurnStart{}
    case 2: T.MessageStart{user()}
    case 3: T.MessageUpdate{T.LlmMessage{Ai.Assistant{assistant(None{})}}, Ai.Start{assistant(None{})}}
    case 4: T.MessageEnd{user()}
    case 5: T.ToolExecutionStart{"a", "echo", V.Null{}}
    case 6: T.ToolExecutionStart{"a", "echo", V.Null{}}
    case 7: T.ToolExecutionStart{"b", "echo", V.Null{}}
    case 8: T.ToolExecutionEnd{"missing", "echo", Unit{}, False{}}
    case 9: T.ToolExecutionEnd{"a", "echo", Unit{}, False{}}
    case 10: T.TurnEnd{T.LlmMessage{Ai.Assistant{assistant(Some{"failure"})}}, Nil{}}
    case 11: T.TurnEnd{T.LlmMessage{Ai.Assistant{assistant(Some{""})}}, Nil{}}
    case 12: T.TurnEnd{user(), Nil{}}
    case 13: T.MessageStart{T.CustomMessage{"custom"}}
    case 14: T.AgentEnd{user() <> Nil{}}
    case 15: T.ToolExecutionUpdate{"b", "echo", V.Null{}, Unit{}}
    case _: T.MessageEnd{T.CustomMessage{"custom"}}
def step(index: U32, state: Value()) -> Value():
  match index:
    case 0: state
    case 1: State.beginRun(Unit, String, String, String, state)
    case 19: State.finishRunState(Unit, String, String, String, state)
    case 20: State.beginRun(Unit, String, String, String, state)
    case 21: State.finishRunState(Unit, String, String, String, state)
    case 22: State.stateReset(Unit, String, String, String, state)
    case other: State.processEvent(Unit, String, String, String, Unit, Unit, state, event((other - 2 : U32)))

@unsafe def checkSteps(+index: U32, +state: Value(), expected: List<&2, String>) -> IO(Unit):
  match expected:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        +next : Value() = step(index, state)
        Test.assertion(String.eq(key(next), value), "native Agent state differs from pinned initialization/event reducer")
        checkSteps((index + 1 : U32), next, rest)

def zero(value: F64) -> Bool: V.equal(V.Number{value}, V.Number{F.fromU32(0)})
def defaultModelMatches(model: Ai.Model<Ai.JsonValue>) -> Bool:
  match model:
    case Ai.Model{"unknown", "unknown", Ai.CustomModelApi{"unknown"}, "unknown", "", False{}, None{}, Nil{}, Ai.ModelCost{a, b, c, d, None{}}, context, maximum, None{}, None{}, None{}}:
      zero(a) && zero(b) && zero(c) && zero(d) && zero(context) && zero(maximum)
    case _: False{}

def scenario(mode: U32, expected: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    Test.assertion(defaultModelMatches(State.defaultModel(Ai.JsonValue)), "complete upstream unknown-model defaults")
    +callback : C.Callback<Validation.ExecuteInput(), Validation.ExecuteOutput()> <- C.create(~Unit, ~Validation.ExecuteInput(), ~Validation.ExecuteOutput(), ~executor, Unit{})
    +start : Value() = State.createState(Unit, String, String, String, initial(mode, callback))
    baseline : String = key(start)
    checkSteps(0, start, expected)
    Test.assertion(String.eq(key(start), baseline), "earlier immutable state snapshot survives all later transitions")
    C.dispose(Validation.ExecuteInput(), Validation.ExecuteOutput(), callback)

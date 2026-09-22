import Base
import ../src/agent.bend as Agent
import ../src/agent.bend as State
import ../src/agent.bend as Run
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../ai/src/utils/transcript.bend as Transcript
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/record.bend as Record
import ../../runtime/src/f64.bend as F
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-behavior.bend as Behavior
import ./agent-run.bend as H
import ./tool-changes.bend as ChangesTest
import ./message-events.bend as Test

def schema() -> Schema.Value:
  Schema.ObjectValue{Record.Record{Record.Property{"type", Schema.Text{"object"}} <> Record.Property{"properties", Schema.ObjectValue{Record.Record{Nil{}}}} <> Nil{}}}
def declaration(name: String, description: String) -> Ai.Tool<Schema.Value>: Ai.Tool{name, description, schema(), None{}}
def tool(name: String, description: String, executor: Named.Executor()) -> Named.Tool():
  T.AgentTool{name, description, schema(), None{}, "Fixture", None{}, executor, None{}, None{}}
def additions(values: Maybe<&2, List<&2, Ai.Tool<Schema.Value>>>) -> String:
  match values:
    case None{}: ""
    case Some{Nil{}}: ""
    case Some{Ai.Tool{name, _, _, _} <> Nil{}}: name
    case Some{Ai.Tool{name, _, _, _} <> rest}: name ++ "," ++ additions(Some{rest})
def removals(values: Maybe<&2, List<&2, Ai.ToolReference>>) -> String:
  match values:
    case None{}: ""
    case Some{Nil{}}: ""
    case Some{Ai.ToolReference{name} <> Nil{}}: name
    case Some{Ai.ToolReference{name} <> rest}: name ++ "," ++ removals(Some{rest})
def declarations(messages: List<&2, Ai.Message<Schema.Value, Unit, Unit, Unit>>) -> String:
  match messages:
    case Nil{}: ""
    case Ai.System{Ai.SystemMessage{_, _, added, removed, _}} <> rest: "+" ++ additions(added) ++ ";-" ++ removals(removed) ++ ";" ++ declarations(rest)
    case _ <> rest: declarations(rest)
type Capture is Data:
  Capture{requests: R.Ref<String>, streams: R.Ref<List<&2, H.StreamValue()>>}
def provider(capture: Capture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture input:
    case Capture{requests, streams} T.StreamInput{_, Ai.TranscriptContext{messages}, _}:
      do IO<H.ProviderOutput()>:
        R.modify(String, Unit, requests, old => (old ++ declarations(messages) ++ "|", Unit{}))
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Unit, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        Stream.push(Ai.AssistantMessageEvent<Unit, Unit>, Ai.AssistantMessage<Unit, Unit>, stream, Ai.StreamDone{Ai.DoneStop{}, H.assistant()})
        return Done{stream}
def forbidden(unused: Unit, input: T.ToolExecutionInput<Unit, Run.RunSignal(), Unit>) -> IO(Result<&2, &2, String, T.AgentToolResult<Unit>>):
  IO.die(Result<&2, &2, String, T.AgentToolResult<Unit>>, 1, "declaration-only test must not execute a tool")
def initial(mode: U32, executor: Named.Executor()) -> Maybe<&2, State.AgentInitialState<Schema.Value, Unit, Unit, Unit, String, Unit, Run.RunSignal(), String, Unit>>:
  Some{State.AgentInitialState{Some{"You are helpful."}, None{}, None{}, Bool.pick(Maybe<&2, List<&2, Named.Tool()>>, U32.is_eq(mode, 1), None{}, Some{tool("first", "first tool", executor) <> Nil{}}), None{}}}
def create(mode: U32, capture: Capture) -> IO(Named.Fixture):
  do IO<Named.Fixture>:
    +stream : Named.StreamFunction() <- C.create(~Capture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, capture)
    +validate : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput<Schema.Value, Unit, Unit>, ~Result<&2, &2, String, Unit>, ~H.validate, 0)
    +execute : Named.Executor() <- C.create(~Unit, ~T.ToolExecutionInput<Unit, Run.RunSignal(), Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~forbidden, Unit{})
    +fallback : Named.Fallback() <- Provider.create(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, Named.options(initial(mode, execute), stream), fallback, validate, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(result)
    return Named.Fixture{agent, stream, validate, execute, fallback}
def executor(fixture: Named.Fixture) -> Named.Executor():
  match fixture:
    case Named.Fixture{_, _, _, value, _}: value
def changedMessage(messages: H.Messages()) -> Bool:
  match messages:
    case T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{""}, None{}, Some{added <> Nil{}}, Some{Ai.ToolReference{"first"} <> Nil{}}, timestamp}}} <> _:
      ChangesTest.declared(Declaration.declarationsEqual(added, declaration("second", "second tool"))) && Bool.not(Schema.equal(Schema.Number{timestamp}, Schema.Number{F.fromU32(0)}))
    case _ <> rest: changedMessage(rest)
    case Nil{}: False{}
def change(+fixture: Named.Fixture) -> IO(Unit):
  do IO<Unit>:
    +agent : Owner.Owner() = Named.getAgent(fixture)
    Behavior.prompt(agent, "one")
    Agent.setTools(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, tool("second", "second tool", executor(fixture)) <> Nil{})
    Behavior.prompt(agent, "two")
    Behavior.prompt(agent, "three")
    state : Named.Snapshot() <- Agent.state(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    Test.assertion(changedMessage(Named.getMessages(state)), "complete added/removed declaration and timestamp persist in generated system message")
def sections(key: String, value: String) -> Maybe<&2, Record.Record<Maybe<&2, String>>>:
  Some{Record.Record{Record.Property{key, Some{value}} <> Nil{}}}
def pending(mode: U32) -> H.Message():
  match mode:
    case 1: T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{""}, sections("skills", "<skills>x</skills>"), None{}, None{}, F.fromU32(1)}}}
    case _: T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{""}, sections("note", "<note>x</note>"), Some{declaration("second", "second tool") <> Nil{}}, Some{Ai.ToolReference{"first"} <> Nil{}}, F.fromU32(1)}}}
def second(messages: H.Messages()) -> Ai.SystemMessage<Schema.Value>:
  match messages:
    case _ <> T.LlmMessage{Ai.System{value}} <> _: value
    case _: Ai.SystemMessage{Ai.SystemText{"unexpected"}, None{}, None{}, None{}, F.fromU32(0)}
def merged(message: Ai.SystemMessage<Schema.Value>) -> Bool:
  match message:
    case Ai.SystemMessage{Ai.SystemText{""}, Some{Record.Record{Record.Property{"skills", Some{"<skills>x</skills>"}} <> Nil{}}}, Some{added <> Nil{}}, None{}, timestamp}:
      ChangesTest.declared(Declaration.declarationsEqual(added, declaration("echo", "Echo input"))) && Schema.equal(Schema.Number{timestamp}, Schema.Number{F.fromU32(1)})
    case _: False{}
def rewritten(message: Ai.SystemMessage<Schema.Value>) -> Bool:
  match message:
    case Ai.SystemMessage{Ai.SystemText{""}, Some{Record.Record{Record.Property{"note", Some{"<note>x</note>"}} <> Nil{}}}, None{}, None{}, timestamp}: Schema.equal(Schema.Number{timestamp}, Schema.Number{F.fromU32(1)})
    case _: False{}
def current(message: Maybe<&2, Ai.SystemMessage<Schema.Value>>) -> Bool:
  match message:
    case Some{Ai.SystemMessage{_, _, Some{Ai.Tool{"first", _, _, _} <> Nil{}}, _, _}}: True{}
    case _: False{}
def checkPending(mode: U32, +messages: H.Messages()) -> Bool:
  match mode:
    case 1: merged(second(messages))
    case _: rewritten(second(messages)) && current(Transcript.getCurrentSystemMessage(Schema.Value, Unit, Unit, Unit, State.defaultConvertToLlm(Schema.Value, Unit, Unit, Unit, String, Unit, Run.RunSignal(), String, Unit, messages)))
def setEcho(mode: U32, agent: Owner.Owner(), execute: Named.Executor()) -> IO(Unit):
  match mode:
    case 1: Agent.setTools(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, tool("echo", "Echo input", execute) <> Nil{})
    case _: IO.pure(Unit, Unit{})
def merge(+fixture: Named.Fixture, +mode: U32) -> IO(Unit):
  do IO<Unit>:
    +agent : Owner.Owner() = Named.getAgent(fixture)
    setEcho(mode, agent, executor(fixture))
    user : H.Message() = T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"hi"}, F.fromU32(2)}}}
    result : Owner.Outcome() <- Agent.prompt(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent, Agent.Messages{pending(mode) <> user <> Nil{}})
    Behavior.success(result)
    state : Named.Snapshot() <- Agent.state(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    Test.assertion(checkPending(mode, Named.getMessages(state)), "pending system sections/timestamp survive and executable declarations win")
def run(mode: U32, fixture: Named.Fixture) -> IO(Unit):
  match mode:
    case 0: change(fixture)
    case _: merge(fixture, mode)
def expected(mode: U32) -> String:
  match mode:
    case 0: "+first;-;|+first;-;+second;-first;|+first;-;+second;-first;|"
    case 1: "+;-;+echo;-;|"
    case _: "+first;-;+;-;|"
def scenario(+mode: U32, name: String) -> IO(Unit):
  do IO<Unit>:
    +requests : R.Ref<String> <- R.new(String, "")
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +fixture : Named.Fixture <- create(mode, Capture{requests, streams})
    run(mode, fixture)
    actual : String <- R.read(String, requests)
    Test.assertion(String.eq(actual, expected(mode)), "provider receives the exact ordered declarations without duplicate system messages")
    Named.dispose(fixture)
    old : String <- R.dispose(String, requests)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    IO.print("PASS " ++ name)
def main() -> IO(Unit):
  do IO<Unit>:
    scenario(0, "declares tool loadout changes to the model before the next request")
    scenario(1, "merges tool changes into a pending system message")
    scenario(2, "rewrites pending tool declarations to match the executable set")

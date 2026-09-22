import Base
import ../src/agent.bend as Run
import ../src/agent.bend as Runtime
import ../src/agent.bend as State
import ../src/agent.bend as Life
import ../src/agent.bend as Plan
import ../src/agent.bend as Listeners
import ../src/agent-loop.bend as Loop
import ../src/agent-loop.bend as Emission
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ./agent-run.bend as H
import ./message-events.bend as Test

# The stream lease end to end: the provider lends an owned stream and records
# when the loop releases it; the trace shows the release after the final
# assistant message and before the turn ends, exactly once, and the loop's
# outcome combines consumption and release failures as specified.

type LeaseCapture is Data:
  LeaseCapture{mode: U32, trace: R.Ref<String>, streams: R.Ref<List<&2, H.StreamValue()>>}

type ListenerCapture is Data:
  ListenerCapture{trace: R.Ref<String>, failAtEnd: Bool}

def note(trace: R.Ref<String>, entry: String) -> IO(Unit):
  R.modify(String, Unit, trace, old => (old ++ entry ++ ";", Unit{}))

# An ended assistant message also shows its error text, so a failure that the
# loop turns into an errored assistant turn is visible in the trace.
def detail(event: H.EventValue()) -> String:
  match event:
    case T.MessageEnd{T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, Some{error}, _, _, _}}}}: "(" ++ error ++ ")"
    case _: ""

def listener(capture: ListenerCapture, input: Listeners.Input<H.EventValue()>) -> IO(Emission.Emission<String>):
  match capture input:
    case ListenerCapture{trace, failAtEnd} Listeners.Input{+event, _}:
      do IO<Emission.Emission<String>>:
        +name : String = H.eventName(event)
        note(trace, name ++ detail(event))
        return Emission.EmissionReady{Bool.pick(Result<&2, &2, String, Unit>, failAtEnd && String.eq(name, "end:a"), Fail{"listener failed"}, Done{Unit{}})}

def cleanup(mode: U32) -> Result<&2, &2, String, Unit>:
  match mode:
    case 0: Done{Unit{}}
    case _: Fail{"cleanup failed"}

def release(trace: R.Ref<String>, outcome: Result<&2, &2, String, Unit>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    note(trace, "released")
    return outcome

def opened(+mode: U32, +trace: R.Ref<String>, streams: R.Ref<List<&2, H.StreamValue()>>) -> IO(H.ProviderOutput()):
  match mode:
    case 2: IO.pure(H.ProviderOutput(), Fail{"open failed"})
    case _:
      do IO<H.ProviderOutput()>:
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Schema.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Ai.AssistantMessage<Schema.Value, Unit>, stream, Ai.Start{H.assistant()})
        Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Ai.AssistantMessage<Schema.Value, Unit>, stream, Ai.StreamDone{Ai.DoneStop{}, H.assistant()})
        return Done{T.StreamLease{stream, release(trace, cleanup(mode))}}

def provider(capture: LeaseCapture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture:
    case LeaseCapture{mode, +trace, streams}:
      do IO<H.ProviderOutput()>:
        note(trace, "opened")
        opened(mode, trace, streams)

def scenario(+mode: U32, +expected: String) -> IO(Unit):
  do IO<Unit>:
    initial : State.AgentInitialState<Unit, Unit, String, String> = State.AgentInitialState{Some{"base"}, None{}, None{}, None{}, None{}}
    +runtime : H.Owner() <- Runtime.newRuntime(Unit, Unit, String, String, initial, T.OneAtATime{}, T.OneAtATime{})
    +listeners : Run.Registry(Unit, Unit, String, String) <- Listeners.newListeners(H.EventValue(), String)
    +trace : R.Ref<String> <- R.new(String, "")
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +observe : Listeners.Handler(H.EventValue(), String) <- C.create(~ListenerCapture, ~Listeners.Input<H.EventValue()>, ~Emission.Emission<String>, ~listener, ListenerCapture{trace, U32.is_eq(mode, 3)})
    ignored : Listeners.Subscription<H.EventValue(), String> <- Listeners.subscribeListeners(H.EventValue(), String, listeners, observe)
    +convert : C.Callback<H.Messages(), H.Converted()> <- C.create(~Unit, ~H.Messages(), ~H.Converted(), ~H.converter, Unit{})
    +validation : C.Callback<Loop.ToolValidationInput, Result<&2, &2, String, Schema.Value>> <- C.create(~U32, ~Loop.ToolValidationInput, ~Result<&2, &2, String, Schema.Value>, ~H.validate, 0)
    +stream : T.StreamFn(Unit, Unit, H.Config(), String) <- C.create(~LeaseCapture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, LeaseCapture{mode, trace, streams})
    prepared : H.Claim() <- Runtime.beginPrompt(Unit, Unit, String, String, runtime, H.user("prompt") <> Nil{})
    claimed : Life.Claimed<Plan.Plan<H.Message()>> <- H.requireClaim(prepared)
    completed : H.Completion() <- Run.runClaimedRun(~Unit, ~Unit, ~String, ~String, ~Unit, ~H.identity, ~H.identity, ~H.declaration, runtime, listeners, Run.Options{H.config(convert), Provider.Explicit{stream}, validation, Unit{}}, claimed)
    outcome : String <- H.finish(completed)
    Runtime.waitForIdleRuntime(Unit, Unit, String, String, runtime)
    events : String <- R.read(String, trace)
    +actual : String = events ++ "#" ++ outcome
    Test.assertion(String.eq(actual, expected), "stream lease trace mismatch: " ++ actual ++ " != " ++ expected)
    Listeners.disposeListeners(H.EventValue(), String, listeners)
    C.dispose(Listeners.Input<H.EventValue()>, Emission.Emission<String>, observe)
    C.dispose(H.Messages(), H.Converted(), convert)
    C.dispose(Loop.ToolValidationInput, Result<&2, &2, String, Schema.Value>, validation)
    C.dispose(H.ProviderInput(), H.ProviderOutput(), stream)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    old : String <- R.dispose(String, trace)
    state : Runtime.OwnedState<Unit, Unit, String, String> <- Runtime.disposeRuntime(Unit, Unit, String, String, runtime)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(0, "agent_start;turn_start;start:u;end:u;opened;start:a;end:a;released;turn_end;agent_end;#ok")
    IO.print("PASS the lease is released once, after the final assistant message and before the turn ends")
    scenario(1, "agent_start;turn_start;start:u;end:u;opened;start:a;end:a;released;start:a;end:a(cleanup failed);turn_end;agent_end;#ok")
    IO.print("PASS a release failure after a consumed response becomes an errored assistant turn")
    scenario(2, "agent_start;turn_start;start:u;end:u;opened;start:a;end:a(open failed);turn_end;agent_end;#ok")
    IO.print("PASS a failed open releases nothing and becomes an errored assistant turn")
    scenario(3, "agent_start;turn_start;start:u;end:u;opened;start:a;end:a;released;start:a;end:a(listener failed);#listener failed")
    IO.print("PASS an earlier delivery failure survives a failing release, which still runs once")

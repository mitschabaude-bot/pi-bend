import Base
import ./types.bend as T
import ./agent-state.bend as State
import ./agent-queues.bend as Q
import ./agent-continuation.bend as Continue
import ./agent-lifecycle.bend as L

# P/A/G/D/C are schema/arguments/diagnostics/details/custom message values;
# V/S/E/J are validated arguments/tool signal/tool error/model metadata.
# One synchronized owner couples transcript, queues and active-run status.
type OwnedState<-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data> is Data:
  OwnedState{state: T.AgentState<P, A, G, D, C, V, S, E, J>, queues: Q.Queues<T.AgentMessage<P, A, G, D, C>>}
type Runtime<-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data> is Data:
  Runtime{lifecycle: L.Lifecycle<OwnedState<P, A, G, D, C, V, S, E, J>>}

def new(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, initial: State.AgentInitialState<P, A, G, D, C, V, S, E, J>, steeringMode: T.QueueMode, followUpMode: T.QueueMode) -> IO(Runtime<P, A, G, D, C, V, S, E, J>):
  do IO<Runtime<P, A, G, D, C, V, S, E, J>>:
    lifecycle : L.Lifecycle<OwnedState<P, A, G, D, C, V, S, E, J>> <- L.new(OwnedState<P, A, G, D, C, V, S, E, J>, OwnedState{State.create(P, A, G, D, C, V, S, E, J, initial), Q.new(T.AgentMessage<P, A, G, D, C>, steeringMode, followUpMode)})
    return Runtime{lifecycle}
def snapshot(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>) -> IO(OwnedState<P, A, G, D, C, V, S, E, J>):
  match runtime:
    case Runtime{lifecycle}: L.read(OwnedState<P, A, G, D, C, V, S, E, J>, lifecycle)
def stateValue(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>) -> T.AgentState<P, A, G, D, C, V, S, E, J>:
  match owned:
    case OwnedState{state, _}: state
def read(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>) -> IO(T.AgentState<P, A, G, D, C, V, S, E, J>):
  do IO<T.AgentState<P, A, G, D, C, V, S, E, J>>:
    owned : OwnedState<P, A, G, D, C, V, S, E, J> <- snapshot(P, A, G, D, C, V, S, E, J, runtime)
    return stateValue(P, A, G, D, C, V, S, E, J, owned)
def history(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, state: T.AgentState<P, A, G, D, C, V, S, E, J>) -> List<&2, T.AgentMessage<P, A, G, D, C>>:
  match state:
    case T.AgentState{_, _, _, messages, _, _, _, _}: messages

def enqueueState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, kind: Q.QueueKind, message: T.AgentMessage<P, A, G, D, C>) -> OwnedState<P, A, G, D, C, V, S, E, J> & Unit:
  match owned:
    case OwnedState{state, queues}: (OwnedState{state, Q.enqueue(T.AgentMessage<P, A, G, D, C>, queues, kind, message)}, Unit{})
def enqueue(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>, kind: Q.QueueKind, message: T.AgentMessage<P, A, G, D, C>) -> IO(Unit):
  match runtime:
    case Runtime{lifecycle}: L.modify(OwnedState<P, A, G, D, C, V, S, E, J>, Unit, lifecycle, owned => active => enqueueState(P, A, G, D, C, V, S, E, J, owned, kind, message))
def steer(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>, message: T.AgentMessage<P, A, G, D, C>) -> IO(Unit): enqueue(P, A, G, D, C, V, S, E, J, runtime, Q.Steering{}, message)
def followUp(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>, message: T.AgentMessage<P, A, G, D, C>) -> IO(Unit): enqueue(P, A, G, D, C, V, S, E, J, runtime, Q.FollowUp{}, message)
def updatedQueues(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, update: Q.Queues<T.AgentMessage<P, A, G, D, C>> -> Q.Queues<T.AgentMessage<P, A, G, D, C>>) -> OwnedState<P, A, G, D, C, V, S, E, J> & Unit:
  match owned:
    case OwnedState{state, queues}: (OwnedState{state, update(queues)}, Unit{})
def updateQueues(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>, update: Q.Queues<T.AgentMessage<P, A, G, D, C>> -> Q.Queues<T.AgentMessage<P, A, G, D, C>>) -> IO(Unit):
  match runtime:
    case Runtime{lifecycle}: L.modify(OwnedState<P, A, G, D, C, V, S, E, J>, Unit, lifecycle, owned => active => updatedQueues(P, A, G, D, C, V, S, E, J, owned, update))
def clearQueue(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>, kind: Q.QueueKind) -> IO(Unit): updateQueues(P, A, G, D, C, V, S, E, J, runtime, queues => Q.clear(T.AgentMessage<P, A, G, D, C>, queues, kind))
def clearAllQueues(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>) -> IO(Unit): updateQueues(P, A, G, D, C, V, S, E, J, runtime, queues => Q.clearAll(T.AgentMessage<P, A, G, D, C>, queues))
def setQueueMode(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>, kind: Q.QueueKind, mode: T.QueueMode) -> IO(Unit): updateQueues(P, A, G, D, C, V, S, E, J, runtime, queues => Q.setMode(T.AgentMessage<P, A, G, D, C>, queues, kind, mode))
def drained(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, state: T.AgentState<P, A, G, D, C, V, S, E, J>, result: Q.Queues<T.AgentMessage<P, A, G, D, C>> & List<&2, T.AgentMessage<P, A, G, D, C>>) -> OwnedState<P, A, G, D, C, V, S, E, J> & List<&2, T.AgentMessage<P, A, G, D, C>>:
  match result:
    case Tuple{queues, messages}: (OwnedState{state, queues}, messages)
def drainState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, kind: Q.QueueKind) -> OwnedState<P, A, G, D, C, V, S, E, J> & List<&2, T.AgentMessage<P, A, G, D, C>>:
  match owned:
    case OwnedState{state, queues}: drained(P, A, G, D, C, V, S, E, J, state, Q.drain(T.AgentMessage<P, A, G, D, C>, queues, kind))
def drain(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>, kind: Q.QueueKind) -> IO(List<&2, T.AgentMessage<P, A, G, D, C>>):
  match runtime:
    case Runtime{lifecycle}: L.modify(OwnedState<P, A, G, D, C, V, S, E, J>, List<&2, T.AgentMessage<P, A, G, D, C>>, lifecycle, owned => active => drainState(P, A, G, D, C, V, S, E, J, owned, kind))

def resetState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, active: Maybe<&2, L.ActiveRun>) -> OwnedState<P, A, G, D, C, V, S, E, J> & Result<&2, &2, String, Unit>:
  match owned active:
    case OwnedState{state, queues} None{}: (OwnedState{State.reset(P, A, G, D, C, V, S, E, J, state), Q.clearAll(T.AgentMessage<P, A, G, D, C>, queues)}, Done{Unit{}})
    case OwnedState{state, queues} Some{_}: (OwnedState{state, queues}, Fail{"Agent is already processing. Wait for completion before resetting."})
def reset(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>) -> IO(Result<&2, &2, String, Unit>):
  match runtime:
    case Runtime{lifecycle}: L.modify(OwnedState<P, A, G, D, C, V, S, E, J>, Result<&2, &2, String, Unit>, lifecycle, owned => active => resetState(P, A, G, D, C, V, S, E, J, owned, active))

def preparePrompt(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, messages: List<&2, T.AgentMessage<P, A, G, D, C>>) -> Result<&2, &2, String, L.Prepared<OwnedState<P, A, G, D, C, V, S, E, J>, Continue.Plan<T.AgentMessage<P, A, G, D, C>>>>:
  match owned:
    case OwnedState{state, queues}: Done{L.Prepared{OwnedState{State.beginRun(P, A, G, D, C, V, S, E, J, state), queues}, Continue.Prompt{messages, False{}}}}
def planned(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, state: T.AgentState<P, A, G, D, C, V, S, E, J>, result: Q.Queues<T.AgentMessage<P, A, G, D, C>> & Result<&2, &2, Continue.ContinueError, Continue.Plan<T.AgentMessage<P, A, G, D, C>>>) -> Result<&2, &2, String, L.Prepared<OwnedState<P, A, G, D, C, V, S, E, J>, Continue.Plan<T.AgentMessage<P, A, G, D, C>>>>:
  match result:
    case Tuple{_, Fail{error}}: Fail{Continue.errorMessage(error)}
    case Tuple{queues, Done{plan}}: Done{L.Prepared{OwnedState{State.beginRun(P, A, G, D, C, V, S, E, J, state), queues}, plan}}
def prepareContinue(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>) -> Result<&2, &2, String, L.Prepared<OwnedState<P, A, G, D, C, V, S, E, J>, Continue.Plan<T.AgentMessage<P, A, G, D, C>>>>:
  match owned:
    case OwnedState{+state, queues}: planned(P, A, G, D, C, V, S, E, J, state, Continue.plan(P, A, G, D, C, False{}, history(P, A, G, D, C, V, S, E, J, state), queues))
def beginPrompt(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>, messages: List<&2, T.AgentMessage<P, A, G, D, C>>) -> IO(Result<&2, &2, L.ClaimError<String>, L.Claimed<Continue.Plan<T.AgentMessage<P, A, G, D, C>>>>):
  match runtime:
    case Runtime{lifecycle}: L.claim(OwnedState<P, A, G, D, C, V, S, E, J>, String, Continue.Plan<T.AgentMessage<P, A, G, D, C>>, lifecycle, owned => preparePrompt(P, A, G, D, C, V, S, E, J, owned, messages))
def beginContinue(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>) -> IO(Result<&2, &2, L.ClaimError<String>, L.Claimed<Continue.Plan<T.AgentMessage<P, A, G, D, C>>>>):
  match runtime:
    case Runtime{lifecycle}: L.claim(OwnedState<P, A, G, D, C, V, S, E, J>, String, Continue.Plan<T.AgentMessage<P, A, G, D, C>>, lifecycle, owned => prepareContinue(P, A, G, D, C, V, S, E, J, owned))
def ended(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>) -> OwnedState<P, A, G, D, C, V, S, E, J>:
  match owned:
    case OwnedState{state, queues}: OwnedState{State.finishRun(P, A, G, D, C, V, S, E, J, state), queues}
def finishRun(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>, run: L.ActiveRun) -> IO(Bool):
  match runtime:
    case Runtime{lifecycle}: L.finish(OwnedState<P, A, G, D, C, V, S, E, J>, lifecycle, run, owned => ended(P, A, G, D, C, V, S, E, J, owned))

def listenerRun(active: Maybe<&2, L.ActiveRun>) -> Result<&2, &2, String, L.ActiveRun>:
  match active:
    case None{}: Fail{"Agent listener invoked outside active run"}
    case Some{run}: Done{run}
def eventState(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, owned: OwnedState<P, A, G, D, C, V, S, E, J>, active: Maybe<&2, L.ActiveRun>, event: T.AgentEvent<P, A, G, D, C, Partial, Execution>) -> OwnedState<P, A, G, D, C, V, S, E, J> & Result<&2, &2, String, L.ActiveRun>:
  match owned:
    case OwnedState{state, queues}: (OwnedState{State.processEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, state, event), queues}, listenerRun(active))
# Reduction happens before listener dispatch, including the source's error for
# an event outside a run. The returned handle carries the active signal.
def recordEvent(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>, event: T.AgentEvent<P, A, G, D, C, Partial, Execution>) -> IO(Result<&2, &2, String, L.ActiveRun>):
  match runtime:
    case Runtime{lifecycle}: L.modify(OwnedState<P, A, G, D, C, V, S, E, J>, Result<&2, &2, String, L.ActiveRun>, lifecycle, owned => active => eventState(P, A, G, D, C, V, S, E, J, Partial, Execution, owned, active, event))
def abort(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>) -> IO(Unit):
  match runtime:
    case Runtime{lifecycle}: L.abort(OwnedState<P, A, G, D, C, V, S, E, J>, lifecycle)
def waitForIdle(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>) -> IO(Unit):
  match runtime:
    case Runtime{lifecycle}: L.waitForIdle(OwnedState<P, A, G, D, C, V, S, E, J>, lifecycle)
def dispose(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, C, V, S, E, J>) -> IO(OwnedState<P, A, G, D, C, V, S, E, J>):
  match runtime:
    case Runtime{lifecycle}: L.dispose(OwnedState<P, A, G, D, C, V, S, E, J>, lifecycle)

def changedState(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, owned: OwnedState<P, A, G, D, M, V, S, E, J>, change: State.Change<P, A, G, D, M, V, S, E, J>) -> OwnedState<P, A, G, D, M, V, S, E, J> & Unit:
  match owned:
    case OwnedState{state, queues}: (OwnedState{State.applyChange(P, A, G, D, M, V, S, E, J, state, change), queues}, Unit{})
def updateState(-P: Data, -A: Data, -G: Data, -D: Data, -M: Data, -V: Data, -S: Data, -E: Data, -J: Data, runtime: Runtime<P, A, G, D, M, V, S, E, J>, change: State.Change<P, A, G, D, M, V, S, E, J>) -> IO(Unit):
  match runtime:
    case Runtime{lifecycle}: L.modify(OwnedState<P, A, G, D, M, V, S, E, J>, Unit, lifecycle, owned => active => changedState(P, A, G, D, M, V, S, E, J, owned, change))

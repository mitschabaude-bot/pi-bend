import Base
import ./types.bend as T
import ./agent-runtime.bend as Runtime
import ./agent-lifecycle.bend as Lifecycle
import ./agent-listeners.bend as Listeners
import ../../runtime/src/abort.bend as Abort

type DeliveryError<-Failure: Data> is Data:
  OutsideRun{message: String}
  ListenerFailed{error: Failure}
def delivered(-Failure: Data, result: Result<&2, &2, Failure, Unit>) -> Result<&2, &2, DeliveryError<Failure>, Unit>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{ListenerFailed{error}}
def dispatch(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -Partial: Data, -Execution: Data, -Failure: Data, listeners: Listeners.Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, event: T.AgentEvent<P, A, G, D, C, Partial, Execution>, active: Result<&2, &2, String, Lifecycle.ActiveRun>) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  match active:
    case Fail{message}: IO.pure(Result<&2, &2, DeliveryError<Failure>, Unit>, Fail{OutsideRun{message}})
    case Done{run}:
      do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
        result : Result<&2, &2, Failure, Unit> <- Listeners.emit(T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure, listeners, event, Lifecycle.signal(run))
        return delivered(Failure, result)
# State commits before listeners observe this event. Awaiting this operation is
# part of the active run: agent_end delivery itself never marks the owner idle.
def processEvents(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, runtime: Runtime.Runtime<P, A, G, D, C, V, S, E, J>, listeners: Listeners.Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, +event: T.AgentEvent<P, A, G, D, C, Partial, Execution>) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
    active : Result<&2, &2, String, Lifecycle.ActiveRun> <- Runtime.recordEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, runtime, event)
    dispatch(P, A, G, D, C, Partial, Execution, Failure, listeners, event, active)

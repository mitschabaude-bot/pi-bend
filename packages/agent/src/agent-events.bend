import Base
import ./event-emission.bend as Emission
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
def completed(-Failure: Data, delivery: Emission.Emission<Failure>) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
    result : Result<&2, &2, Failure, Unit> <- Emission.wait(Failure, delivery)
    return delivered(Failure, result)
def startDispatch(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -Partial: Data, -Execution: Data, -Failure: Data, listeners: Listeners.Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, event: T.AgentEvent<P, A, G, D, C, Partial, Execution>, active: Result<&2, &2, String, Lifecycle.ActiveRun>) -> IO(Emission.Emission<DeliveryError<Failure>>):
  match active:
    case Fail{message}: IO.pure(Emission.Emission<DeliveryError<Failure>>, Emission.Ready{Fail{OutsideRun{message}}})
    case Done{run}:
      do IO<Emission.Emission<DeliveryError<Failure>>>:
        delivery : Emission.Emission<Failure> <- Listeners.start(T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure, listeners, event, Lifecycle.signal(run))
        Emission.start(DeliveryError<Failure>, completed(Failure, delivery))
# State reduction and the first listener's immediate effects happen before
# returning. The caller owns and must await the remaining delivery.
def startEvents(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, runtime: Runtime.Runtime<P, A, G, D, C, V, S, E, J>, listeners: Listeners.Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, +event: T.AgentEvent<P, A, G, D, C, Partial, Execution>) -> IO(Emission.Emission<DeliveryError<Failure>>):
  do IO<Emission.Emission<DeliveryError<Failure>>>:
    active : Result<&2, &2, String, Lifecycle.ActiveRun> <- Runtime.recordEvent(P, A, G, D, C, V, S, E, J, Partial, Execution, runtime, event)
    startDispatch(P, A, G, D, C, Partial, Execution, Failure, listeners, event, active)

# Awaited delivery is the same start operation followed by its completion.
def processEvents(-P: Data, -A: Data, -G: Data, -D: Data, -C: Data, -V: Data, -S: Data, -E: Data, -J: Data, -Partial: Data, -Execution: Data, -Failure: Data, runtime: Runtime.Runtime<P, A, G, D, C, V, S, E, J>, listeners: Listeners.Listeners<T.AgentEvent<P, A, G, D, C, Partial, Execution>, Abort.AbortSignal<Unit>, Failure>, +event: T.AgentEvent<P, A, G, D, C, Partial, Execution>) -> IO(Result<&2, &2, DeliveryError<Failure>, Unit>):
  do IO<Result<&2, &2, DeliveryError<Failure>, Unit>>:
    delivery : Emission.Emission<DeliveryError<Failure>> <- startEvents(P, A, G, D, C, V, S, E, J, Partial, Execution, Failure, runtime, listeners, event)
    Emission.wait(DeliveryError<Failure>, delivery)

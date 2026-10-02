import Base
import ./abort.bend as Abort
import ./deferred.bend as D
import ./ref.bend as Ref

# Cancellation releases the caller without destroying its running operation.
# The operation borrows a private signal; its controller and observations live
# until both caller and worker finish. Cleanup runs exactly once at that point.
type State is Type:
  Active{completed: Bool, departed: Bool, cleanup: IO(Unit)}
  Retired{}

type Task<-A: Data> is Data:
  Task{result: D.Deferred<A>, state: Ref.Ref<State>, controller: Abort.AbortController<Unit>}

type Arrival<-A: Data> is Data:
  Completed{value: A}
  Cancelled{}

def finishedState(done: Bool, completed: Bool, departed: Bool, cleanup: IO(Unit)) -> State & Maybe<&1, IO(Unit)>:
  match done:
    case True{}: (Retired{}, Some{cleanup})
    case False{}: (Active{completed, departed, cleanup}, None{})

def departure(+worker: Bool, state: State) -> State & Maybe<&1, IO(Unit)>:
  match state:
    case Retired{}: (Retired{}, None{})
    case Active{completed, departed, cleanup}:
      +done = completed || worker
      +gone = departed || Bool.not(worker)
      finishedState(done && gone, done, gone, cleanup)

def clean(-A: Data, task: Task<A>, cleanup: Maybe<&1, IO(Unit)>) -> IO(Unit):
  match task cleanup:
    case _ None{}: IO.pure(Unit, Unit{})
    case Task{result, state, controller} Some{finish}:
      do IO<Unit>:
        D.dispose(A, result)
        Abort.dispose(Unit, controller)
        previous : State <- Ref.dispose(State, state)
        finish

def depart(-A: Data, +task: Task<A>, worker: Bool) -> IO(Unit):
  match task:
    case Task{_, state, _}:
      do IO<Unit>:
        cleanup : Maybe<&1, IO(Unit)> <- Ref.modify(State, Maybe<&1, IO(Unit)>, state, current => departure(worker, current))
        clean(A, task, cleanup)

def perform(-A: Data, +task: Task<A>, operation: Abort.AbortSignal<Unit> -> IO(A)) -> IO(Unit):
  match task:
    case Task{result, _, controller}:
      do IO<Unit>:
        value : A <- operation(Abort.signal(Unit, controller))
        settled : Bool <- D.resolve(A, result, value)
        depart(A, task, True{})

def reportResult(-A: Data, value: Maybe<&2, A>, completion: D.Deferred<Arrival<A>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{result}:
      do IO<Unit>:
        won : Bool <- D.resolve(Arrival<A>, completion, Completed{result})
        return Unit{}

def observeResult(-A: Data, ticket: D.Ticket<Maybe<&2, A>>, completion: D.Deferred<Arrival<A>>) -> IO(Unit):
  do IO<Unit>:
    value : Maybe<&2, A> <- D.wait(Maybe<&2, A>, ticket)
    reportResult(A, value, completion)

def reportAbort(-A: Data, value: Maybe<&2, Abort.AbortReason<Unit>>, completion: D.Deferred<Arrival<A>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{_}:
      do IO<Unit>:
        won : Bool <- D.resolve(Arrival<A>, completion, Cancelled{})
        return Unit{}

def observeAbort(-A: Data, ticket: D.Ticket<Maybe<&2, Abort.AbortReason<Unit>>>, completion: D.Deferred<Arrival<A>>) -> IO(Unit):
  do IO<Unit>:
    value : Maybe<&2, Abort.AbortReason<Unit>> <- D.wait(Maybe<&2, Abort.AbortReason<Unit>>, ticket)
    reportAbort(A, value, completion)

def observed(-A: Data, result: D.Observation<A>, aborted: D.Observation<Abort.AbortReason<Unit>>, +completion: D.Deferred<Arrival<A>>) -> IO(Arrival<A>):
  match result aborted:
    case D.Observation{resultTicket, resultCancellation} D.Observation{abortTicket, abortCancellation}:
      do IO<Arrival<A>>:
        resultWorker : Chan(Unit) <- IO.fork(Unit, observeResult(A, resultTicket, completion))
        abortWorker : Chan(Unit) <- IO.fork(Unit, observeAbort(A, abortTicket, completion))
        value : Arrival<A> <- D.result(Arrival<A>, completion)
        resultRemoved : Bool <- D.cancel(A, resultCancellation)
        abortRemoved : Bool <- D.cancel(Abort.AbortReason<Unit>, abortCancellation)
        IO.join(Unit, resultWorker)
        IO.join(Unit, abortWorker)
        D.dispose(Arrival<A>, completion)
        return value

def decide(-A: Data, result: D.Deferred<A>, cancelled: Maybe<&2, A>) -> IO(A):
  match cancelled:
    case Some{value}: IO.pure(A, value)
    case None{}: D.result(A, result)

def arrived(-A: Data, result: D.Deferred<A>, arrival: Arrival<A>, onAbort: IO(Maybe<&2, A>)) -> IO(A):
  match arrival:
    case Completed{value}: IO.pure(A, value)
    case Cancelled{}:
      do IO<A>:
        cancelled : Maybe<&2, A> <- onAbort
        decide(A, result, cancelled)

def await(-A: Data, +result: D.Deferred<A>, caller: Abort.AbortSignal<Unit>, onAbort: IO(Maybe<&2, A>)) -> IO(A):
  do IO<A>:
    completion : D.Deferred<Arrival<A>> <- D.new(Arrival<A>)
    observation : D.Observation<A> <- D.observe(A, result)
    aborted : D.Observation<Abort.AbortReason<Unit>> <- Abort.observe(Unit, caller)
    value : Arrival<A> <- observed(A, observation, aborted, completion)
    arrived(A, result, value, onAbort)

def run(-A: Data, +caller: Abort.AbortSignal<Unit>, operation: Abort.AbortSignal<Unit> -> IO(A), onAbort: IO(Maybe<&2, A>), cleanup: IO(Unit)) -> IO(A):
  do IO<A>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    link : Abort.Link<Unit> <- Abort.link(Unit, caller, controller)
    +result : D.Deferred<A> <- D.new(A)
    state : Ref.Ref<State> <- Ref.new(State, Active{False{}, False{}, cleanup})
    +task : Task<A> = Task{result, state, controller}
    worker : Chan(Unit) <- IO.fork(Unit, perform(A, task, operation))
    value : A <- await(A, result, caller, onAbort)
    Abort.unlink(Unit, link)
    depart(A, task, False{})
    return value

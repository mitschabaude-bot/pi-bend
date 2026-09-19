import Base
import ./abortable-socket.bend as S
import ./socket-writer.bend as W
import ./socket-interrupt.bend as I
import ./ref.bend as R
import ./abort.bend as A
import ./deferred.bend as D

# One upload task borrows the connection interrupt until stop joins it.
# Stopping competes atomically with write completion: an intentional stop must
# not turn the shutdown-induced write error into a failed response.
type State<-Reason: Data> is Data:
  Active{}
  Settled{result: Result<&2, &2, S.Error<Reason>, Unit>, reported: Bool}
  Stopped{}

type Error<-Reason: Data> is Data:
  WriteFailure{error: S.Error<Reason>, cleanup: Maybe<&2, I.Error>}
  InterruptFailure{error: I.Error}

type Owner<-Reason: Data> is Type:
  Owner{state: R.Ref<State<Reason>>, interrupt: I.Handle, task: Chan(Result<&2, &2, I.Error, Unit>)}

def borrowed(-Reason: Data, socket: Socket, signal: A.AbortSignal<Reason>, cancellation: D.Cancellation<A.AbortReason<Reason>>, watcher: Chan(Result<&2, &2, I.Error, Unit>), pair: I.Owner & I.Handle) -> S.Owner<Reason> & I.Handle:
  match pair:
    case (owner, handle): (S.Owner{socket, S.Lifetime{signal, owner, cancellation, watcher}}, handle)

# Borrowing never duplicates the affine interrupt owner.
def borrowConnection(-Reason: Data, owner: S.Owner<Reason>) -> S.Owner<Reason> & I.Handle:
  match owner:
    case S.Owner{socket, S.Lifetime{signal, owner, cancellation, watcher}}:
      borrowed(Reason, socket, signal, cancellation, watcher, I.borrow(owner))

def settle(-Reason: Data, state: State<Reason>, result: Result<&2, &2, S.Error<Reason>, Unit>) -> State<Reason> & Bool:
  match state result:
    case Active{} Done{_}: (Settled{Done{Unit{}}, False{}}, False{})
    case Active{} Fail{+error}: (Settled{Fail{error}, False{}}, True{})
    case previous _: (previous, False{})

def wake(handle: I.Handle, needed: Bool) -> IO(Result<&2, &2, I.Error, Unit>):
  match needed:
    case False{}: IO.pure(Result<&2, &2, I.Error, Unit>, Done{Unit{}})
    case True{}:
      do IO<Result<&2, &2, I.Error, Unit>>:
        result : Result<&2, &2, I.Error, Bool> <- I.cancel(handle)
        return S.cancelled(result)

def finished(-Reason: Data, state: R.Ref<State<Reason>>, handle: I.Handle, pair: W.Writer<Reason> & Result<&2, &2, S.Error<Reason>, Unit>) -> IO(Result<&2, &2, I.Error, Unit>):
  match pair:
    case (writer, result):
      do IO<Result<&2, &2, I.Error, Unit>>:
        failed : Bool <- R.modify(State<Reason>, Bool, state, previous => settle(Reason, previous, result))
        W.close(Reason, writer)
        wake(handle, failed)

def body(-Reason: Data, +state: R.Ref<State<Reason>>, handle: I.Handle, bytes: List<&2, U32>, pair: W.Writer<Reason> & Result<&2, &2, S.Error<Reason>, Unit>) -> IO(Result<&2, &2, I.Error, Unit>):
  match pair:
    case (writer, Fail{error}): finished(Reason, state, handle, (writer, Fail{error}))
    case (writer, Done{_}):
      do IO<Result<&2, &2, I.Error, Unit>>:
        result : W.Writer<Reason> & Result<&2, &2, S.Error<Reason>, Unit> <- W.send(Reason, writer, bytes)
        finished(Reason, state, handle, result)

def run(-Reason: Data, writer: W.Writer<Reason>, state: R.Ref<State<Reason>>, handle: I.Handle, head: List<&2, U32>, bytes: List<&2, U32>) -> IO(Result<&2, &2, I.Error, Unit>):
  do IO<Result<&2, &2, I.Error, Unit>>:
    result : W.Writer<Reason> & Result<&2, &2, S.Error<Reason>, Unit> <- W.send(Reason, writer, head)
    body(Reason, state, handle, bytes, result)

def launch(-Reason: Data, writer: W.Writer<Reason>, head: List<&2, U32>, bytes: List<&2, U32>, pair: S.Owner<Reason> & I.Handle) -> IO(S.Owner<Reason> & Result<&2, &1, S.Error<Reason>, Owner<Reason>>):
  match pair:
    case (connection, +handle):
      do IO<S.Owner<Reason> & Result<&2, &1, S.Error<Reason>, Owner<Reason>>>:
        +state : R.Ref<State<Reason>> <- R.new(State<Reason>, Active{})
        task : Chan(Result<&2, &2, I.Error, Unit>) <- IO.fork(Result<&2, &2, I.Error, Unit>, run(Reason, writer, state, handle, head, bytes))
        return (connection, Done{Owner{state, handle, task}})

def created(-Reason: Data, head: List<&2, U32>, bytes: List<&2, U32>, pair: S.Owner<Reason> & Result<&2, &1, S.Error<Reason>, W.Writer<Reason>>) -> IO(S.Owner<Reason> & Result<&2, &1, S.Error<Reason>, Owner<Reason>>):
  match pair:
    case (connection, Fail{error}): IO.pure(S.Owner<Reason> & Result<&2, &1, S.Error<Reason>, Owner<Reason>>, (connection, Fail{error}))
    case (connection, Done{writer}): launch(Reason, writer, head, bytes, borrowConnection(Reason, connection))

def start(-Reason: Data, connection: S.Owner<Reason>, head: List<&2, U32>, bytes: List<&2, U32>) -> IO(S.Owner<Reason> & Result<&2, &1, S.Error<Reason>, Owner<Reason>>):
  do IO<S.Owner<Reason> & Result<&2, &1, S.Error<Reason>, Owner<Reason>>>:
    pair : S.Owner<Reason> & Result<&2, &1, S.Error<Reason>, W.Writer<Reason>> <- W.create(Reason, connection)
    created(Reason, head, bytes, pair)

def observe(-Reason: Data, state: State<Reason>) -> State<Reason> & Maybe<&2, S.Error<Reason>>:
  match state:
    case Settled{Fail{+error}, _}: (Settled{Fail{error}, True{}}, Some{error})
    case previous: (previous, None{})

def check(-Reason: Data, owner: Owner<Reason>) -> IO(Owner<Reason> & Maybe<&2, S.Error<Reason>>):
  match owner:
    case Owner{+state, interrupt, task}:
      do IO<Owner<Reason> & Maybe<&2, S.Error<Reason>>>:
        error : Maybe<&2, S.Error<Reason>> <- R.modify(State<Reason>, Maybe<&2, S.Error<Reason>>, state, value => observe(Reason, value))
        return (Owner{state, interrupt, task}, error)

def stopping(-Reason: Data, state: State<Reason>) -> State<Reason> & Bool:
  match state:
    case Active{}: (Stopped{}, True{})
    case previous: (previous, False{})

def outcome(-Reason: Data, state: State<Reason>, cleanup: Result<&2, &2, I.Error, Unit>) -> Result<&2, &2, Error<Reason>, Unit>:
  match state cleanup:
    case Settled{Fail{error}, False{}} Done{_}: Fail{WriteFailure{error, None{}}}
    case Settled{Fail{error}, False{}} Fail{cleanup}: Fail{WriteFailure{error, Some{cleanup}}}
    case _ Fail{error}: Fail{InterruptFailure{error}}
    case _ Done{_}: Done{Unit{}}

def combined(left: Result<&2, &2, I.Error, Unit>, right: Result<&2, &2, I.Error, Unit>) -> Result<&2, &2, I.Error, Unit>:
  match left:
    case Fail{error}: Fail{error}
    case Done{_}: right

# Call before retiring the connection. A successful completed upload needs no
# shutdown; an unfinished one is interrupted. Joining precedes state disposal.
def stop(-Reason: Data, owner: Owner<Reason>) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  match owner:
    case Owner{+state, interrupt, task}:
      do IO<Result<&2, &2, Error<Reason>, Unit>>:
        needed : Bool <- R.modify(State<Reason>, Bool, state, value => stopping(Reason, value))
        stopped : Result<&2, &2, I.Error, Unit> <- wake(interrupt, needed)
        joined : Result<&2, &2, I.Error, Unit> <- IO.join(Result<&2, &2, I.Error, Unit>, task)
        value : State<Reason> <- R.dispose(State<Reason>, state)
        return outcome(Reason, value, combined(stopped, joined))

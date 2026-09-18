import Base
import ../../runtime/src/ref.bend as R
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/abort.bend as A

# The owner stores Agent state and queues together in State. Claiming a run and
# its pure preparation therefore share one transaction, with no effectful callback under
# the lock. ActiveRun handles are borrowed until the owner's final disposal.
type ActiveRun is Data:
  ActiveRun{completion: D.Deferred<Unit>, controller: A.AbortController<Unit>}
type Cell<-State: Data> is Data:
  Cell{value: State, active: Maybe<&2, ActiveRun>, retired: List<&2, ActiveRun>}
type Lifecycle<-State: Data> is Data:
  Lifecycle{cell: R.Ref<Cell<State>>}
type Prepared<-State: Data, -Value: Data> is Data:
  Prepared{state: State, value: Value}
type ClaimError<-Error: Data> is Data:
  Busy{}
  Rejected{error: Error}
type Claimed<-Value: Data> is Data:
  Claimed{run: ActiveRun, value: Value}

def new(-State: Data, value: State) -> IO(Lifecycle<State>):
  do IO<Lifecycle<State>>:
    cell : R.Ref<Cell<State>> <- R.new(Cell<State>, Cell{value, None{}, Nil{}})
    return Lifecycle{cell}
def createRun() -> IO(ActiveRun):
  do IO<ActiveRun>:
    completion : D.Deferred<Unit> <- D.new(Unit)
    controller : A.AbortController<Unit> <- A.new(Unit)
    return ActiveRun{completion, controller}
def disposeRun(run: ActiveRun) -> IO(Unit):
  match run:
    case ActiveRun{completion, controller}:
      do IO<Unit>:
        D.dispose(Unit, completion)
        A.dispose(Unit, controller)
def same(left: ActiveRun, right: ActiveRun) -> Bool:
  match left right:
    case ActiveRun{D.Deferred{a}, _} ActiveRun{D.Deferred{b}, _}: R.same(D.State<Unit>, a, b)
def signal(run: ActiveRun) -> A.AbortSignal<Unit>:
  match run:
    case ActiveRun{_, controller}: A.signal(Unit, controller)
def prepared(-State: Data, -Error: Data, -Value: Data, original: State, retired: List<&2, ActiveRun>, +run: ActiveRun, result: Result<&2, &2, Error, Prepared<State, Value>>) -> Cell<State> & Result<&2, &2, ClaimError<Error>, Claimed<Value>>:
  match result:
    case Fail{error}: (Cell{original, None{}, retired}, Fail{Rejected{error}})
    case Done{Prepared{next, value}}: (Cell{next, Some{run}, retired}, Done{Claimed{run, value}})
def claimState(-State: Data, -Error: Data, -Value: Data, cell: Cell<State>, run: ActiveRun, prepare: State -> Result<&2, &2, Error, Prepared<State, Value>>) -> Cell<State> & Result<&2, &2, ClaimError<Error>, Claimed<Value>>:
  match cell:
    case Cell{value, Some{active}, retired}: (Cell{value, Some{active}, retired}, Fail{Busy{}})
    case Cell{+value, None{}, retired}: prepared(State, Error, Value, value, retired, run, prepare(value))
def claimed(-Error: Data, -Value: Data, candidate: ActiveRun, result: Result<&2, &2, ClaimError<Error>, Claimed<Value>>) -> IO(Result<&2, &2, ClaimError<Error>, Claimed<Value>>):
  match result:
    case Done{value}: IO.pure(Result<&2, &2, ClaimError<Error>, Claimed<Value>>, Done{value})
    case Fail{error}:
      do IO<Result<&2, &2, ClaimError<Error>, Claimed<Value>>>:
        disposeRun(candidate)
        return Fail{error}
def claim(-State: Data, -Error: Data, -Value: Data, owner: Lifecycle<State>, prepare: State -> Result<&2, &2, Error, Prepared<State, Value>>) -> IO(Result<&2, &2, ClaimError<Error>, Claimed<Value>>):
  match owner:
    case Lifecycle{cell}:
      do IO<Result<&2, &2, ClaimError<Error>, Claimed<Value>>>:
        +candidate : ActiveRun <- createRun()
        result : Result<&2, &2, ClaimError<Error>, Claimed<Value>> <- R.modify(Cell<State>, Result<&2, &2, ClaimError<Error>, Claimed<Value>>, cell, current => claimState(State, Error, Value, current, candidate, prepare))
        claimed(Error, Value, candidate, result)
def readValue(-State: Data, cell: Cell<State>) -> State:
  match cell:
    case Cell{value, _, _}: value
def read(-State: Data, owner: Lifecycle<State>) -> IO(State):
  match owner:
    case Lifecycle{cell}:
      do IO<State>:
        current : Cell<State> <- R.read(Cell<State>, cell)
        return readValue(State, current)
def activeValue(-State: Data, cell: Cell<State>) -> Maybe<&2, ActiveRun>:
  match cell:
    case Cell{_, active, _}: active
def activeRun(-State: Data, owner: Lifecycle<State>) -> IO(Maybe<&2, ActiveRun>):
  match owner:
    case Lifecycle{cell}:
      do IO<Maybe<&2, ActiveRun>>:
        current : Cell<State> <- R.read(Cell<State>, cell)
        return activeValue(State, current)
def waitRun(active: Maybe<&2, ActiveRun>) -> IO(Unit):
  match active:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ActiveRun{completion, _}}: D.result(Unit, completion)
def waitForIdle(-State: Data, owner: Lifecycle<State>) -> IO(Unit):
  do IO<Unit>:
    active : Maybe<&2, ActiveRun> <- activeRun(State, owner)
    waitRun(active)
def abortRun(active: Maybe<&2, ActiveRun>) -> IO(Unit):
  match active:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ActiveRun{_, controller}}:
      do IO<Unit>:
        won : Bool <- A.abort(Unit, controller, None{})
        return Unit{}
def abort(-State: Data, owner: Lifecycle<State>) -> IO(Unit):
  do IO<Unit>:
    active : Maybe<&2, ActiveRun> <- activeRun(State, owner)
    abortRun(active)

# Called only after the executor and all awaited listeners have settled.
# A stale finishing handle cannot clear a newer run or reapply the reduction.
def finishMatched(-State: Data, value: State, +active: ActiveRun, retired: List<&2, ActiveRun>, reduce: State -> State, matches: Bool) -> Cell<State> & Bool:
  match matches:
    case True{}: (Cell{reduce(value), None{}, active <> retired}, True{})
    case False{}: (Cell{value, Some{active}, retired}, False{})
def finishState(-State: Data, cell: Cell<State>, run: ActiveRun, reduce: State -> State) -> Cell<State> & Bool:
  match cell:
    case Cell{value, None{}, retired}: (Cell{value, None{}, retired}, False{})
    case Cell{value, Some{+active}, retired}: finishMatched(State, value, active, retired, reduce, same(active, run))
def settle(run: ActiveRun, won: Bool) -> IO(Bool):
  match run won:
    case ActiveRun{completion, _} True{}:
      do IO<Bool>:
        settled : Bool <- D.resolve(Unit, completion, Unit{})
        return True{}
    case _ False{}: IO.pure(Bool, False{})
def finish(-State: Data, owner: Lifecycle<State>, +run: ActiveRun, reduce: State -> State) -> IO(Bool):
  match owner:
    case Lifecycle{cell}:
      do IO<Bool>:
        won : Bool <- R.modify(Cell<State>, Bool, cell, current => finishState(State, current, run, reduce))
        settle(run, won)

type RunError<-Error: Data> is Data:
  ClaimFailed{error: ClaimError<Error>}
  CallbackFailed{error: Error}
def recoverResult(-Error: Data, run: ActiveRun, result: Result<&2, &2, Error, Unit>, recover: ActiveRun -> Error -> IO(Result<&2, &2, Error, Unit>)) -> IO(Result<&2, &2, Error, Unit>):
  match result:
    case Done{value}: IO.pure(Result<&2, &2, Error, Unit>, Done{value})
    case Fail{error}: recover(run, error)
def runResult(-Error: Data, result: Result<&2, &2, Error, Unit>) -> Result<&2, &2, RunError<Error>, Unit>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{CallbackFailed{error}}
def executeClaim(-State: Data, -Error: Data, -Value: Data, owner: Lifecycle<State>, claimResult: Result<&2, &2, ClaimError<Error>, Claimed<Value>>, execute: Claimed<Value> -> IO(Result<&2, &2, Error, Unit>), recover: ActiveRun -> Error -> IO(Result<&2, &2, Error, Unit>), reduce: State -> State) -> IO(Result<&2, &2, RunError<Error>, Unit>):
  match claimResult:
    case Fail{error}: IO.pure(Result<&2, &2, RunError<Error>, Unit>, Fail{ClaimFailed{error}})
    case Done{Claimed{+run, value}}:
      do IO<Result<&2, &2, RunError<Error>, Unit>>:
        result : Result<&2, &2, Error, Unit> <- execute(Claimed{run, value})
        recovered : Result<&2, &2, Error, Unit> <- recoverResult(Error, run, result, recover)
        finished : Bool <- finish(State, owner, run, reduce)
        return runResult(Error, recovered)
# Like Agent.runWithLifecycle: recovery handles executor failure, and final
# state/idle settlement happens even when recovery itself returns an error.
def runWithLifecycle(-State: Data, -Error: Data, -Value: Data, +owner: Lifecycle<State>, prepare: State -> Result<&2, &2, Error, Prepared<State, Value>>, execute: Claimed<Value> -> IO(Result<&2, &2, Error, Unit>), recover: ActiveRun -> Error -> IO(Result<&2, &2, Error, Unit>), reduce: State -> State) -> IO(Result<&2, &2, RunError<Error>, Unit>):
  do IO<Result<&2, &2, RunError<Error>, Unit>>:
    result : Result<&2, &2, ClaimError<Error>, Claimed<Value>> <- claim(State, Error, Value, owner, prepare)
    executeClaim(State, Error, Value, owner, result, execute, recover, reduce)

def disposeRuns(runs: List<&2, ActiveRun>) -> IO(Unit):
  match runs:
    case Nil{}: IO.pure(Unit, Unit{})
    case run <> rest:
      do IO<Unit>:
        disposeRun(run)
        disposeRuns(rest)
def disposed(-State: Data, cell: Cell<State>) -> IO(State):
  match cell:
    case Cell{value, None{}, retired}:
      do IO<State>:
        disposeRuns(retired)
        return value
    case Cell{_, Some{_}, _}: IO.die(State, 1, "Agent lifecycle disposed during an active run")
# Retire owner/run/signal aliases and drain waiters before final disposal.
# Completed signals remain inspectable throughout the owner's lifetime.
def dispose(-State: Data, owner: Lifecycle<State>) -> IO(State):
  match owner:
    case Lifecycle{cell}:
      do IO<State>:
        previous : Cell<State> <- R.dispose(Cell<State>, cell)
        disposed(State, previous)

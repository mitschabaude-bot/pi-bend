import Base
import ../../runtime/src/callback.bend as C

# The per-call operation owns preparation, execution, finalization and result
# delivery. The scheduler owns ordering, cancellation boundaries and reduction.
# State changes are explicit values carried into the next invocation.
type Invocation<-State: Data, -Call: Data> is Data:
  Invocation{state: State, call: Call}

type Completed<-State: Data, -Message: Data> is Data:
  Completed{state: State, message: Message, terminate: Bool}

type Batch<-State: Data, -Message: Data> is Data:
  Batch{state: State, messages: List<&2, Message>, terminate: Bool}

type Step<-State: Data, -Message: Data, -Error: Data> is Data:
  Ready{state: State}
  Yielded{completed: Completed<State, Message>}
  Failed{error: Error}
  Cancelled{state: State}

def completedStep(-State: Data, -Message: Data, -Error: Data, result: Result<&2, &2, Error, Completed<State, Message>>) -> Step<State, Message, Error>:
  match result:
    case Done{value}: Yielded{value}
    case Fail{error}: Failed{error}

def afterAbort(-State: Data, -Message: Data, -Error: Data, stopped: Bool, state: State) -> Step<State, Message, Error>:
  match stopped:
    case True{}: Cancelled{state}
    case False{}: Ready{state}

def nonempty(-Message: Data, values: List<&2, Message>) -> Bool:
  match values:
    case Nil{}: False{}
    case _ <> _: True{}

def finish(-State: Data, -Message: Data, -Error: Data, state: State, +reversed: List<&2, Message>, allTerminate: Bool) -> IO(Result<&2, &2, Error, Batch<State, Message>>):
  IO.pure(Result<&2, &2, Error, Batch<State, Message>>, Done{Batch{state, List.reverse(&2, Message, reversed), nonempty(Message, reversed) && allTerminate}})

# Check abort only after a completed per-call operation has delivered its
# message. Even an initially aborted signal permits the first immediate result.
# A terminate flag never skips remaining calls; all completed calls must opt in.
# Each Ready consumes a call; Yielded and Failed/Cancelled settle that call.
@unsafe
def sequential(-State: Data, -Call: Data, -Message: Data, -Error: Data, calls: List<&2, Call>, step: Step<State, Message, Error>, reversed: List<&2, Message>, allTerminate: Bool, +invoke: C.Callback<Invocation<State, Call>, Result<&2, &2, Error, Completed<State, Message>>>, +aborted: C.Callback<Unit, Bool>) -> IO(Result<&2, &2, Error, Batch<State, Message>>):
  match calls step:
    case _ Failed{error}: IO.pure(Result<&2, &2, Error, Batch<State, Message>>, Fail{error})
    case _ Cancelled{state}: finish(State, Message, Error, state, reversed, allTerminate)
    case Nil{} Ready{state}: finish(State, Message, Error, state, reversed, allTerminate)
    case call <> rest Ready{state}:
      do IO<Result<&2, &2, Error, Batch<State, Message>>>:
        result : Result<&2, &2, Error, Completed<State, Message>> <- C.call(Invocation<State, Call>, Result<&2, &2, Error, Completed<State, Message>>, invoke, Invocation{state, call})
        sequential(State, Call, Message, Error, rest, completedStep(State, Message, Error, result), reversed, allTerminate, invoke, aborted)
    case remaining Yielded{Completed{state, message, terminate}}:
      do IO<Result<&2, &2, Error, Batch<State, Message>>>:
        stopped : Bool <- C.call(Unit, Bool, aborted, Unit{})
        sequential(State, Call, Message, Error, remaining, afterAbort(State, Message, Error, stopped, state), message <> reversed, allTerminate && terminate, invoke, aborted)

def executeSequential(-State: Data, -Call: Data, -Message: Data, -Error: Data, state: State, calls: List<&2, Call>, invoke: C.Callback<Invocation<State, Call>, Result<&2, &2, Error, Completed<State, Message>>>, aborted: C.Callback<Unit, Bool>) -> IO(Result<&2, &2, Error, Batch<State, Message>>):
  sequential(State, Call, Message, Error, calls, Ready{state}, Nil{}, True{}, invoke, aborted)

import Base
import ../src/agent-loop.bend as B
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ./tool-batch-sequential.bend as S
import ./tool-batch-policy.bend as T

type Gates is Data:
  Gates{started: Chan(Unit), release: Chan(Unit), finished: R.Ref<Bool>}

def execute(gates: Gates, input: S.Input()) -> IO(S.Output()):
  match gates input:
    case Gates{started, release, finished} B.Invocation{state, S.Call{1, _, _}}:
      do IO<S.Output()>:
        T.assertion(U32.is_eq(state, 0), "first call receives initial state")
        sent : Bool <- Chan.send(Unit, started, Unit{})
        T.assertion(sent, "start gate remains open")
        released : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        R.write(Bool, finished, True{})
        return Done{B.BatchCompleted{1, 1, True{}}}
    case Gates{_, _, finished} B.Invocation{state, S.Call{2, _, _}}:
      do IO<S.Output()>:
        previousFinished : Bool <- R.read(Bool, finished)
        T.assertion(previousFinished && U32.is_eq(state, 1), "second call waits for first completion and receives returned state")
        return Done{B.BatchCompleted{3, 2, True{}}}
    case _ _: IO.die(S.Output(), 1, "unexpected gated call")

def notAborted(unused: Unit, input: Unit) -> IO(Bool): IO.pure(Bool, False{})

def background(execute: C.Callback<S.Input(), S.Output()>, cancel: C.Callback<Unit, Bool>, reply: Chan(S.Outcome())) -> IO(Unit):
  do IO<Unit>:
    result : S.Outcome() <- B.executeSequential(U32, S.Call, U32, String, 0, S.Call{1, True{}, False{}} <> S.Call{2, True{}, False{}} <> Nil{}, execute, cancel)
    sent : Bool <- Chan.send(S.Outcome(), reply, result)
    T.assertion(sent, "batch result receiver remains open")

def checked(result: Maybe<&1, S.Outcome()>) -> IO(Unit):
  match result:
    case Some{actual}: T.assertion(S.outcome(actual, Done{B.Batch{3, 1 <> 2 <> Nil{}, True{}}}), "gated batch result")
    case None{}: T.assertion(False{}, "batch ended without result")

def main() -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +finished : R.Ref<Bool> <- R.new(Bool, False{})
    +reply : Chan(S.Outcome()) <- Chan.new(S.Outcome(), 1)
    +invoke : C.Callback<S.Input(), S.Output()> <- C.create(~Gates, ~S.Input(), ~S.Output(), ~execute, Gates{started, release, finished})
    +cancel : C.Callback<Unit, Bool> <- C.create(~Unit, ~Unit, ~Bool, ~notAborted, Unit{})
    IO.spawn(Unit, background(invoke, cancel, reply))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    beforeRelease : Bool <- R.read(Bool, finished)
    T.assertion(Bool.not(beforeRelease), "first call is suspended at its delivery boundary")
    sent : Bool <- Chan.send(Unit, release, Unit{})
    T.assertion(sent, "release gate remains open")
    result : Maybe<&1, S.Outcome()> <- Chan.recv(S.Outcome(), reply)
    checked(result)
    C.dispose(S.Input(), S.Output(), invoke)
    C.dispose(Unit, Bool, cancel)
    finished : Bool <- R.dispose(Bool, finished)
    Chan.close(Unit, started)
    Chan.close(Unit, release)
    Chan.close(S.Outcome(), reply)
    IO.print("PASS gated sequential batch execution and returned-state propagation")

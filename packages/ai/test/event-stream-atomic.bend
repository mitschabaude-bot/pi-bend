import Base
import ../src/utils/event-stream.bend as S
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/deferred.bend as D
import ../../agent/test/message-events.bend as Test

type Gate is Data:
  Gate{entered: Chan(Unit), release: Chan(Unit)}

def complete(unused: Unit, value: U32) -> IO(Bool): IO.pure(Bool, True{})
def extract(gate: Gate, value: U32) -> IO(U32):
  match gate:
    case Gate{entered, release}:
      do IO<U32>:
        sent : Bool <- Chan.send(Unit, entered, Unit{})
        R.requireSent(sent)
        released : Unit <- IO.join(Unit, release)
        return value

def yielded(value: S.Iteration<U32>, expected: U32) -> IO(Unit):
  match value:
    case S.Yield{actual}: Test.assertion(U32.is_eq(actual, expected), "terminal event value")
    case S.End{}: Test.assertion(False{}, "terminal event must be visible before iteration ends")

def terminalPublication() -> IO(Unit):
  do IO<Unit>:
    +entered : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +predicate : C.Callback<U32, Bool> <- C.create(~Unit, ~U32, ~Bool, ~complete, Unit{})
    +extractor : C.Callback<U32, U32> <- C.create(~Gate, ~U32, ~U32, ~extract, Gate{entered, release})
    +stream : S.EventStream<U32, U32> <- S.create(U32, U32, predicate, extractor)
    +iterator : S.Iterator<U32, U32> <- S.iterator(U32, U32, stream)
    pushed : Chan(Unit) <- IO.fork(Unit, S.push(U32, U32, stream, 7))
    extracting : Unit <- IO.join(Unit, entered)
    # next registers while terminal extraction is suspended. It must wait for
    # the event instead of treating a partially committed push as end-of-stream.
    +next : D.Deferred<S.Iteration<U32>> <- S.next(U32, U32, iterator)
    sent : Bool <- Chan.send(Unit, release, Unit{})
    R.requireSent(sent)
    finished : Unit <- IO.join(Unit, pushed)
    value : S.Iteration<U32> <- D.result(S.Iteration<U32>, next)
    yielded(value, 7)
    D.dispose(S.Iteration<U32>, next)
    result : U32 <- S.resultValue(U32, U32, stream)
    Test.assertion(U32.is_eq(result, 7), "terminal result preserved")
    S.end(U32, U32, stream, None{})
    S.disposeIterator(U32, U32, iterator)
    S.dispose(U32, U32, stream)
    C.dispose(U32, Bool, predicate)
    C.dispose(U32, U32, extractor)

def identity(unused: Unit, value: U32) -> IO(U32): IO.pure(U32, value)

def delayedPredicate(gate: Gate, value: U32) -> IO(Bool):
  do IO<Bool>:
    ignored : U32 <- extract(gate, value)
    return False{}

def ended(value: S.Iteration<U32>) -> IO(Unit):
  match value:
    case S.End{}: IO.pure(Unit, Unit{})
    case _: Test.assertion(False{}, "a push suspended before close must not publish afterwards")

def closeDuringPush() -> IO(Unit):
  do IO<Unit>:
    +entered : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +predicate : C.Callback<U32, Bool> <- C.create(~Gate, ~U32, ~Bool, ~delayedPredicate, Gate{entered, release})
    +extractor : C.Callback<U32, U32> <- C.create(~Unit, ~U32, ~U32, ~identity, Unit{})
    +stream : S.EventStream<U32, U32> <- S.create(U32, U32, predicate, extractor)
    +iterator : S.Iterator<U32, U32> <- S.iterator(U32, U32, stream)
    pushed : Chan(Unit) <- IO.fork(Unit, S.push(U32, U32, stream, 7))
    checking : Unit <- IO.join(Unit, entered)
    S.end(U32, U32, stream, Some{99})
    sent : Bool <- Chan.send(Unit, release, Unit{})
    R.requireSent(sent)
    finished : Unit <- IO.join(Unit, pushed)
    value : S.Iteration<U32> <- S.nextValue(U32, U32, iterator)
    ended(value)
    result : U32 <- S.resultValue(U32, U32, stream)
    Test.assertion(U32.is_eq(result, 99), "close retains its final result")
    S.disposeIterator(U32, U32, iterator)
    S.dispose(U32, U32, stream)
    C.dispose(U32, Bool, predicate)
    C.dispose(U32, U32, extractor)

def winner(value: S.Iteration<U32>, result: U32) -> IO(Unit):
  match value:
    case S.Yield{event}: Test.assertion(U32.is_eq(event, 7) && U32.is_eq(result, 7), "terminal event and first final result commit together")
    case S.End{}: Test.assertion(U32.is_eq(result, 9), "close wins only when the terminal event was not committed")

def race(+predicate: C.Callback<U32, Bool>, +extractor: C.Callback<U32, U32>) -> IO(Unit):
  do IO<Unit>:
    +stream : S.EventStream<U32, U32> <- S.create(U32, U32, predicate, extractor)
    +iterator : S.Iterator<U32, U32> <- S.iterator(U32, U32, stream)
    pushed : Chan(Unit) <- IO.fork(Unit, S.push(U32, U32, stream, 7))
    closed : Chan(Unit) <- IO.fork(Unit, S.end(U32, U32, stream, Some{9}))
    pushDone : Unit <- IO.join(Unit, pushed)
    closeDone : Unit <- IO.join(Unit, closed)
    value : S.Iteration<U32> <- S.nextValue(U32, U32, iterator)
    result : U32 <- S.resultValue(U32, U32, stream)
    winner(value, result)
    S.disposeIterator(U32, U32, iterator)
    S.dispose(U32, U32, stream)

def races(count: Nat, +predicate: C.Callback<U32, Bool>, +extractor: C.Callback<U32, U32>) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        race(predicate, extractor)
        races(rest, predicate, extractor)

def main() -> IO(Unit):
  do IO<Unit>:
    terminalPublication()
    closeDuringPush()
    +predicate : C.Callback<U32, Bool> <- C.create(~Unit, ~U32, ~Bool, ~complete, Unit{})
    +extractor : C.Callback<U32, U32> <- C.create(~Unit, ~U32, ~U32, ~identity, Unit{})
    races(128n, predicate, extractor)
    C.dispose(U32, Bool, predicate)
    C.dispose(U32, U32, extractor)
    IO.print("PASS gated atomic terminal publication, close during push, and 128 completion/close races")

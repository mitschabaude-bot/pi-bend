import Base
import ../src/concurrent-all.bend as A
import ../src/callback.bend as C
import ../src/ref.bend as R

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

type Work is Data:
  Work{id: U32, release: Chan(Unit), fail: Bool}

def execute(started: Chan(U32), work: Work) -> IO(Result<&2, &2, U32, U32>):
  match work:
    case Work{+id, release, fail}:
      do IO<Result<&2, &2, U32, U32>>:
        sent : Bool <- Chan.send(U32, started, id)
        R.requireSent(sent)
        released : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return Bool.pick(Result<&2, &2, U32, U32>, fail, Fail{id}, Done{id})

def release(+gate: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Unit, gate, Unit{})
    R.requireSent(sent)

def id(result: Maybe<&1, U32>) -> U32:
  match result:
    case Some{value}: value
    case None{}: 0

def success(result: Result<&2, &2, U32, List<&2, U32>>) -> Bool:
  match result:
    case Done{1 <> 2 <> 3 <> Nil{}}: True{}
    case _: False{}

def failed(result: Result<&2, &2, U32, List<&2, U32>>) -> Bool:
  match result:
    case Fail{2}: True{}
    case _: False{}

def empty(result: Result<&2, &2, U32, List<&2, U32>>) -> Bool:
  match result:
    case Done{Nil{}}: True{}
    case _: False{}

def checkEarly(failure: Bool, +run: A.Run<U32, U32>) -> IO(Unit):
  match failure:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        result : Result<&2, &2, U32, List<&2, U32>> <- A.result(U32, U32, run)
        assertion(failed(result), "failure settles while earlier and later siblings remain suspended")
        again : Result<&2, &2, U32, List<&2, U32>> <- A.result(U32, U32, run)
        assertion(failed(again), "failure remains stable for repeat observers")

def scenario(+failure: Bool) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(U32) <- Chan.new(U32, 3)
    +first : Chan(Unit) <- Chan.new(Unit, 1)
    +second : Chan(Unit) <- Chan.new(Unit, 1)
    +third : Chan(Unit) <- Chan.new(Unit, 1)
    +callback : C.Callback<Work, Result<&2, &2, U32, U32>> <- C.create(~Chan(U32), ~Work, ~Result<&2, &2, U32, U32>, ~execute, started)
    +run : A.Run<U32, U32> <- A.start(Work, U32, U32, Work{1, first, failure} <> Work{2, second, failure} <> Work{3, third, False{}} <> Nil{}, callback)
    a : Maybe<&1, U32> <- Chan.recv(U32, started)
    b : Maybe<&1, U32> <- Chan.recv(U32, started)
    c : Maybe<&1, U32> <- Chan.recv(U32, started)
    assertion(U32.is_eq(U32.add(U32.add(id(a), id(b)), id(c)), 6), "every callback starts before any is released")
    release(second)
    checkEarly(failure, run)
    release(third)
    release(first)
    +result : Result<&2, &2, U32, List<&2, U32>> <- A.result(U32, U32, run)
    assertion(Bool.pick(Bool, failure, failed(result), success(result)), "ordered success or first temporal failure")
    A.dispose(U32, U32, run)
    C.dispose(Work, Result<&2, &2, U32, U32>, callback)
    Chan.close(U32, started)
    Chan.close(Unit, first)
    Chan.close(Unit, second)
    Chan.close(Unit, third)
    return Unit{}

def numbers(count: Nat) -> List<&2, Nat>:
  match count:
    case Zero{}: Nil{}
    case Succ{+rest}: Succ{rest} <> numbers(rest)

def identity(unused: Unit, input: Nat) -> IO(Result<&2, &2, U32, Nat>):
  IO.pure(Result<&2, &2, U32, Nat>, Done{input})

def sameNumbers(left: List<&2, Nat>, right: List<&2, Nat>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> rest b <> tail: Nat.is_eq(a, b) && sameNumbers(rest, tail)
    case _ _: False{}

def manyResult(expected: List<&2, Nat>, result: Result<&2, &2, U32, List<&2, Nat>>) -> Bool:
  match result:
    case Done{actual}: sameNumbers(expected, actual)
    case Fail{_}: False{}

def many() -> IO(Unit):
  do IO<Unit>:
    +callback : C.Callback<Nat, Result<&2, &2, U32, Nat>> <- C.create(~Unit, ~Nat, ~Result<&2, &2, U32, Nat>, ~identity, Unit{})
    +run : A.Run<U32, Nat> <- A.start(Nat, U32, Nat, numbers(256n), callback)
    result : Result<&2, &2, U32, List<&2, Nat>> <- A.result(U32, Nat, run)
    assertion(manyResult(numbers(256n), result), "256 concurrent completions retain every value in input order")
    A.dispose(U32, Nat, run)
    C.dispose(Nat, Result<&2, &2, U32, Nat>, callback)

def main() -> IO(Unit):
  do IO<Unit>:
    +started : Chan(U32) <- Chan.new(U32, 1)
    +callback : C.Callback<Work, Result<&2, &2, U32, U32>> <- C.create(~Chan(U32), ~Work, ~Result<&2, &2, U32, U32>, ~execute, started)
    +run : A.Run<U32, U32> <- A.start(Work, U32, U32, Nil{}, callback)
    result : Result<&2, &2, U32, List<&2, U32>> <- A.result(U32, U32, run)
    assertion(empty(result), "empty collection resolves successfully")
    A.dispose(U32, U32, run)
    C.dispose(Work, Result<&2, &2, U32, U32>, callback)
    Chan.close(U32, started)
    scenario(False{})
    scenario(True{})
    many()
    IO.print("PASS concurrent all: empty, concurrent start, ordered results, prompt first failure, sibling drain, repeat observation, 256 completions")

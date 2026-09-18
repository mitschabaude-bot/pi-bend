import Base
import ../src/tool-batch.bend as B
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ./tool-batch-policy.bend as T

type Call is Data:
  Call{id: U32, terminate: Bool, fail: Bool}
type Observed is Data:
  Observed{visited: List<&2, U32>, entered: U32, checks: U32}
type Environment is Data:
  Environment{observed: R.Ref<Observed>, stopAfter: U32}
def Input() -> Data: B.Invocation<U32, Call>
def Output() -> Data: Result<&2, &2, String, B.Completed<U32, U32>>
def Outcome() -> Data: Result<&2, &2, String, B.Batch<U32, U32>>

def enter(id: U32, state: Observed) -> Observed & Unit:
  match state:
    case Observed{visited, count, checks}: (Observed{id <> visited, (count + 1 : U32), checks}, Unit{})

def result(fail: Bool, +state: U32, terminate: Bool) -> Output():
  match fail:
    case True{}: Fail{"delivery failed"}
    case False{}: Done{B.Completed{state, state, terminate}}

def invoke(environment: Environment, input: Input()) -> IO(Output()):
  match environment input:
    case Environment{observed, _} B.Invocation{state, Call{+id, terminate, fail}}:
      do IO<Output()>:
        R.modify(Observed, Unit, observed, old => enter(id, old))
        return result(fail, (state + id : U32), terminate)

def inspected(stopAfter: U32, state: Observed) -> Observed & Bool:
  match state:
    case Observed{visited, +entered, checks}: (Observed{visited, entered, (checks + 1 : U32)}, U32.is_ge(entered, stopAfter))

def aborted(environment: Environment, unused: Unit) -> IO(Bool):
  match environment:
    case Environment{observed, stopAfter}: R.modify(Observed, Bool, observed, old => inspected(stopAfter, old))

def equal(left: List<&2, U32>, right: List<&2, U32>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> xs b <> ys: U32.is_eq(a, b) && equal(xs, ys)
    case _ _: False{}

def outcome(actual: Outcome(), expected: Outcome()) -> Bool:
  match actual expected:
    case Fail{a} Fail{b}: String.eq(a, b)
    case Done{B.Batch{a, am, at}} Done{B.Batch{b, bm, bt}}: U32.is_eq(a, b) && equal(am, bm) && String.eq(Bool.show(at), Bool.show(bt))
    case _ _: False{}

def observations(actual: Observed, visited: List<&2, U32>, checks: U32) -> Bool:
  match actual:
    case Observed{actual, _, count}: equal(List.reverse(&2, U32, actual), visited) && U32.is_eq(count, checks)

def check(calls: List<&2, Call>, state: U32, +stopAfter: U32, expected: Outcome(), visited: List<&2, U32>, checks: U32, +label: String) -> IO(Unit):
  do IO<Unit>:
    +observed : R.Ref<Observed> <- R.new(Observed, Observed{Nil{}, 0, 0})
    +execute : C.Callback<Input(), Output()> <- C.create(~Environment, ~Input(), ~Output(), ~invoke, Environment{observed, stopAfter})
    +cancel : C.Callback<Unit, Bool> <- C.create(~Environment, ~Unit, ~Bool, ~aborted, Environment{observed, stopAfter})
    actual : Outcome() <- B.executeSequential(U32, Call, U32, String, state, calls, execute, cancel)
    T.assertion(outcome(actual, expected), "sequential batch result: " ++ label)
    C.dispose(Input(), Output(), execute)
    C.dispose(Unit, Bool, cancel)
    observed : Observed <- R.dispose(Observed, observed)
    T.assertion(observations(observed, visited, checks), "sequential batch invocation/cancellation order: " ++ label)

import Base
import ../src/utils/event-stream.bend as E
import ../../runtime/src/callback.bend as C
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/ref.bend as Ref

# Direct port of packages/ai/test/event-stream.test.ts at 46c9de402.
# These cases use exact small integers, represented by U32 in this generic API.
def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def predicate(complete: Bool, value: U32) -> IO(Bool):
  IO.pure(Bool, complete && U32.is_eq(value, 3))

def identity(unused: Unit, value: U32) -> IO(U32): IO.pure(U32, value)
def stringify(unused: Unit, value: U32) -> IO(String): IO.pure(String, U32.show(value))

type Fixture is Data:
  Fixture{stream: E.EventStream<U32, U32>, predicate: C.Callback<U32, Bool>, extract: C.Callback<U32, U32>}

def fixture(complete: Bool) -> IO(Fixture):
  do IO<Fixture>:
    +check : C.Callback<U32, Bool> <- C.create(~Bool, ~U32, ~Bool, ~predicate, complete)
    +extract : C.Callback<U32, U32> <- C.create(~Unit, ~U32, ~U32, ~identity, Unit{})
    stream : E.EventStream<U32, U32> <- E.create(U32, U32, check, extract)
    return Fixture{stream, check, extract}

def streamOf(value: Fixture) -> E.EventStream<U32, U32>:
  match value:
    case Fixture{stream, _, _}: stream

def disposeFixture(value: Fixture) -> IO(Unit):
  match value:
    case Fixture{stream, check, extract}:
      do IO<Unit>:
        E.dispose(U32, U32, stream)
        C.dispose(U32, Bool, check)
        C.dispose(U32, U32, extract)

def expect(value: E.Iteration<U32>, expected: Maybe<&2, U32>) -> IO(Unit):
  match value expected:
    case E.Yield{a} Some{b}: assertion(U32.is_eq(a, b), "unexpected yielded value")
    case E.End{} None{}: IO.pure(Unit, Unit{})
    case _ _: assertion(False{}, "unexpected iterator done flag")

def expectNext(-R: Data, cursor: E.Iterator<U32, R>, expected: Maybe<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    value : E.Iteration<U32> <- E.nextValue(U32, R, cursor)
    expect(value, expected)

def expectPromise(+promise: D.Deferred<E.Iteration<U32>>, expected: Maybe<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    value : E.Iteration<U32> <- D.result(E.Iteration<U32>, promise)
    expect(value, expected)
    D.dispose(E.Iteration<U32>, promise)

def bufferedCompletion() -> IO(Unit):
  do IO<Unit>:
    +f : Fixture <- fixture(True{})
    +stream : E.EventStream<U32, U32> = streamOf(f)
    E.push(U32, U32, stream, 1)
    E.push(U32, U32, stream, 2)
    E.push(U32, U32, stream, 3)
    E.push(U32, U32, stream, 4)
    value : U32 <- E.resultValue(U32, U32, stream)
    assertion(U32.is_eq(value, 3), "completion result")
    +cursor : E.Iterator<U32, U32> <- E.iterator(U32, U32, stream)
    expectNext(U32, cursor, Some{1})
    expectNext(U32, cursor, Some{2})
    expectNext(U32, cursor, Some{3})
    expectNext(U32, cursor, None{})
    E.disposeIterator(U32, U32, cursor)
    disposeFixture(f)
    IO.print("PASS drains buffered events in order and ignores events pushed after completion")

def interleavedBuffer() -> IO(Unit):
  do IO<Unit>:
    +f : Fixture <- fixture(False{})
    +stream : E.EventStream<U32, U32> = streamOf(f)
    E.push(U32, U32, stream, 1)
    E.push(U32, U32, stream, 2)
    +cursor : E.Iterator<U32, U32> <- E.iterator(U32, U32, stream)
    expectNext(U32, cursor, Some{1})
    E.push(U32, U32, stream, 3)
    expectNext(U32, cursor, Some{2})
    expectNext(U32, cursor, Some{3})
    E.end(U32, U32, stream, Some{3})
    expectNext(U32, cursor, None{})
    E.disposeIterator(U32, U32, cursor)
    disposeFixture(f)
    IO.print("PASS preserves order when events arrive after buffered draining starts")

def waitingConsumers() -> IO(Unit):
  do IO<Unit>:
    +f : Fixture <- fixture(False{})
    +stream : E.EventStream<U32, U32> = streamOf(f)
    +first : E.Iterator<U32, U32> <- E.iterator(U32, U32, stream)
    +second : E.Iterator<U32, U32> <- E.iterator(U32, U32, stream)
    firstEvent : D.Deferred<E.Iteration<U32>> <- E.next(U32, U32, first)
    secondEvent : D.Deferred<E.Iteration<U32>> <- E.next(U32, U32, second)
    E.push(U32, U32, stream, 1)
    E.push(U32, U32, stream, 2)
    expectPromise(firstEvent, Some{1})
    expectPromise(secondEvent, Some{2})
    E.end(U32, U32, stream, None{})
    E.disposeIterator(U32, U32, first)
    E.disposeIterator(U32, U32, second)
    disposeFixture(f)
    IO.print("PASS delivers events to waiting consumers in registration order")

def explicitResult() -> IO(Unit):
  do IO<Unit>:
    +check : C.Callback<U32, Bool> <- C.create(~Bool, ~U32, ~Bool, ~predicate, False{})
    +extract : C.Callback<U32, String> <- C.create(~Unit, ~U32, ~String, ~stringify, Unit{})
    +stream : E.EventStream<U32, String> <- E.create(U32, String, check, extract)
    E.push(U32, String, stream, 1)
    E.push(U32, String, stream, 2)
    E.end(U32, String, stream, Some{"complete"})
    value : String <- E.resultValue(U32, String, stream)
    assertion(String.eq(value, "complete"), "explicit result")
    +cursor : E.Iterator<U32, String> <- E.iterator(U32, String, stream)
    expectNext(String, cursor, Some{1})
    expectNext(String, cursor, Some{2})
    expectNext(String, cursor, None{})
    E.disposeIterator(U32, String, cursor)
    E.dispose(U32, String, stream)
    C.dispose(U32, Bool, check)
    C.dispose(U32, String, extract)
    IO.print("PASS drains buffered events after end and resolves the explicit result")

def wakeAll() -> IO(Unit):
  do IO<Unit>:
    +f : Fixture <- fixture(False{})
    +stream : E.EventStream<U32, U32> = streamOf(f)
    +first : E.Iterator<U32, U32> <- E.iterator(U32, U32, stream)
    +second : E.Iterator<U32, U32> <- E.iterator(U32, U32, stream)
    firstEvent : D.Deferred<E.Iteration<U32>> <- E.next(U32, U32, first)
    secondEvent : D.Deferred<E.Iteration<U32>> <- E.next(U32, U32, second)
    E.end(U32, U32, stream, None{})
    expectPromise(firstEvent, None{})
    expectPromise(secondEvent, None{})
    E.disposeIterator(U32, U32, first)
    E.disposeIterator(U32, U32, second)
    disposeFixture(f)
    IO.print("PASS wakes all waiting consumers when ended without a result")

# Native regressions supplement, rather than replace, the five upstream cases.
def queuedNext() -> IO(Unit):
  do IO<Unit>:
    +f : Fixture <- fixture(False{})
    +stream : E.EventStream<U32, U32> = streamOf(f)
    +first : E.Iterator<U32, U32> <- E.iterator(U32, U32, stream)
    +second : E.Iterator<U32, U32> <- E.iterator(U32, U32, stream)
    a : D.Deferred<E.Iteration<U32>> <- E.next(U32, U32, first)
    b : D.Deferred<E.Iteration<U32>> <- E.next(U32, U32, first)
    c : D.Deferred<E.Iteration<U32>> <- E.next(U32, U32, second)
    E.push(U32, U32, stream, 1)
    E.push(U32, U32, stream, 2)
    E.push(U32, U32, stream, 3)
    expectPromise(a, Some{1})
    expectPromise(c, Some{2})
    expectPromise(b, Some{3})
    E.end(U32, U32, stream, None{})
    expectNext(U32, first, None{})
    expectNext(U32, first, None{})
    E.disposeIterator(U32, U32, first)
    E.disposeIterator(U32, U32, second)
    disposeFixture(f)
    IO.print("PASS queued next calls serialize within each iterator")

def pendingState(-A: Data, state: D.State<A>) -> Bool:
  match state:
    case D.Pending{_}: True{}
    case D.Resolved{_}: False{}

def expectPending(-A: Data, promise: D.Deferred<A>) -> IO(Unit):
  match promise:
    case D.Deferred{state}:
      do IO<Unit>:
        observed : D.State<A> <- Ref.read(D.State<A>, state)
        assertion(pendingState(A, observed), "promise must still be pending")

def completionDoesNotEndWaiters() -> IO(Unit):
  do IO<Unit>:
    +f : Fixture <- fixture(True{})
    +stream : E.EventStream<U32, U32> = streamOf(f)
    +first : E.Iterator<U32, U32> <- E.iterator(U32, U32, stream)
    +second : E.Iterator<U32, U32> <- E.iterator(U32, U32, stream)
    a : D.Deferred<E.Iteration<U32>> <- E.next(U32, U32, first)
    +b : D.Deferred<E.Iteration<U32>> <- E.next(U32, U32, second)
    E.push(U32, U32, stream, 3)
    expectPromise(a, Some{3})
    expectPending(E.Iteration<U32>, b)
    E.end(U32, U32, stream, Some{99})
    expectPromise(b, None{})
    value : U32 <- E.resultValue(U32, U32, stream)
    assertion(U32.is_eq(value, 3), "first result settlement wins")
    value : U32 <- E.resultValue(U32, U32, stream)
    assertion(U32.is_eq(value, 3), "result remains repeatable")
    E.disposeIterator(U32, U32, first)
    E.disposeIterator(U32, U32, second)
    disposeFixture(f)
    IO.print("PASS completion delivers one event; explicit end wakes other waiters")

def deferredExplicitResult() -> IO(Unit):
  do IO<Unit>:
    +f : Fixture <- fixture(False{})
    +stream : E.EventStream<U32, U32> = streamOf(f)
    E.end(U32, U32, stream, None{})
    expectPending(U32, E.result(U32, U32, stream))
    E.end(U32, U32, stream, Some{7})
    E.end(U32, U32, stream, Some{8})
    value : U32 <- E.resultValue(U32, U32, stream)
    assertion(U32.is_eq(value, 7), "end without result must leave final result unsettled")
    disposeFixture(f)
    IO.print("PASS end without result permits later explicit result settlement")

def refPredicate(unused: Unit, value: Ref.Ref<U32>) -> IO(Bool): IO.pure(Bool, False{})
def refIdentity(unused: Unit, value: Ref.Ref<U32>) -> IO(Ref.Ref<U32>): IO.pure(Ref.Ref<U32>, value)

def expectRetained(value: E.Iteration<Ref.Ref<U32>>) -> IO(Unit):
  match value:
    case E.End{}: assertion(False{}, "shared event missing")
    case E.Yield{reference}:
      do IO<Unit>:
        observed : U32 <- Ref.read(U32, reference)
        assertion(U32.is_eq(observed, 42), "event must retain live shared identity")

def retainedPayload() -> IO(Unit):
  do IO<Unit>:
    +check : C.Callback<Ref.Ref<U32>, Bool> <- C.create(~Unit, ~Ref.Ref<U32>, ~Bool, ~refPredicate, Unit{})
    +extract : C.Callback<Ref.Ref<U32>, Ref.Ref<U32>> <- C.create(~Unit, ~Ref.Ref<U32>, ~Ref.Ref<U32>, ~refIdentity, Unit{})
    +stream : E.EventStream<Ref.Ref<U32>, Ref.Ref<U32>> <- E.create(Ref.Ref<U32>, Ref.Ref<U32>, check, extract)
    +reference : Ref.Ref<U32> <- Ref.new(U32, 1)
    E.push(Ref.Ref<U32>, Ref.Ref<U32>, stream, reference)
    E.end(Ref.Ref<U32>, Ref.Ref<U32>, stream, Some{reference})
    Ref.write(U32, reference, 42)
    +cursor : E.Iterator<Ref.Ref<U32>, Ref.Ref<U32>> <- E.iterator(Ref.Ref<U32>, Ref.Ref<U32>, stream)
    observed : E.Iteration<Ref.Ref<U32>> <- E.nextValue(Ref.Ref<U32>, Ref.Ref<U32>, cursor)
    expectRetained(observed)
    finalReference : Ref.Ref<U32> <- E.resultValue(Ref.Ref<U32>, Ref.Ref<U32>, stream)
    finalValue : U32 <- Ref.read(U32, finalReference)
    assertion(U32.is_eq(finalValue, 42), "final result must retain shared identity")
    E.disposeIterator(Ref.Ref<U32>, Ref.Ref<U32>, cursor)
    E.dispose(Ref.Ref<U32>, Ref.Ref<U32>, stream)
    C.dispose(Ref.Ref<U32>, Bool, check)
    C.dispose(Ref.Ref<U32>, Ref.Ref<U32>, extract)
    previous : U32 <- Ref.dispose(U32, reference)
    IO.print("PASS event and result payloads retain live shared identity")

def main() -> IO(Unit):
  do IO<Unit>:
    bufferedCompletion()
    interleavedBuffer()
    waitingConsumers()
    explicitResult()
    wakeAll()
    queuedNext()
    completionDoesNotEndWaiters()
    deferredExplicitResult()
    retainedPayload()

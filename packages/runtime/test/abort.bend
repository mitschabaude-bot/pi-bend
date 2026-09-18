import Base
import ../src/abort.bend as A
import ../src/deferred.bend as D
import ../src/ref.bend as R

def assertion(ok: Bool, label: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))

def unthrown(-Reason: Data, value: Result<&2, &2, A.AbortReason<Reason>, Unit>) -> Bool:
  match value:
    case Done{Unit{}}: True{}
    case _: False{}

def zero(value: A.AbortReason<U32>) -> Bool:
  match value:
    case A.Supplied{number}: U32.is_eq(number, 0)
    case _: False{}

def zeroResult(value: Result<&2, &2, A.AbortReason<U32>, Unit>) -> Bool:
  match value:
    case Fail{why}: zero(why)
    case _: False{}

def errorHandle(value: Maybe<&2, A.AbortReason<Unit>>) -> IO(R.Ref<A.AbortError>):
  match value:
    case Some{A.DefaultAbort{error}}: IO.pure(R.Ref<A.AbortError>, error)
    case _: IO.die(R.Ref<A.AbortError>, 1, "missing default AbortError")

def checkDefault(value: A.AbortError) -> Bool:
  match value:
    case A.AbortError{name, message, code}: String.eq(name, "AbortError") && String.eq(message, "This operation was aborted") && U32.is_eq(code, 20)

def changedDefault(value: A.AbortError) -> Bool:
  match value:
    case A.AbortError{_, message, _}: String.eq(message, "retained")

def sharedValue(value: A.AbortReason<R.Ref<String>>) -> IO(String):
  match value:
    case A.Supplied{reference}: R.read(String, reference)
    case _: IO.die(String, 1, "supplied object reason was replaced")

def abortMany(count: Nat, +controller: A.AbortController<U32>) -> IO(List<&2, Chan(Unit)>):
  match count:
    case 0n: IO.pure(List<&2, Chan(Unit)>, Nil{})
    case 1n+ +n:
      do IO<List<&2, Chan(Unit)>>:
        task : Chan(Unit) <- IO.fork(Unit, A.abort(U32, controller, Some{U32.from_nat(n)}))
        tail : List<&2, Chan(Unit)> <- abortMany(n, controller)
        return task <> tail

def joinAll(tasks: List<&2, Chan(Unit)>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> tail:
      do IO<Unit>:
        result : Unit <- IO.join(Unit, head)
        joinAll(tail)

def sameReason(a: Maybe<&2, A.AbortReason<U32>>, b: Maybe<&2, A.AbortReason<U32>>) -> Bool:
  match a b:
    case Some{A.Supplied{x}} Some{A.Supplied{y}}: U32.is_eq(x, y)
    case _ _: False{}

type NullReason is Data:
  NullReason{}

def falseResult(value: Result<&2, &2, A.AbortReason<Bool>, Unit>) -> Bool:
  match value:
    case Fail{A.Supplied{False{}}}: True{}
    case _: False{}

def nullResult(value: Result<&2, &2, A.AbortReason<NullReason>, Unit>) -> Bool:
  match value:
    case Fail{A.Supplied{NullReason{}}}: True{}
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    +controller : A.AbortController<U32> <- A.new(U32)
    +signal : A.AbortSignal<U32> = A.signal(U32, controller)
    before : Bool <- A.aborted(U32, signal)
    assertion(Bool.not(before), "new controller must not be aborted")
    beforeCheck : Result<&2, &2, A.AbortReason<U32>, Unit> <- A.throwIfAborted(U32, signal)
    assertion(unthrown(U32, beforeCheck), "unaborted preflight must succeed")
    first : D.Ticket<A.AbortReason<U32>> <- A.observe(U32, signal)
    second : D.Ticket<A.AbortReason<U32>> <- A.observe(U32, signal)
    A.abort(U32, controller, Some{0})
    A.abort(U32, controller, Some{9})
    A.abort(U32, controller, None{})
    after : Bool <- A.aborted(U32, signal)
    assertion(after, "zero is an abort reason")
    checked : Result<&2, &2, A.AbortReason<U32>, Unit> <- A.throwIfAborted(U32, signal)
    assertion(zeroResult(checked), "preflight must return the first reason")
    a : A.AbortReason<U32> <- D.wait(A.AbortReason<U32>, first)
    b : A.AbortReason<U32> <- D.wait(A.AbortReason<U32>, second)
    late : D.Ticket<A.AbortReason<U32>> <- A.observe(U32, signal)
    c : A.AbortReason<U32> <- D.wait(A.AbortReason<U32>, late)
    assertion(zero(a) && zero(b) && zero(c), "early/late observations must retain the first reason")
    A.dispose(U32, controller)
    +defaults : A.AbortController<Unit> <- A.new(Unit)
    A.abort(Unit, defaults, None{})
    info : Maybe<&2, A.AbortReason<Unit>> <- A.reason(Unit, A.signal(Unit, defaults))
    +error : R.Ref<A.AbortError> <- errorHandle(info)
    details : A.AbortError <- R.read(A.AbortError, error)
    assertion(checkDefault(details), "default error metadata differs from Node")
    R.write(A.AbortError, error, A.AbortError{"AbortError", "retained", 20})
    A.abort(Unit, defaults, None{})
    info : Maybe<&2, A.AbortReason<Unit>> <- A.reason(Unit, A.signal(Unit, defaults))
    retained : R.Ref<A.AbortError> <- errorHandle(info)
    details : A.AbortError <- R.read(A.AbortError, retained)
    assertion(changedDefault(details), "repeated abort replaced the default error identity")
    A.dispose(Unit, defaults)
    +object : R.Ref<String> <- R.new(String, "before")
    +objects : A.AbortController<R.Ref<String>> <- A.new(R.Ref<String>)
    ticket : D.Ticket<A.AbortReason<R.Ref<String>>> <- A.observe(R.Ref<String>, A.signal(R.Ref<String>, objects))
    A.abort(R.Ref<String>, objects, Some{object})
    R.write(String, object, "after")
    value : A.AbortReason<R.Ref<String>> <- D.wait(A.AbortReason<R.Ref<String>>, ticket)
    text : String <- sharedValue(value)
    assertion(String.eq(text, "after"), "supplied reason identity was lost")
    A.dispose(R.Ref<String>, objects)
    text : String <- R.read(String, object)
    assertion(String.eq(text, "after"), "disposing the signal must not dispose the supplied reason")
    previous : String <- R.dispose(String, object)
    +competing : A.AbortController<U32> <- A.new(U32)
    tasks : List<&2, Chan(Unit)> <- abortMany(100n, competing)
    joinAll(tasks)
    +won : Maybe<&2, A.AbortReason<U32>> <- A.reason(U32, A.signal(U32, competing))
    A.abort(U32, competing, Some{1000})
    still : Maybe<&2, A.AbortReason<U32>> <- A.reason(U32, A.signal(U32, competing))
    assertion(sameReason(won, still), "concurrent abort must settle exactly once")
    A.dispose(U32, competing)
    +falseController : A.AbortController<Bool> <- A.new(Bool)
    A.abort(Bool, falseController, Some{False{}})
    falseCheck : Result<&2, &2, A.AbortReason<Bool>, Unit> <- A.throwIfAborted(Bool, A.signal(Bool, falseController))
    assertion(falseResult(falseCheck), "false must remain a supplied reason")
    A.dispose(Bool, falseController)
    +nullController : A.AbortController<NullReason> <- A.new(NullReason)
    A.abort(NullReason, nullController, Some{NullReason{}})
    nullCheck : Result<&2, &2, A.AbortReason<NullReason>, Unit> <- A.throwIfAborted(NullReason, A.signal(NullReason, nullController))
    assertion(nullResult(nullCheck), "explicit null must differ from omitted reason")
    A.dispose(NullReason, nullController)
    unused : A.AbortController<Unit> <- A.new(Unit)
    A.dispose(Unit, unused)
    IO.print("PASS abort state, preflight, reason identity, observation and concurrent first settlement")

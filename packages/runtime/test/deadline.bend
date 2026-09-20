import Base
import ../src/deadline.bend as Deadline
import ../src/abort.bend as Abort
import ../src/deferred.bend as Deferred

def assertTrue(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "deadline contract failed")

def label(value: Abort.AbortReason<Deadline.Cause<String>>) -> String:
  match value:
    case Abort.Supplied{Deadline.Expired{}}: "expiry"
    case Abort.Supplied{Deadline.ParentAbort{Abort.DefaultAbort{}}}: "default"
    case Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{reason}}}: reason
    case _: "unexpected"

def retained(value: Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>>) -> String:
  match value:
    case None{}: "none"
    case Some{why}: label(why)

def waitSignal(signal: Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Abort.AbortReason<Deadline.Cause<String>>):
  match signal:
    case Abort.AbortSignal{settlement}: Deferred.result(Abort.AbortReason<Deadline.Cause<String>>, settlement)

def waitBorrowed(pair: Deadline.Scope<String> & Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Deadline.Scope<String> & String):
  match pair:
    case (scope, signal):
      do IO<Deadline.Scope<String> & String>:
        why : Abort.AbortReason<Deadline.Cause<String>> <- waitSignal(signal)
        return (scope, label(why))

def finish(expected: String, pair: Deadline.Scope<String> & String) -> IO(Unit):
  match pair:
    case (scope, +actual):
      do IO<Unit>:
        assertTrue(String.eq(expected, actual))
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
        assertTrue(String.eq(retained(reason), actual))

def waitAndClose(scope: Deadline.Scope<String>, expected: String) -> IO(Unit):
  do IO<Unit>:
    pair : Deadline.Scope<String> & String <- waitBorrowed(Deadline.borrow(String, scope))
    finish(expected, pair)

def pre(reason: Maybe<&2, String>, expected: String) -> IO(Unit):
  do IO<Unit>:
    +parent : Abort.AbortController<String> <- Abort.new(String)
    won : Bool <- Abort.abort(String, parent, reason)
    scope : Deadline.Scope<String> <- Deadline.create(String, 0, Abort.signal(String, parent))
    waitAndClose(scope, expected)
    Abort.dispose(String, parent)

def early(count: Nat, +parent: Abort.AbortSignal<String>) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        scope : Deadline.Scope<String> <- Deadline.create(String, 60000, parent)
        why : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
        assertTrue(String.eq(retained(why), "none"))
        early(rest, parent)

def scopes(count: Nat, +parent: Abort.AbortSignal<String>, acc: List<&1, Deadline.Scope<String>>) -> IO(List<&1, Deadline.Scope<String>>):
  match count:
    case Zero{}: IO.pure(List<&1, Deadline.Scope<String>>, acc)
    case Succ{rest}:
      do IO<List<&1, Deadline.Scope<String>>>:
        scope : Deadline.Scope<String> <- Deadline.create(String, 60000, parent)
        scopes(rest, parent, scope <> acc)

def closedScopes(values: List<&1, Deadline.Scope<String>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case scope <> rest:
      do IO<Unit>:
        waitAndClose(scope, "stop")
        closedScopes(rest)

def broadcast() -> IO(Unit):
  do IO<Unit>:
    +parent : Abort.AbortController<String> <- Abort.new(String)
    owners : List<&1, Deadline.Scope<String>> <- scopes(64n, Abort.signal(String, parent), Nil{})
    first : Bool <- Abort.abort(String, parent, Some{"stop"})
    second : Bool <- Abort.abort(String, parent, Some{"later"})
    assertTrue(first && Bool.not(second))
    closedScopes(owners)
    Abort.dispose(String, parent)

def later(parent: Abort.AbortController<String>, delay: U32) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(delay)
    won : Bool <- Abort.abort(String, parent, Some{"stop"})
    return Unit{}

def raceClosed(pair: Deadline.Scope<String> & String) -> IO(Unit):
  match pair:
    case (scope, +why):
      do IO<Unit>:
        assertTrue(String.eq(why, "stop") || String.eq(why, "expiry"))
        result : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
        assertTrue(String.eq(retained(result), why))

def race(expiry: U32, delay: U32) -> IO(Unit):
  do IO<Unit>:
    +parent : Abort.AbortController<String> <- Abort.new(String)
    scope : Deadline.Scope<String> <- Deadline.create(String, expiry, Abort.signal(String, parent))
    task : Chan(Unit) <- IO.fork(Unit, later(parent, delay))
    pair : Deadline.Scope<String> & String <- waitBorrowed(Deadline.borrow(String, scope))
    raceClosed(pair)
    IO.join(Unit, task)
    Abort.dispose(String, parent)

def races(count: Nat) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        race(0, 0)
        race(0, 1)
        race(1, 0)
        race(1, 1)
        races(rest)

def closeAllowed(value: Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>>) -> Bool:
  match value:
    case None{}: True{}
    case Some{Abort.Supplied{Deadline.Expired{}}}: True{}
    case _: False{}

def closeRace(parent: Abort.AbortSignal<String>, delay: U32) -> IO(Unit):
  do IO<Unit>:
    scope : Deadline.Scope<String> <- Deadline.create(String, delay, parent)
    why : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
    assertTrue(closeAllowed(why))

def closeRaces(count: Nat, +parent: Abort.AbortSignal<String>) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        closeRace(parent, 0)
        closeRace(parent, 1)
        closeRaces(rest, parent)

def basic() -> IO(Unit):
  do IO<Unit>:
    +parent : Abort.AbortController<String> <- Abort.new(String)
    early(32n, Abort.signal(String, parent))
    closeRaces(16n, Abort.signal(String, parent))
    scope : Deadline.Scope<String> <- Deadline.create(String, 1, Abort.signal(String, parent))
    waitAndClose(scope, "expiry")
    aborted : Bool <- Abort.aborted(String, Abort.signal(String, parent))
    assertTrue(Bool.not(aborted))
    # Disposing the child leaves the parent usable for another scope.
    scope : Deadline.Scope<String> <- Deadline.create(String, 0, Abort.signal(String, parent))
    waitAndClose(scope, "expiry")
    Abort.dispose(String, parent)
    broadcast()
    races(16n)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "pre" <> Nil{}:
      do IO<Unit>:
        pre(None{}, "default")
        pre(Some{"stop"}, "stop")
        IO.print("PASS deadline")
    case _:
      do IO<Unit>:
        basic()
        IO.print("PASS deadline")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

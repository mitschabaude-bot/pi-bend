import Base
import ../src/tool-update-scope.bend as U
import ../../runtime/src/deferred.bend as D
import ./message-events.bend as Test

def required(value: Maybe<&1, U.Ticket<String>>) -> IO(U.Ticket<String>):
  match value:
    case Some{ticket}: IO.pure(U.Ticket<String>, ticket)
    case None{}: IO.die(U.Ticket<String>, 1, "open scope rejected update")

def reserve(scope: U.Scope<String>) -> IO(U.Ticket<String>):
  do IO<U.Ticket<String>>:
    value : Maybe<&1, U.Ticket<String>> <- U.begin(String, scope)
    required(value)

def rejected(value: Maybe<&1, U.Ticket<String>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{_}: Test.assertion(False{}, "closed tool accepted late update")

def check(result: U.Outcome(String), expected: String) -> IO(Unit):
  match result:
    case Done{_}: Test.assertion(String.is_empty(expected), "listener failure disappeared")
    case Fail{error}: Test.assertion(String.eq(error, expected), "wrong listener failure precedence")

def pending(scope: U.Scope<String>) -> IO(Unit):
  match scope:
    case U.Scope{_, result, _}:
      do IO<Unit>:
        observed : Maybe<&2, U.Outcome(String)> <- D.peek(U.Outcome(String), result)
        Test.assertion(Maybe.is_none(&2, U.Outcome(String), observed), "scope settled before accepted updates")

def notDrained(scope: U.Scope<String>) -> IO(Unit):
  match scope:
    case U.Scope{_, _, drained}:
      do IO<Unit>:
        observed : Maybe<&2, Unit> <- D.peek(Unit, drained)
        Test.assertion(Maybe.is_none(&2, Unit, observed), "scope drained with an outstanding update")

def empty() -> IO(Unit):
  do IO<Unit>:
    +scope : U.Scope<String> <- U.new(String)
    U.close(String, scope)
    U.close(String, scope)
    value : U.Outcome(String) <- U.result(String, scope)
    check(value, "")
    late : Maybe<&1, U.Ticket<String>> <- U.begin(String, scope)
    rejected(late)
    U.dispose(String, scope)

def successful() -> IO(Unit):
  do IO<Unit>:
    +scope : U.Scope<String> <- U.new(String)
    first : U.Ticket<String> <- reserve(scope)
    second : U.Ticket<String> <- reserve(scope)
    U.close(String, scope)
    pending(scope)
    U.complete(String, second, Done{Unit{}})
    pending(scope)
    U.complete(String, first, Done{Unit{}})
    value : U.Outcome(String) <- U.result(String, scope)
    check(value, "")
    U.dispose(String, scope)

def failedAfterClose() -> IO(Unit):
  do IO<Unit>:
    +scope : U.Scope<String> <- U.new(String)
    first : U.Ticket<String> <- reserve(scope)
    second : U.Ticket<String> <- reserve(scope)
    U.close(String, scope)
    U.complete(String, second, Fail{"second"})
    value : U.Outcome(String) <- U.result(String, scope)
    check(value, "second")
    notDrained(scope)
    U.complete(String, first, Fail{"first"})
    unchanged : U.Outcome(String) <- U.result(String, scope)
    check(unchanged, "second")
    U.dispose(String, scope)

def failedBeforeClose() -> IO(Unit):
  do IO<Unit>:
    +scope : U.Scope<String> <- U.new(String)
    first : U.Ticket<String> <- reserve(scope)
    second : U.Ticket<String> <- reserve(scope)
    U.complete(String, second, Fail{"second"})
    U.complete(String, first, Fail{"first"})
    pending(scope)
    U.close(String, scope)
    value : U.Outcome(String) <- U.result(String, scope)
    check(value, "first")
    U.dispose(String, scope)

def failedWithPending() -> IO(Unit):
  do IO<Unit>:
    +scope : U.Scope<String> <- U.new(String)
    first : U.Ticket<String> <- reserve(scope)
    second : U.Ticket<String> <- reserve(scope)
    U.complete(String, second, Fail{"second"})
    U.close(String, scope)
    value : U.Outcome(String) <- U.result(String, scope)
    check(value, "second")
    notDrained(scope)
    U.complete(String, first, Done{Unit{}})
    U.dispose(String, scope)

def independentScopes() -> IO(Unit):
  do IO<Unit>:
    +fast : U.Scope<String> <- U.new(String)
    +slow : U.Scope<String> <- U.new(String)
    U.close(String, fast)
    late : Maybe<&1, U.Ticket<String>> <- U.begin(String, fast)
    rejected(late)
    accepted : U.Ticket<String> <- reserve(slow)
    U.close(String, slow)
    pending(slow)
    U.complete(String, accepted, Done{Unit{}})
    U.dispose(String, fast)
    U.dispose(String, slow)

def tickets(count: Nat, +scope: U.Scope<String>) -> IO(List<&1, U.Ticket<String>>):
  match count:
    case 0n: IO.pure(List<&1, U.Ticket<String>>, Nil{})
    case 1n+n:
      do IO<List<&1, U.Ticket<String>>>:
        first : U.Ticket<String> <- reserve(scope)
        rest : List<&1, U.Ticket<String>> <- tickets(n, scope)
        return first <> rest

def launch(updates: List<&1, U.Ticket<String>>, +fail: Bool) -> IO(Unit):
  match updates:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.spawn(Unit, U.complete(String, first, Bool.pick(U.Outcome(String), fail, Fail{"concurrent"}, Done{Unit{}})))
        launch(rest, fail)

def concurrent(+fail: Bool) -> IO(Unit):
  do IO<Unit>:
    +scope : U.Scope<String> <- U.new(String)
    updates : List<&1, U.Ticket<String>> <- tickets(128n, scope)
    U.close(String, scope)
    launch(updates, fail)
    value : U.Outcome(String) <- U.result(String, scope)
    check(value, Bool.pick(String, fail, "concurrent", ""))
    U.dispose(String, scope)

def main() -> IO(Unit):
  do IO<Unit>:
    empty()
    successful()
    failedAfterClose()
    failedBeforeClose()
    failedWithPending()
    independentScopes()
    concurrent(False{})
    concurrent(True{})
    IO.print("PASS update admission, late-update rejection, failure precedence, independent invocations and 256 concurrent completions")

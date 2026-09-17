import Base
import ../src/deferred.bend as D
import ../src/ref.bend as R

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def main() -> IO(Unit):
  do IO<Unit>:
    +deferred : D.Deferred<String> <- D.new(String)
    first : D.Ticket<String> <- D.subscribe(String, deferred)
    second : D.Ticket<String> <- D.subscribe(String, deferred)
    earlyConsumer : Chan(String) <- IO.fork(String, D.wait(String, first))
    won : Bool <- D.resolve(String, deferred, "first result")
    assertion(won, "initial settlement must win")
    won : Bool <- D.resolve(String, deferred, "replacement")
    assertion(Bool.not(won), "repeated settlement must be ignored")
    a : String <- IO.join(String, earlyConsumer)
    b : String <- D.wait(String, second)
    c : String <- D.result(String, deferred)
    d : String <- D.result(String, deferred)
    assertion(String.eq(a, "first result") && String.eq(b, "first result") && String.eq(c, "first result") && String.eq(d, "first result"), "all observers must receive the original result")
    +cell : R.Ref<String> <- R.new(String, "before")
    +shared : D.Deferred<R.Ref<String>> <- D.new(R.Ref<String>)
    won : Bool <- D.resolve(R.Ref<String>, shared, cell)
    R.write(String, cell, "after")
    observed : R.Ref<String> <- D.result(R.Ref<String>, shared)
    value : String <- R.read(String, observed)
    assertion(String.eq(value, "after"), "settled objects must retain shared identity")
    D.dispose(String, deferred)
    D.dispose(R.Ref<String>, shared)
    previous : String <- R.dispose(String, cell)
    IO.print("deferred: waiting/late/repeated observers, first settlement and shared identity passed")

import Base
import ../src/listener-registry.bend as L
import ../src/callback.bend as C
import ../src/ref.bend as R
import ../src/utf16.bend as U

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def echo(unused: Unit, value: Unit) -> IO(Unit): IO.pure(Unit, value)

def emptyState(state: L.State<Unit, Unit>) -> Bool:
  match state:
    case L.State{_, 0n, Nil{}, Nil{}}: True{}
    case _: False{}

def checkEmpty(registry: L.Registry<Unit, Unit>) -> IO(Unit):
  match registry:
    case L.Registry{state}:
      do IO<Unit>:
        current : L.State<Unit, Unit> <- R.read(L.State<Unit, Unit>, state)
        assertion(emptyState(current), "registry must release live/retired nodes and closed walks")

def mutate(adding: Bool, registry: L.Registry<Unit, Unit>, callback: C.Callback<Unit, Unit>) -> IO(Bool):
  match adding:
    case True{}: L.add(Unit, Unit, registry, "abort", callback, L.Options{False{}, True{}, False{}})
    case False{}: L.remove(Unit, Unit, registry, "abort", callback, False{})

def mutations(count: Nat, +adding: Bool, +registry: L.Registry<Unit, Unit>, +callback: C.Callback<Unit, Unit>) -> IO(List<&2, Chan(Bool)>):
  match count:
    case 0n: IO.pure(List<&2, Chan(Bool)>, Nil{})
    case 1n+ n:
      do IO<List<&2, Chan(Bool)>>:
        task : Chan(Bool) <- IO.fork(Bool, mutate(adding, registry, callback))
        rest : List<&2, Chan(Bool)> <- mutations(n, adding, registry, callback)
        return task <> rest

def winners(tasks: List<&2, Chan(Bool)>) -> IO(U32):
  match tasks:
    case Nil{}: IO.pure(U32, 0)
    case task <> rest:
      do IO<U32>:
        won : Bool <- IO.join(Bool, task)
        others : U32 <- winners(rest)
        return (others + Bool.pick(U32, won, 1, 0) : U32)

def openWalks(count: Nat, +registry: L.Registry<Unit, Unit>) -> IO(List<&1, L.Cursor<Unit, Unit>>):
  match count:
    case 0n: IO.pure(List<&1, L.Cursor<Unit, Unit>>, Nil{})
    case 1n+ n:
      do IO<List<&1, L.Cursor<Unit, Unit>>>:
        cursor : L.Cursor<Unit, Unit> <- L.begin(Unit, Unit, registry, "abort")
        rest : List<&1, L.Cursor<Unit, Unit>> <- openWalks(n, registry)
        return cursor <> rest

def claimed(step: L.Step<Unit, Unit>) -> IO(Bool):
  match step:
    case L.End{}: IO.pure(Bool, False{})
    case L.More{cursor, listener}:
      do IO<Bool>:
        L.close(Unit, Unit, cursor)
        return Maybe.is_some(&2, L.Registration<Unit, Unit>, listener)

def claim(cursor: L.Cursor<Unit, Unit>) -> IO(Bool):
  do IO<Bool>:
    step : L.Step<Unit, Unit> <- L.next(Unit, Unit, cursor)
    claimed(step)

def claimAll(cursors: List<&1, L.Cursor<Unit, Unit>>) -> IO(List<&2, Chan(Bool)>):
  match cursors:
    case Nil{}: IO.pure(List<&2, Chan(Bool)>, Nil{})
    case cursor <> rest:
      do IO<List<&2, Chan(Bool)>>:
        task : Chan(Bool) <- IO.fork(Bool, claim(cursor))
        tail : List<&2, Chan(Bool)> <- claimAll(rest)
        return task <> tail

def retained(state: L.State<Unit, Unit>) -> Bool:
  match state:
    case L.State{_, 1n+ _, Nil{}, _ <> _}: True{}
    case _: False{}

def checkRetained(registry: L.Registry<Unit, Unit>) -> IO(Unit):
  match registry:
    case L.Registry{state}:
      do IO<Unit>:
        current : L.State<Unit, Unit> <- R.read(L.State<Unit, Unit>, state)
        assertion(retained(current), "active walk must retain the removed node it can still reach")

def checkFlags(step: L.Step<Unit, Unit>) -> IO(Unit):
  match step:
    case L.More{cursor, Some{L.Registration{_, _, _, L.Options{False{}, False{}, True{}}}}}: L.close(Unit, Unit, cursor)
    case L.More{cursor, _}:
      do IO<Unit>:
        L.close(Unit, Unit, cursor)
        assertion(False{}, "duplicate registration replaced the original options")
    case L.End{}: assertion(False{}, "expected original listener")

def expectEnd(step: L.Step<Unit, Unit>) -> IO(Unit):
  match step:
    case L.End{}: IO.pure(Unit, Unit{})
    case L.More{cursor, _}:
      do IO<Unit>:
        L.close(Unit, Unit, cursor)
        assertion(False{}, "stopping traversal must close it before claiming a listener")

def expectSkipped(step: L.Step<Unit, Unit>) -> IO(Unit):
  match step:
    case L.More{cursor, None{}}:
      do IO<Unit>:
        end : L.Step<Unit, Unit> <- L.next(Unit, Unit, cursor)
        expectEnd(end)
    case L.More{cursor, Some{_}}:
      do IO<Unit>:
        L.close(Unit, Unit, cursor)
        assertion(False{}, "skipped listener must not be claimed")
    case L.End{}: assertion(False{}, "skipping must advance rather than stop")

def stopPassive(registration: L.Registration<Unit, Unit>) -> L.DispatchDecision:
  match registration:
    case L.Registration{_, _, _, L.Options{_, _, True{}}}: L.StopDispatch{}
    case _: L.CallListener{}

def main() -> IO(Unit):
  do IO<Unit>:
    +registry : L.Registry<Unit, Unit> <- L.new(Unit, Unit)
    +callback : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~echo, Unit{})
    additions : List<&2, Chan(Bool)> <- mutations(64n, True{}, registry, callback)
    count : U32 <- winners(additions)
    assertion(U32.is_eq(count, 1), "duplicate concurrent registrations must have one insertion winner")
    cursors : List<&1, L.Cursor<Unit, Unit>> <- openWalks(64n, registry)
    claims : List<&2, Chan(Bool)> <- claimAll(cursors)
    count : U32 <- winners(claims)
    assertion(U32.is_eq(count, 1), "concurrent once traversal must invoke exactly once")
    checkEmpty(registry)
    added : Bool <- L.add(Unit, Unit, registry, "abort", callback, L.Options{False{}, False{}, False{}})
    assertion(added, "removed once callback must be addable again")
    cursor : L.Cursor<Unit, Unit> <- L.begin(Unit, Unit, registry, "abort")
    removals : List<&2, Chan(Bool)> <- mutations(64n, False{}, registry, callback)
    count : U32 <- winners(removals)
    assertion(U32.is_eq(count, 1), "concurrent removals must have one removal winner")
    checkRetained(registry)
    L.close(Unit, Unit, cursor)
    checkEmpty(registry)
    added : Bool <- L.add(Unit, Unit, registry, "🐱", callback, L.Options{False{}, False{}, True{}})
    duplicate : Bool <- L.add(Unit, Unit, registry, U.unit(55357) ++ U.unit(56369), callback, L.Options{False{}, True{}, False{}})
    assertion(added && Bool.not(duplicate), "equivalent UTF-16 event names must identify one listener")
    cursor : L.Cursor<Unit, Unit> <- L.begin(Unit, Unit, registry, "🐱")
    step : L.Step<Unit, Unit> <- L.next(Unit, Unit, cursor)
    checkFlags(step)
    removed : Bool <- L.remove(Unit, Unit, registry, U.unit(55357) ++ U.unit(56369), callback, False{})
    assertion(removed, "removal must normalize UTF-16 event names too")
    checkEmpty(registry)
    added : Bool <- L.add(Unit, Unit, registry, "abort", callback, L.Options{False{}, True{}, False{}})
    assertion(added, "once control fixture")
    cursor : L.Cursor<Unit, Unit> <- L.begin(Unit, Unit, registry, "abort")
    step : L.Step<Unit, Unit> <- L.nextWith(Unit, Unit, cursor, listener => L.StopDispatch{})
    expectEnd(step)
    cursor : L.Cursor<Unit, Unit> <- L.begin(Unit, Unit, registry, "abort")
    step : L.Step<Unit, Unit> <- L.nextWith(Unit, Unit, cursor, listener => L.SkipListener{})
    expectSkipped(step)
    cursor : L.Cursor<Unit, Unit> <- L.begin(Unit, Unit, registry, "abort")
    invoked : Bool <- claim(cursor)
    assertion(invoked, "stop and skip must preserve once for a later invocation")
    checkEmpty(registry)
    added : Bool <- L.add(Unit, Unit, registry, "abort", callback, L.Options{False{}, False{}, True{}})
    cursor : L.Cursor<Unit, Unit> <- L.begin(Unit, Unit, registry, "abort")
    removed : Bool <- L.remove(Unit, Unit, registry, "abort", callback, False{})
    assertion(added && removed, "removed metadata fixture")
    step : L.Step<Unit, Unit> <- L.nextWith(Unit, Unit, cursor, listener => stopPassive(listener))
    expectEnd(step)
    checkEmpty(registry)
    L.dispose(Unit, Unit, registry)
    C.call(Unit, Unit, callback, Unit{})
    C.dispose(Unit, Unit, callback)
    IO.print("PASS listener registry identity, options, UTF-16, concurrent once/removal and cursor cleanup")

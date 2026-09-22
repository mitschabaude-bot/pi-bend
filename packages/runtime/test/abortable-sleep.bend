import Base
import ../src/abort.bend as A
import ../src/socket.bend as S

def expectDone(value: Result<&2, &2, A.AbortReason<String>, Unit>) -> IO(Unit):
  match value:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "unexpected sleep cancellation")

def expectReason(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "wrong sleep cancellation reason")

def expectCancelled(value: Result<&2, &2, A.AbortReason<String>, Unit>) -> IO(Unit):
  match value:
    case Fail{A.Supplied{why}}: expectReason(String.eq(why, "stop"))
    case _: IO.die(Unit, 1, "expected sleep cancellation")

def complete(count: Nat, +signal: A.AbortSignal<String>) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        result : Result<&2, &2, A.AbortReason<String>, Unit> <- S.sleep(String, 1, signal)
        expectDone(result)
        complete(rest, signal)

def launch(count: Nat, +signal: A.AbortSignal<String>) -> IO(List<&2, Chan(Result<&2, &2, A.AbortReason<String>, Unit>)>):
  match count:
    case Zero{}: IO.pure(List<&2, Chan(Result<&2, &2, A.AbortReason<String>, Unit>)>, Nil{})
    case Succ{rest}:
      do IO<List<&2, Chan(Result<&2, &2, A.AbortReason<String>, Unit>)>>:
        task : Chan(Result<&2, &2, A.AbortReason<String>, Unit>) <- IO.fork(Result<&2, &2, A.AbortReason<String>, Unit>, S.sleep(String, 60000, signal))
        tasks : List<&2, Chan(Result<&2, &2, A.AbortReason<String>, Unit>)> <- launch(rest, signal)
        return task <> tasks

def joinAll(tasks: List<&2, Chan(Result<&2, &2, A.AbortReason<String>, Unit>)>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit, Unit{})
    case task <> rest:
      do IO<Unit>:
        result : Result<&2, &2, A.AbortReason<String>, Unit> <- IO.join(Result<&2, &2, A.AbortReason<String>, Unit>, task)
        expectCancelled(result)
        joinAll(rest)

def broadcast(rounds: Nat) -> IO(Unit):
  match rounds:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        tasks : List<&2, Chan(Result<&2, &2, A.AbortReason<String>, Unit>)> <- launch(128n, A.signal(String, controller))
        IO.sleep(5)
        won : Bool <- A.abort(String, controller, Some{"stop"})
        expectReason(won)
        repeated : Bool <- A.abort(String, controller, Some{"replacement"})
        expectReason(Bool.not(repeated))
        joinAll(tasks)
        pre : Result<&2, &2, A.AbortReason<String>, Unit> <- S.sleep(String, 0, A.signal(String, controller))
        expectCancelled(pre)
        A.dispose(String, controller)
        broadcast(rest)

def independent() -> IO(Unit):
  do IO<Unit>:
    +first : A.AbortController<String> <- A.new(String)
    +second : A.AbortController<String> <- A.new(String)
    long : Chan(Result<&2, &2, A.AbortReason<String>, Unit>) <- IO.fork(Result<&2, &2, A.AbortReason<String>, Unit>, S.sleep(String, 60000, A.signal(String, first)))
    short : Result<&2, &2, A.AbortReason<String>, Unit> <- S.sleep(String, 1, A.signal(String, second))
    expectDone(short)
    won : Bool <- A.abort(String, first, Some{"stop"})
    result : Result<&2, &2, A.AbortReason<String>, Unit> <- IO.join(Result<&2, &2, A.AbortReason<String>, Unit>, long)
    expectCancelled(result)
    unaffected : Result<&2, &2, A.AbortReason<String>, Unit> <- S.sleep(String, 1, A.signal(String, second))
    expectDone(unaffected)
    A.dispose(String, first)
    A.dispose(String, second)

def abortAfter(delay: U32, controller: A.AbortController<String>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(delay)
    won : Bool <- A.abort(String, controller, Some{"stop"})
    return Unit{}

def expectSettled(result: Result<&2, &2, A.AbortReason<String>, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{reason}: expectCancelled(Fail{reason})

def races(count: Nat, +index: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        aborter : Chan(Unit) <- IO.fork(Unit, abortAfter(((index / 3) % 3 : U32), controller))
        result : Result<&2, &2, A.AbortReason<String>, Unit> <- S.sleep(String, (index % 3 : U32), A.signal(String, controller))
        expectSettled(result)
        joined : Unit <- IO.join(Unit, aborter)
        pre : Result<&2, &2, A.AbortReason<String>, Unit> <- S.sleep(String, 0, A.signal(String, controller))
        expectCancelled(pre)
        A.dispose(String, controller)
        races(rest, (index + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    +controller : A.AbortController<String> <- A.new(String)
    complete(32n, A.signal(String, controller))
    zero : Result<&2, &2, A.AbortReason<String>, Unit> <- S.sleep(String, 0, A.signal(String, controller))
    expectDone(zero)
    task : Chan(Result<&2, &2, A.AbortReason<String>, Unit>) <- IO.fork(Result<&2, &2, A.AbortReason<String>, Unit>, S.sleep(String, 60000, A.signal(String, controller)))
    IO.sleep(5)
    won : Bool <- A.abort(String, controller, Some{"stop"})
    cancelled : Result<&2, &2, A.AbortReason<String>, Unit> <- IO.join(Result<&2, &2, A.AbortReason<String>, Unit>, task)
    expectCancelled(cancelled)
    pre : Result<&2, &2, A.AbortReason<String>, Unit> <- S.sleep(String, 60000, A.signal(String, controller))
    expectCancelled(pre)
    A.dispose(String, controller)
    broadcast(8n)
    independent()
    races(90n, 0)
    IO.print("PASS abortable sleep")

import Base
import ../../../../../runtime/src/abort.bend as Abort
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/timer.bend as Timer

# Callbacks are borrowed; disposal cancels and joins the worker before returning.
type Owner is Type:
  Complete{}
  CountdownTimer{cancel: Abort.AbortController<Unit>,worker: Chan(Unit)}

def seconds(milliseconds: Nat) -> Nat: (milliseconds + 999n) / 1000n
def requestRender(redraw: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Unit):
  match redraw:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.call(Unit,Unit,callback,Unit{})
@unsafe def run(remaining: Nat,+signal: Abort.AbortSignal<Unit>,+tick: Callback.Callback<Nat,Unit>,+expire: Callback.Callback<Unit,Unit>,+redraw: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Unit):
  do IO<Unit>:
    waited : Result<&2,&2,Abort.AbortReason<Unit>,Unit> <- Timer.sleep(Unit,1000,signal)
    Bool.pick(Unit -> IO(Unit),Result.is_done(&2,&2,Abort.AbortReason<Unit>,Unit,waited),
      _ => do IO<Unit>:
        +next : Nat <- IO.pure(Nat,remaining - 1n)
        Callback.call(Nat,Unit,tick,next)
        requestRender(redraw)
        Bool.pick(Unit -> IO(Unit),Nat.is_eq(next,0n),
          _ => Callback.call(Unit,Unit,expire,Unit{}),
          _ => run(next,signal,tick,expire,redraw))(Unit{}),
      _ => IO.pure(Unit,Unit{}))(Unit{})
def create(milliseconds: Nat,+redraw: Maybe<&2,Callback.Callback<Unit,Unit>>,+tick: Callback.Callback<Nat,Unit>,+expire: Callback.Callback<Unit,Unit>) -> IO(Owner):
  do IO<Owner>:
    +remaining : Nat <- IO.pure(Nat,seconds(milliseconds))
    Callback.call(Nat,Unit,tick,remaining)
    Bool.pick(Unit -> IO(Owner),Nat.is_eq(remaining,0n),
      _ => do IO<Owner>:
        Callback.call(Unit,Unit,expire,Unit{})
        return Complete{},
      _ => do IO<Owner>:
        +cancel : Abort.AbortController<Unit> <- Abort.new(Unit)
        worker : Chan(Unit) <- IO.fork(Unit,run(remaining,Abort.signal(Unit,cancel),tick,expire,redraw))
        return CountdownTimer{cancel,worker})(Unit{})
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Complete{}: IO.pure(Unit,Unit{})
    case CountdownTimer{+cancel,worker}:
      do IO<Unit>:
        cancelled : Bool <- Abort.abort(Unit,cancel,None{})
        joined : Unit <- IO.join(Unit,worker)
        Abort.dispose(Unit,cancel)

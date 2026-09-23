import Base
import ../packages/tui/src/components/loader.bend as L
import ../packages/tui/src/components/cancellable-loader.bend as Cancel
import ../packages/tui/src/keybindings.bend as KB
import ../packages/tui/src/keys.bend as Keys
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/timer.bend as Timer
import ../packages/runtime/src/abort.bend as Abort
import ../packages/tui/src/components/text.bend as T

def color(prefix: String,input: String) -> IO(String): IO.pure(String,prefix ++ input)
def increment(counter: Ref.Ref<Nat>,_ : Unit) -> IO(Unit):
  do IO<Unit>:
    next : Nat <- Ref.modify(Nat,Nat,counter,+old => (Succ{old},Succ{old}))
    return Unit{}
def display(state: L.Loader) -> String:
  match state:
    case L.Loader{T.Text{value,_,_,_,_},_,_,_,_,_,_,_}: value
def printDisplay(state: L.Loader) -> IO(Unit): IO.print(display(state))
def snapshots(initial: L.Loader) -> IO(Unit):
  do IO<Unit>:
    +first : L.Loader <- L.refresh(initial)
    printDisplay(first)
    +second : L.Loader <- L.next(first)
    printDisplay(second)
    +third : L.Loader <- L.setMessage(second,"Work")
    printDisplay(third)
    +fourth : L.Loader <- L.refresh(L.configure(third,Some{L.Indicator{"*" <> "-" <> Nil{},7}}))
    printDisplay(fourth)
    +fifth : L.Loader <- L.next(fourth)
    printDisplay(fifth)
    +sixth : L.Loader <- L.refresh(L.configure(fifth,Some{L.Indicator{Nil{},80}}))
    printDisplay(sixth)
    +seventh : L.Loader <- L.refresh(L.configure(sixth,None{}))
    printDisplay(seventh)
    eighth : L.Loader <- L.invalidate(seventh)
    printDisplay(eighth)

def cancellationBorrowed(pair: Cancel.CancellableLoader & Cancel.CancellationHandle,counter: Ref.Ref<Nat>) -> IO(Unit):
  match pair:
    case (state,+handle):
      do IO<Unit>:
        +manager : KB.KeybindingsManager <- IO.pure(KB.KeybindingsManager,KB.create(KB.TUI_KEYBINDINGS(),R.new(List<&2,Keys.KeyId>)))
        Cancel.handleInput(handle,manager,Keys.defaults(),"x")
        before : Bool <- Cancel.aborted(handle)
        Cancel.handleInput(handle,manager,Keys.defaults(),"\u{1b}")
        after : Bool <- Abort.aborted(Unit,Cancel.signal(handle))
        Cancel.handleInput(handle,manager,Keys.defaults(),"\u{1b}")
        calls : Nat <- Ref.read(Nat,counter)
        IO.print(Bool.show(before) ++ "/" ++ Bool.show(after) ++ "/" ++ Nat.show(calls))
        Cancel.dispose(state)
def cancellation(state: Cancel.CancellableLoader,counter: Ref.Ref<Nat>) -> IO(Unit):
  cancellationBorrowed(Cancel.borrowCancellation(state),counter)

def closeTimer(pair: Timer & Bool) -> IO(Unit):
  match pair: case (timer,_): Timer.close(timer)
def waitTimer(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case (timer,cancel):
      do IO<Unit>:
        result : Timer & Bool <- Timer.wait(timer)
        closeTimer(result)
def pause(milliseconds: U32) -> IO(Unit):
  do IO<Unit>:
    pair : Timer & TimerCancel <- Timer.new(milliseconds)
    waitTimer(pair)
def checkedSpinner(owner: L.Owner,+counter: Ref.Ref<Nat>) -> IO(Unit):
  do IO<Unit>:
    start : Nat <- Ref.read(Nat,counter)
    pause(100)
    +spun : Nat <- Ref.read(Nat,counter)
    stopped : L.Owner <- L.stop(owner)
    pause(30)
    final : Nat <- Ref.read(Nat,counter)
    Bool.pick(Unit -> IO(Unit),Nat.is_gt(spun,start) && Nat.is_eq(spun,final),
      _ => IO.pure(Unit,Unit{}),
      _ => IO.die(Unit,1,"loader timer failed to tick or continued after stop"))(Unit{})
    restarted : L.Owner <- L.setIndicator(stopped,Some{L.Indicator{"A" <> "B" <> Nil{},8}})
    resumed : Nat <- Ref.read(Nat,counter)
    pause(80)
    advanced : Nat <- Ref.read(Nat,counter)
    static : L.Owner <- L.setIndicator(restarted,Some{L.Indicator{Nil{},8}})
    quiet : Nat <- Ref.read(Nat,counter)
    pause(30)
    still : Nat <- Ref.read(Nat,counter)
    Bool.pick(Unit -> IO(Unit),Nat.is_gt(advanced,resumed) && Nat.is_eq(quiet,still),
      _ => IO.pure(Unit,Unit{}),
      _ => IO.die(Unit,1,"loader indicator restart or static stop failed"))(Unit{})
    L.dispose(static)

def main() -> IO(Unit):
  do IO<Unit>:
    +counter : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +spinner : C.Callback<String,String> <- C.create(~String,~String,~String,~color,"s")
    +message : C.Callback<String,String> <- C.create(~String,~String,~String,~color,"m")
    +redraw : C.Callback<Unit,Unit> <- C.create(~Ref.Ref<Nat>,~Unit,~Unit,~increment,counter)
    snapshots(L.initial("Loading...",None{},spinner,message,redraw))
    owner : Cancel.CancellableLoader <- Cancel.create("Working",Some{L.Indicator{Nil{},80}},spinner,message,redraw,Some{redraw})
    cancellation(owner,counter)
    animated : L.Owner <- L.create("Spinner",Some{L.Indicator{"x" <> "y" <> Nil{},8}},spinner,message,redraw)
    restarted : L.Owner <- L.start(animated)
    checkedSpinner(restarted,counter)
    C.dispose(String,String,spinner)
    C.dispose(String,String,message)
    C.dispose(Unit,Unit,redraw)
    last : Nat <- Ref.dispose(Nat,counter)
    return Unit{}

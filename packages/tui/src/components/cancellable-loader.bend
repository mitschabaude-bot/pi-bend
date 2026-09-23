import Base
import ./loader.bend as Loader
import ../keybindings.bend as Keybindings
import ../keys.bend as Keys
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as Callback

# The caller owns the signal's observers and retires them before dispose.
type CancellableLoader is Type:
  CancellableLoader{loader: Loader.Owner,controller: Abort.AbortController<Unit>,onAbort: Maybe<&2,Callback.Callback<Unit,Unit>>}
type CancellationHandle is Data:
  CancellationHandle{controller: Abort.AbortController<Unit>,onAbort: Maybe<&2,Callback.Callback<Unit,Unit>>}

def create(message: String,indicator: Maybe<&2,Loader.Indicator>,spinner: Callback.Callback<String,String>,color: Callback.Callback<String,String>,redraw: Callback.Callback<Unit,Unit>,onAbort: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(CancellableLoader):
  do IO<CancellableLoader>:
    controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    loader : Loader.Owner <- Loader.create(message,indicator,spinner,color,redraw)
    return CancellableLoader{loader,controller,onAbort}
def signal(handle: CancellationHandle) -> Abort.AbortSignal<Unit>:
  match handle: case CancellationHandle{controller,_}: Abort.signal(Unit,controller)
def aborted(handle: CancellationHandle) -> IO(Bool):
  Abort.aborted(Unit,signal(handle))
def borrowCancellation(state: CancellableLoader) -> CancellableLoader & CancellationHandle:
  match state:
    case CancellableLoader{loader,+controller,+onAbort}: (CancellableLoader{loader,controller,onAbort},CancellationHandle{controller,onAbort})
def borrowed(pair: Loader.Owner & Loader.Handle,controller: Abort.AbortController<Unit>,onAbort: Maybe<&2,Callback.Callback<Unit,Unit>>) -> CancellableLoader & Loader.Handle:
  match pair:
    case (loader,handle): (CancellableLoader{loader,controller,onAbort},handle)
def borrow(state: CancellableLoader) -> CancellableLoader & Loader.Handle:
  match state:
    case CancellableLoader{loader,controller,onAbort}: borrowed(Loader.borrow(loader),controller,onAbort)
def setOnAbort(state: CancellableLoader,callback: Maybe<&2,Callback.Callback<Unit,Unit>>) -> CancellableLoader:
  match state: case CancellableLoader{loader,controller,_}: CancellableLoader{loader,controller,callback}
def abortedCallback(onAbort: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Unit):
  match onAbort:
    case None{}: IO.pure(Unit,Unit{})
    case Some{callback}: Callback.call(Unit,Unit,callback,Unit{})
def handleInput(handle: CancellationHandle,keybindings: Keybindings.KeybindingsManager,context: Keys.Context,data: String) -> IO(Unit):
  match handle:
    case CancellationHandle{controller,onAbort}:
      Bool.pick(Unit -> IO(Unit),Keybindings.matches(keybindings,context,data,"tui.select.cancel"),
        _ => do IO<Unit>:
          won : Bool <- Abort.abort(Unit,controller,None{})
          abortedCallback(onAbort),
        _ => IO.pure(Unit,Unit{}))(Unit{})
def stop(state: CancellableLoader) -> IO(CancellableLoader):
  match state:
    case CancellableLoader{loader,controller,onAbort}:
      do IO<CancellableLoader>:
        stopped : Loader.Owner <- Loader.stop(loader)
        return CancellableLoader{stopped,controller,onAbort}
def dispose(state: CancellableLoader) -> IO(Unit):
  match state:
    case CancellableLoader{loader,controller,_}:
      do IO<Unit>:
        Loader.dispose(loader)
        Abort.dispose(Unit,controller)

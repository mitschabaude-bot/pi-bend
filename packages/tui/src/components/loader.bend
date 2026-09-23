import Base
import ./text.bend as Text
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/serial-resource.bend as Serial
import ../../../runtime/src/timer.bend as Timer

# Color and redraw callbacks are borrowed from the TUI owner.
type Indicator is Data:
  Indicator{frames: List<&2,String>,intervalMs: U32}
type Loader is Data:
  Loader{text: Text.Text,message: String,indicator: Indicator,frame: Nat,verbatim: Bool,spinnerColorFn: Callback.Callback<String,String>,messageColorFn: Callback.Callback<String,String>,requestRender: Callback.Callback<Unit,Unit>}
type Handle is Data: Handle{resource: Serial.Handle<Loader>}
type Animation is Data:
  Animation{cancel: Abort.AbortController<Unit>,worker: Chan(Unit)}
type Owner is Type:
  Owner{resource: Serial.Owner<Loader>,handle: Handle,animation: Maybe<&2,Animation>}

def defaultFrames() -> List<&2,String>:
  "⠋" <> "⠙" <> "⠹" <> "⠸" <> "⠼" <> "⠴" <> "⠦" <> "⠧" <> "⠇" <> "⠏" <> Nil{}
def defaults() -> Indicator: Indicator{defaultFrames(),80}
def validInterval(+value: U32) -> U32:
  Bool.pick(U32,U32.is_eq(value,0),80,value)
def normalize(indicator: Maybe<&2,Indicator>) -> Indicator:
  match indicator:
    case None{}: defaults()
    case Some{Indicator{frames,interval}}: Indicator{frames,validInterval(interval)}
def frameAt(frames: List<&2,String>,index: Nat) -> String:
  Maybe.default(&2,String,List.get(&2,String,frames,index),"")
def renderedIndicator(state: Loader) -> IO(String):
  match state:
    case Loader{_,_,Indicator{frames,_},index,verbatim,spinner,_,_}:
      +frame = frameAt(frames,index)
      Bool.pick(Unit -> IO(String),verbatim,_ => IO.pure(String,frame),_ => Callback.call(String,String,spinner,frame))(Unit{})
def painted(state: Loader,display: String) -> Loader:
  match state:
    case Loader{old,message,indicator,index,verbatim,spinner,color,redraw}:
      Loader{Text.setText(old,display),message,indicator,index,verbatim,spinner,color,redraw}
def refresh(+state: Loader) -> IO(Loader):
  match state:
    case Loader{_,+message,_,_,_,_,color,_}:
      do IO<Loader>:
        +paintedFrame : String <- renderedIndicator(state)
        +colored : String <- Callback.call(String,String,color,message)
        return painted(state,Bool.pick(String,String.eq(paintedFrame,""),colored,paintedFrame ++ " " ++ colored))
def initial(message: String,+indicator: Maybe<&2,Indicator>,spinner: Callback.Callback<String,String>,color: Callback.Callback<String,String>,redraw: Callback.Callback<Unit,Unit>) -> Loader:
  Loader{Text.new("",Some{1n},Some{0n},None{}),message,normalize(indicator),0n,Bool.not(Maybe.is_none(&2,Indicator,indicator)),spinner,color,redraw}
def configure(state: Loader,+indicator: Maybe<&2,Indicator>) -> Loader:
  match state:
    case Loader{text,message,_,_,_,spinner,color,redraw}:
      Loader{text,message,normalize(indicator),0n,Bool.not(Maybe.is_none(&2,Indicator,indicator)),spinner,color,redraw}
def setMessage(state: Loader,message: String) -> IO(Loader):
  match state:
    case Loader{text,_,indicator,index,verbatim,spinner,color,redraw}:
      refresh(Loader{text,message,indicator,index,verbatim,spinner,color,redraw})
def invalidate(state: Loader) -> IO(Loader):
  match state:
    case Loader{text,message,indicator,index,verbatim,spinner,color,redraw}:
      refresh(Loader{Text.invalidate(text),message,indicator,index,verbatim,spinner,color,redraw})
def next(state: Loader) -> IO(Loader):
  match state:
    case Loader{text,message,Indicator{+frames,interval},index,verbatim,spinner,color,redraw}:
      +count = List.length(&2,String,frames)
      refresh(Loader{text,message,Indicator{frames,interval},(index + 1n) % Nat.max(1n,count),verbatim,spinner,color,redraw})
def interval(state: Loader) -> U32:
  match state: case Loader{_,_,Indicator{_,value},_,_,_,_,_}: value
def animated(state: Loader) -> Bool:
  match state: case Loader{_,_,Indicator{frames,_},_,_,_,_,_}: Nat.is_gt(List.length(&2,String,frames),1n)
def renderPair(result: Text.Text & List<&2,String>,message: String,indicator: Indicator,index: Nat,verbatim: Bool,spinner: Callback.Callback<String,String>,color: Callback.Callback<String,String>,redraw: Callback.Callback<Unit,Unit>) -> Loader & List<&2,String>:
  match result:
    case (updated,lines): (Loader{updated,message,indicator,index,verbatim,spinner,color,redraw},"" <> lines)
def render(state: Loader,width: Nat) -> IO(Loader & List<&2,String>):
  match state:
    case Loader{text,message,indicator,index,verbatim,spinner,color,redraw}:
      do IO<Loader & List<&2,String>>:
        result : Text.Text & List<&2,String> <- Text.render(text,width)
        return renderPair(result,message,indicator,index,verbatim,spinner,color,redraw)

def redrawCallback(state: Loader) -> Callback.Callback<Unit,Unit>:
  match state: case Loader{_,_,_,_,_,_,_,redraw}: redraw
def apply(handle: Handle,operation: Loader -> IO(Loader)) -> IO(Unit):
  match handle:
    case Handle{resource}:
      do IO<Unit>:
        redraw : Callback.Callback<Unit,Unit> <- Serial.run(Loader,Callback.Callback<Unit,Unit>,resource,state => do IO<Loader & Callback.Callback<Unit,Unit>>:
          +updated : Loader <- operation(state)
          return (updated,redrawCallback(updated)))
        Callback.call(Unit,Unit,redraw,Unit{})
def updateMessage(handle: Handle,message: String) -> IO(Unit):
  apply(handle,state => setMessage(state,message))
def invalidateLive(handle: Handle) -> IO(Unit):
  apply(handle,state => invalidate(state))
def renderLive(handle: Handle,width: Nat) -> IO(List<&2,String>):
  match handle:
    case Handle{resource}: Serial.run(Loader,List<&2,String>,resource,state => render(state,width))

def animationInterval(handle: Handle) -> IO(U32):
  match handle:
    case Handle{resource}: Serial.run(Loader,U32,resource,+state => IO.pure(Loader & U32,(state,interval(state))))
def isAnimated(handle: Handle) -> IO(Bool):
  match handle:
    case Handle{resource}: Serial.run(Loader,Bool,resource,+state => IO.pure(Loader & Bool,(state,animated(state))))
@unsafe def animate(+handle: Handle,+signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  do IO<Unit>:
    milliseconds : U32 <- animationInterval(handle)
    elapsed : Result<&2,&2,Abort.AbortReason<Unit>,Unit> <- Timer.sleep(Unit,milliseconds,signal)
    Bool.pick(Unit -> IO(Unit),Result.is_done(&2,&2,Abort.AbortReason<Unit>,Unit,elapsed),
      _ => do IO<Unit>:
        apply(handle,next)
        animate(handle,signal),
      _ => IO.pure(Unit,Unit{}))(Unit{})
def begin(resource: Serial.Owner<Loader>,+handle: Handle,active: Bool) -> IO(Owner):
  match active:
    case False{}: IO.pure(Owner,Owner{resource,handle,None{}})
    case True{}:
      do IO<Owner>:
        +cancel : Abort.AbortController<Unit> <- Abort.new(Unit)
        worker : Chan(Unit) <- IO.fork(Unit,animate(handle,Abort.signal(Unit,cancel)))
        return Owner{resource,handle,Some{Animation{cancel,worker}}}
def stop(owner: Owner) -> IO(Owner):
  match owner:
    case Owner{resource,+handle,None{}}: IO.pure(Owner,Owner{resource,handle,None{}})
    case Owner{resource,handle,Some{Animation{+cancel,worker}}}:
      do IO<Owner>:
        cancelled : Bool <- Abort.abort(Unit,cancel,None{})
        joined : Unit <- IO.join(Unit,worker)
        Abort.dispose(Unit,cancel)
        return Owner{resource,handle,None{}}
def startStopped(owner: Owner) -> IO(Owner):
  match owner:
    case Owner{resource,+handle,None{}}:
      do IO<Owner>:
        apply(handle,state => refresh(state))
        active : Bool <- isAnimated(handle)
        begin(resource,handle,active)
    case Owner{resource,handle,Some{animation}}: IO.pure(Owner,Owner{resource,handle,Some{animation}})
def start(owner: Owner) -> IO(Owner):
  do IO<Owner>:
    stopped : Owner <- stop(owner)
    startStopped(stopped)
def setConfiguration(handle: Handle,indicator: Maybe<&2,Indicator>) -> IO(Unit):
  match handle:
    case Handle{resource}: Serial.run(Loader,Unit,resource,state => IO.pure(Loader & Unit,(configure(state,indicator),Unit{})))
def reconfigured(stopped: Owner,indicator: Maybe<&2,Indicator>) -> IO(Owner):
  match stopped:
    case Owner{resource,+handle,animation}:
      do IO<Owner>:
        setConfiguration(handle,indicator)
        start(Owner{resource,handle,animation})
def setIndicator(owner: Owner,indicator: Maybe<&2,Indicator>) -> IO(Owner):
  do IO<Owner>:
    stopped : Owner <- stop(owner)
    reconfigured(stopped,indicator)
def borrowed(pair: Serial.Owner<Loader> & Serial.Handle<Loader>) -> IO(Owner):
  match pair:
    case (resource,handle): start(Owner{resource,Handle{handle},None{}})
def create(message: String,indicator: Maybe<&2,Indicator>,spinner: Callback.Callback<String,String>,color: Callback.Callback<String,String>,redraw: Callback.Callback<Unit,Unit>) -> IO(Owner):
  do IO<Owner>:
    state : Loader <- IO.pure(Loader,initial(message,indicator,spinner,color,redraw))
    resource : Serial.Owner<Loader> <- Serial.create(Loader,state)
    borrowed(Serial.borrow(Loader,resource))
def borrow(owner: Owner) -> Owner & Handle:
  match owner:
    case Owner{resource,+handle,animation}: (Owner{resource,handle,animation},handle)
def retired(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{resource,_,_}:
      do IO<Unit>:
        discarded : Loader <- Serial.retire(Loader,resource)
        return Unit{}
def dispose(owner: Owner) -> IO(Unit):
  do IO<Unit>:
    stopped : Owner <- stop(owner)
    retired(stopped)

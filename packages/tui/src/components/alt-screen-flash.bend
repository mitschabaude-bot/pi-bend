import Base
import ../utils.bend as Utils
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/serial-resource.bend as Serial
import ../../../runtime/src/timer.bend as Timer

type Entry is Data:
  Entry{message: String,deadline: Nat}
type AltScreenFlashContainer is Data:
  AltScreenFlashContainer{entries: List<&2,Entry>,requestRender: Callback.Callback<Unit,Unit>}
type Handle is Data: Handle{resource: Serial.Handle<AltScreenFlashContainer>}
type Expiry is Data:
  Expiry{cancel: Abort.AbortController<Unit>,worker: Chan(Unit)}
type Owner is Type:
  Owner{resource: Serial.Owner<AltScreenFlashContainer>,handle: Handle,expiry: Maybe<&2,Expiry>}

def initial(redraw: Callback.Callback<Unit,Unit>) -> AltScreenFlashContainer:
  AltScreenFlashContainer{Nil{},redraw}
def append(state: AltScreenFlashContainer,message: String,deadline: Nat) -> AltScreenFlashContainer:
  match state:
    case AltScreenFlashContainer{entries,redraw}:
      AltScreenFlashContainer{List.append(&2,Entry,entries,Entry{message,deadline} <> Nil{}),redraw}
def deadlineOf(entry: Entry) -> Nat:
  match entry: case Entry{_,value}: value
def earlier(candidate: Maybe<&2,Nat>,deadline: Nat) -> Maybe<&2,Nat>:
  match candidate:
    case None{}: Some{deadline}
    case Some{value}: Some{Nat.min(value,deadline)}
def earliest(entries: List<&2,Entry>,candidate: Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match entries:
    case Nil{}: candidate
    case Entry{_,deadline} <> rest: earliest(rest,earlier(candidate,deadline))
def prepend(entry: Entry,pair: List<&2,Entry> & Bool) -> List<&2,Entry> & Bool:
  match pair: case (entries,removed): (entry <> entries,removed)
def withoutFirst(entries: List<&2,Entry>,+target: Nat) -> List<&2,Entry> & Bool:
  match entries:
    case Nil{}: (Nil{},False{})
    case +entry <> +rest:
      Bool.pick(Unit -> List<&2,Entry> & Bool,Nat.is_eq(deadlineOf(entry),target),
        _ => (rest,True{}),
        _ => prepend(entry,withoutFirst(rest,target)))(Unit{})
def expireResult(pair: List<&2,Entry> & Bool,redraw: Callback.Callback<Unit,Unit>) -> AltScreenFlashContainer & Bool:
  match pair: case (remaining,removed): (AltScreenFlashContainer{remaining,redraw},removed)
def expireCandidate(+entries: List<&2,Entry>,+redraw: Callback.Callback<Unit,Unit>,now: Nat,candidate: Maybe<&2,Nat>) -> AltScreenFlashContainer & Bool:
  match candidate:
    case None{}: (AltScreenFlashContainer{entries,redraw},False{})
    case Some{+deadline}:
      Bool.pick(Unit -> AltScreenFlashContainer & Bool,Nat.is_le(deadline,now),
        _ => expireResult(withoutFirst(entries,deadline),redraw),
        _ => (AltScreenFlashContainer{entries,redraw},False{}))(Unit{})
def expired(state: AltScreenFlashContainer,now: Nat) -> AltScreenFlashContainer & Bool:
  match state:
    case AltScreenFlashContainer{+entries,redraw}: expireCandidate(entries,redraw,now,earliest(entries,None{}))
def delay(state: AltScreenFlashContainer,now: Nat) -> Maybe<&2,U32>:
  match state:
    case AltScreenFlashContainer{entries,_}:
      Maybe.map(&2,Nat,U32,deadline => U32.from_nat(Nat.min(4294967295n,deadline - now)),earliest(entries,None{}))
def callback(state: AltScreenFlashContainer) -> Callback.Callback<Unit,Unit>:
  match state: case AltScreenFlashContainer{_,redraw}: redraw

def renderEntry(entry: Entry,width: Nat) -> String:
  match entry:
    case Entry{message,_}: "\u{1b}[7m" ++ Utils.truncateToWidth(" " ++ message ++ " ",width,"",False{}) ++ "\u{1b}[27m"
def renderEntries(entries: List<&2,Entry>,+width: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match entries:
    case Nil{}: List.reverse(&2,String,reversed)
    case entry <> rest: renderEntries(rest,width,renderEntry(entry,width) <> reversed)
def render(state: AltScreenFlashContainer,width: Nat) -> List<&2,String>:
  match state: case AltScreenFlashContainer{entries,_}: renderEntries(entries,width,Nil{})
def invalidate(state: AltScreenFlashContainer) -> AltScreenFlashContainer: state

def renderLive(handle: Handle,width: Nat) -> IO(List<&2,String>):
  match handle:
    case Handle{resource}: Serial.run(AltScreenFlashContainer,List<&2,String>,resource,+state => IO.pure(AltScreenFlashContainer & List<&2,String>,(state,render(state,width))))
def add(handle: Handle,message: String,deadline: Nat) -> IO(Unit):
  match handle:
    case Handle{resource}:
      do IO<Unit>:
        redraw : Callback.Callback<Unit,Unit> <- Serial.run(AltScreenFlashContainer,Callback.Callback<Unit,Unit>,resource,+state =>
          IO.pure(AltScreenFlashContainer & Callback.Callback<Unit,Unit>,(append(state,message,deadline),callback(state))))
        Callback.call(Unit,Unit,redraw,Unit{})
def nextDelay(handle: Handle,now: Nat) -> IO(Maybe<&2,U32>):
  match handle:
    case Handle{resource}: Serial.run(AltScreenFlashContainer,Maybe<&2,U32>,resource,+state => IO.pure(AltScreenFlashContainer & Maybe<&2,U32>,(state,delay(state,now))))
def removal(pair: AltScreenFlashContainer & Bool) -> AltScreenFlashContainer & (Callback.Callback<Unit,Unit> & Bool):
  match pair:
    case (+updated,didRemove): (updated,(callback(updated),didRemove))
def removed(state: AltScreenFlashContainer,now: Nat) -> AltScreenFlashContainer & (Callback.Callback<Unit,Unit> & Bool):
  removal(expired(state,now))
def notify(pair: Callback.Callback<Unit,Unit> & Bool) -> IO(Unit):
  match pair:
    case (redraw,True{}): Callback.call(Unit,Unit,redraw,Unit{})
    case (_,False{}): IO.pure(Unit,Unit{})
def removeExpired(handle: Handle,now: Nat) -> IO(Unit):
  match handle:
    case Handle{resource}:
      do IO<Unit>:
        pair : Callback.Callback<Unit,Unit> & Bool <- Serial.run(AltScreenFlashContainer,Callback.Callback<Unit,Unit> & Bool,resource,+state =>
          IO.pure(AltScreenFlashContainer & (Callback.Callback<Unit,Unit> & Bool),removed(state,now)))
        notify(pair)
# A single owned timer follows the earliest deadline. Each wake removes one
# entry so equal-deadline flashes request separate redraws in insertion order.
@unsafe def worker(+handle: Handle,+signal: Abort.AbortSignal<Unit>) -> IO(Unit):
  do IO<Unit>:
    now : Nat <- IO.now()
    +next : Maybe<&2,U32> <- nextDelay(handle,now)
    Bool.pick(Unit -> IO(Unit),Maybe.is_none(&2,U32,next),
      _ => IO.pure(Unit,Unit{}),
      _ => do IO<Unit>:
        elapsed : Result<&2,&2,Abort.AbortReason<Unit>,Unit> <- Timer.sleep(Unit,Maybe.default(&2,U32,next,0),signal)
        Bool.pick(Unit -> IO(Unit),Result.is_done(&2,&2,Abort.AbortReason<Unit>,Unit,elapsed),
          _ => do IO<Unit>:
            now : Nat <- IO.now()
            removeExpired(handle,now)
            worker(handle,signal),
          _ => IO.pure(Unit,Unit{}))(Unit{}))(Unit{})
def start(resource: Serial.Owner<AltScreenFlashContainer>,+handle: Handle) -> IO(Owner):
  do IO<Owner>:
    +cancel : Abort.AbortController<Unit> <- Abort.new(Unit)
    task : Chan(Unit) <- IO.fork(Unit,worker(handle,Abort.signal(Unit,cancel)))
    return Owner{resource,handle,Some{Expiry{cancel,task}}}
def stop(owner: Owner) -> IO(Owner):
  match owner:
    case Owner{resource,handle,None{}}: IO.pure(Owner,Owner{resource,handle,None{}})
    case Owner{resource,handle,Some{Expiry{+cancel,task}}}:
      do IO<Owner>:
        cancelled : Bool <- Abort.abort(Unit,cancel,None{})
        joined : Unit <- IO.join(Unit,task)
        Abort.dispose(Unit,cancel)
        return Owner{resource,handle,None{}}
def added(owner: Owner,message: String,durationMs: U32) -> IO(Owner):
  match owner:
    case Owner{resource,+handle,_}:
      do IO<Owner>:
        now : Nat <- IO.now()
        add(handle,message,now + U32.to_nat(durationMs))
        start(resource,handle)
def flash(owner: Owner,message: String,durationMs: Maybe<&2,U32>) -> IO(Owner):
  do IO<Owner>:
    stopped : Owner <- stop(owner)
    added(stopped,message,Maybe.default(&2,U32,durationMs,1000))
def borrow(owner: Owner) -> Owner & Handle:
  match owner:
    case Owner{resource,+handle,expiry}: (Owner{resource,handle,expiry},handle)
def owned(pair: Serial.Owner<AltScreenFlashContainer> & Serial.Handle<AltScreenFlashContainer>) -> Owner:
  match pair: case (resource,handle): Owner{resource,Handle{handle},None{}}
def create(redraw: Callback.Callback<Unit,Unit>) -> IO(Owner):
  do IO<Owner>:
    resource : Serial.Owner<AltScreenFlashContainer> <- Serial.create(AltScreenFlashContainer,initial(redraw))
    return owned(Serial.borrow(AltScreenFlashContainer,resource))
def retired(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{resource,_,_}:
      do IO<Unit>:
        state : AltScreenFlashContainer <- Serial.retire(AltScreenFlashContainer,resource)
        return Unit{}
def dispose(owner: Owner) -> IO(Unit):
  do IO<Unit>:
    stopped : Owner <- stop(owner)
    retired(stopped)

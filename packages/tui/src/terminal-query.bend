import Base
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/deferred.bend as Deferred
import ../../runtime/src/serial-resource.bend as Serial
import ./terminal-colors.bend as Colors

# A timed-out OSC 11 request retains its queue slot until its reply arrives.
# Completed deferred values remain owned by the session until close, since a
# reply can arrive between registration and the caller's first observation.
type ColorReply is Data: ColorReply{value: Deferred.Deferred<Maybe<&2,Colors.RgbColor>>}
type SchemeReply is Data: SchemeReply{value: Deferred.Deferred<Maybe<&2,Colors.TerminalColorScheme>>}
type Listener is Data: Listener{id: Nat, callback: Callback.Callback<Colors.TerminalColorScheme,Unit>}
type State is Type:
  State{colors: List<&2,ColorReply>, schemes: List<&2,SchemeReply>, listeners: List<&2,Listener>, retiredColors: List<&2,ColorReply>, retiredSchemes: List<&2,SchemeReply>, nextListener: Nat, notifications: Bool, stopped: Bool}
type Owner is Type: Owner{state: Serial.Owner<State>}
type Handle is Data: Handle{state: Serial.Handle<State>}
type Consumption is Data: Consumption{consumed: Bool, listeners: List<&2,Listener>, scheme: Maybe<&2,Colors.TerminalColorScheme>}

def initial() -> State: State{Nil{},Nil{},Nil{},Nil{},Nil{},0n,False{},True{}}
def create() -> IO(Owner):
  do IO<Owner>:
    state : Serial.Owner<State> <- Serial.create(State,initial())
    return Owner{state}
def borrowed(pair: Serial.Owner<State> & Serial.Handle<State>) -> Owner & Handle:
  match pair:
    case (next,handle): (Owner{next},Handle{handle})
def borrow(owner: Owner) -> Owner & Handle:
  match owner:
    case Owner{state}: borrowed(Serial.borrow(State,state))

def addColor(reply: Deferred.Deferred<Maybe<&2,Colors.RgbColor>>,state: State) -> State & Unit:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped}:
      (State{List.append(&2,ColorReply,colors,ColorReply{reply} <> Nil{}),schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped},Unit{})
def addScheme(reply: Deferred.Deferred<Maybe<&2,Colors.TerminalColorScheme>>,state: State) -> State & Unit:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped}:
      (State{colors,SchemeReply{reply} <> schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped},Unit{})
def registerColor(handle: Handle,reply: Deferred.Deferred<Maybe<&2,Colors.RgbColor>>) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State,Unit,state,current => IO.pure(State & Unit,addColor(reply,current)))
def registerScheme(handle: Handle,reply: Deferred.Deferred<Maybe<&2,Colors.TerminalColorScheme>>) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State,Unit,state,current => IO.pure(State & Unit,addScheme(reply,current)))

def timerColorResult(reply: Deferred.Deferred<Maybe<&2,Colors.RgbColor>>,result: Timer & Bool) -> IO(Unit):
  match result:
    case (timer,ready):
      do IO<Unit>:
        Timer.close(timer)
        Bool.pick(Unit -> IO(Unit),ready,
          _ => do IO<Unit>:
            settled : Bool <- Deferred.resolve(Maybe<&2,Colors.RgbColor>,reply,None{})
            return Unit{},
          _ => IO.pure(Unit,Unit{}))(Unit{})
def timeoutColor(reply: Deferred.Deferred<Maybe<&2,Colors.RgbColor>>,owner: Timer) -> IO(Unit):
  do IO<Unit>:
    result : Timer & Bool <- Timer.wait(owner)
    timerColorResult(reply,result)
def timerSchemeResult(reply: Deferred.Deferred<Maybe<&2,Colors.TerminalColorScheme>>,result: Timer & Bool) -> IO(Unit):
  match result:
    case (timer,ready):
      do IO<Unit>:
        Timer.close(timer)
        Bool.pick(Unit -> IO(Unit),ready,
          _ => do IO<Unit>:
            settled : Bool <- Deferred.resolve(Maybe<&2,Colors.TerminalColorScheme>,reply,None{})
            return Unit{},
          _ => IO.pure(Unit,Unit{}))(Unit{})
def timeoutScheme(reply: Deferred.Deferred<Maybe<&2,Colors.TerminalColorScheme>>,owner: Timer) -> IO(Unit):
  do IO<Unit>:
    result : Timer & Bool <- Timer.wait(owner)
    timerSchemeResult(reply,result)

def awaitColor(reply: Deferred.Deferred<Maybe<&2,Colors.RgbColor>>,cancel: TimerCancel,worker: Chan(Unit)) -> IO(Maybe<&2,Colors.RgbColor>):
  do IO<Maybe<&2,Colors.RgbColor>>:
    value : Maybe<&2,Colors.RgbColor> <- Deferred.result(Maybe<&2,Colors.RgbColor>,reply)
    cancelled : Bool <- Timer.cancel(cancel)
    finished : Unit <- IO.join(Unit,worker)
    return value

def startedColor(+reply: Deferred.Deferred<Maybe<&2,Colors.RgbColor>>,write: Callback.Callback<String,Unit>,pair: Timer & TimerCancel) -> IO(Maybe<&2,Colors.RgbColor>):
  match pair:
    case (timer,cancel):
      do IO<Maybe<&2,Colors.RgbColor>>:
        worker : Chan(Unit) <- IO.fork(Unit,timeoutColor(reply,timer))
        written : Unit <- Callback.call(String,Unit,write,"\u{1b}]11;?\u{7}")
        awaitColor(reply,cancel,worker)
def colorQuery(handle: Handle,+write: Callback.Callback<String,Unit>,timeoutMs: U32) -> IO(Maybe<&2,Colors.RgbColor>):
  do IO<Maybe<&2,Colors.RgbColor>>:
    +reply : Deferred.Deferred<Maybe<&2,Colors.RgbColor>> <- Deferred.new(Maybe<&2,Colors.RgbColor>)
    registerColor(handle,reply)
    pair : Timer & TimerCancel <- Timer.new(timeoutMs)
    startedColor(reply,write,pair)


def awaitScheme(reply: Deferred.Deferred<Maybe<&2,Colors.TerminalColorScheme>>,cancel: TimerCancel,worker: Chan(Unit)) -> IO(Maybe<&2,Colors.TerminalColorScheme>):
  do IO<Maybe<&2,Colors.TerminalColorScheme>>:
    value : Maybe<&2,Colors.TerminalColorScheme> <- Deferred.result(Maybe<&2,Colors.TerminalColorScheme>,reply)
    cancelled : Bool <- Timer.cancel(cancel)
    finished : Unit <- IO.join(Unit,worker)
    return value

def startedScheme(+reply: Deferred.Deferred<Maybe<&2,Colors.TerminalColorScheme>>,write: Callback.Callback<String,Unit>,pair: Timer & TimerCancel) -> IO(Maybe<&2,Colors.TerminalColorScheme>):
  match pair:
    case (timer,cancel):
      do IO<Maybe<&2,Colors.TerminalColorScheme>>:
        worker : Chan(Unit) <- IO.fork(Unit,timeoutScheme(reply,timer))
        written : Unit <- Callback.call(String,Unit,write,"\u{1b}[?996n")
        awaitScheme(reply,cancel,worker)
def schemeQuery(handle: Handle,+write: Callback.Callback<String,Unit>,timeoutMs: U32) -> IO(Maybe<&2,Colors.TerminalColorScheme>):
  do IO<Maybe<&2,Colors.TerminalColorScheme>>:
    +reply : Deferred.Deferred<Maybe<&2,Colors.TerminalColorScheme>> <- Deferred.new(Maybe<&2,Colors.TerminalColorScheme>)
    registerScheme(handle,reply)
    pair : Timer & TimerCancel <- Timer.new(timeoutMs)
    startedScheme(reply,write,pair)


def popColor(state: State,value: Maybe<&2,Colors.RgbColor>) -> IO(State & Consumption):
  match state:
    case State{Nil{},schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped}:
      IO.pure(State & Consumption,(state,Consumption{False{},Nil{},None{}}))
    case State{ColorReply{+reply} <> rest,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped}:
      do IO<State & Consumption>:
        settled : Bool <- Deferred.resolve(Maybe<&2,Colors.RgbColor>,reply,value)
        return (State{rest,schemes,listeners,ColorReply{reply} <> retiredColors,retiredSchemes,next,notifications,stopped},Consumption{True{},Nil{},None{}})

def settleSchemes(replies: List<&2,SchemeReply>,+value: Colors.TerminalColorScheme) -> IO(Unit):
  match replies:
    case Nil{}: IO.pure(Unit,Unit{})
    case SchemeReply{+reply} <> rest:
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(Maybe<&2,Colors.TerminalColorScheme>,reply,Some{value})
        settleSchemes(rest,value)
def consumeScheme(state: State,+value: Colors.TerminalColorScheme) -> IO(State & Consumption):
  match state:
    case State{colors,+schemes,+listeners,retiredColors,retiredSchemes,next,notifications,stopped}:
      do IO<State & Consumption>:
        settleSchemes(schemes,value)
        return (State{colors,Nil{},listeners,retiredColors,List.append(&2,SchemeReply,schemes,retiredSchemes),next,notifications,stopped},Consumption{True{},listeners,Some{value}})
def consumeOsc(data: String,state: State,recognized: Bool) -> IO(State & Consumption):
  match recognized:
    case True{}: popColor(state,Colors.parseOsc11BackgroundColor(data))
    case False{}: IO.pure(State & Consumption,(state,Consumption{False{},Nil{},None{}}))
def consumeParsed(+data: String,state: State,parsed: Maybe<&2,Colors.TerminalColorScheme>) -> IO(State & Consumption):
  match parsed:
    case Some{value}: consumeScheme(state,value)
    case None{}: consumeOsc(data,state,Colors.isOsc11BackgroundColorResponse(data))
def consumeLocked(+data: String,state: State) -> IO(State & Consumption): consumeParsed(data,state,Colors.parseTerminalColorSchemeReport(data))
def notifyListeners(listeners: List<&2,Listener>,+value: Colors.TerminalColorScheme) -> IO(Unit):
  match listeners:
    case Nil{}: IO.pure(Unit,Unit{})
    case Listener{_,callback} <> rest:
      do IO<Unit>:
        Callback.call(Colors.TerminalColorScheme,Unit,callback,value)
        notifyListeners(rest,value)
def notified(consumption: Consumption) -> IO(Bool):
  match consumption:
    case Consumption{consumed,listeners,None{}}: IO.pure(Bool,consumed)
    case Consumption{consumed,listeners,Some{value}}:
      do IO<Bool>:
        notifyListeners(listeners,value)
        return consumed
# Call before ordinary input dispatch. True means the reply was consumed.
def consume(handle: Handle,data: String) -> IO(Bool):
  match handle:
    case Handle{state}:
      do IO<Bool>:
        result : Consumption <- Serial.run(State,Consumption,state,current => consumeLocked(data,current))
        notified(result)

def added(callback: Callback.Callback<Colors.TerminalColorScheme,Unit>,state: State) -> State & Nat:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,+next,notifications,stopped}:
      (State{colors,schemes,Listener{next,callback} <> listeners,retiredColors,retiredSchemes,next + 1n,notifications,stopped},next)
def onSchemeChange(handle: Handle,callback: Callback.Callback<Colors.TerminalColorScheme,Unit>) -> IO(Nat):
  match handle:
    case Handle{state}: Serial.run(State,Nat,state,current => IO.pure(State & Nat,added(callback,current)))
def removeListener(+id: Nat,listeners: List<&2,Listener>) -> List<&2,Listener>:
  match listeners:
    case Nil{}: Nil{}
    case Listener{+key,callback} <> +rest:
      Bool.pick(List<&2,Listener>,Nat.is_eq(id,key),rest,Listener{key,callback} <> removeListener(id,rest))
def removed(id: Nat,state: State) -> State & Unit:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped}:
      (State{colors,schemes,removeListener(id,listeners),retiredColors,retiredSchemes,next,notifications,stopped},Unit{})
def offSchemeChange(handle: Handle,id: Nat) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State,Unit,state,current => IO.pure(State & Unit,removed(id,current)))

def notificationState(+enabled: Bool,state: State) -> State & Bool:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,+old,+stopped}:
      (State{colors,schemes,listeners,retiredColors,retiredSchemes,next,enabled,stopped},(old && Bool.not(enabled) || Bool.not(old) && enabled) && Bool.not(stopped))
def setNotifications(handle: Handle,write: Callback.Callback<String,Unit>,+enabled: Bool) -> IO(Unit):
  match handle:
    case Handle{state}:
      do IO<Unit>:
        changed : Bool <- Serial.run(State,Bool,state,current => IO.pure(State & Bool,notificationState(enabled,current)))
        Bool.pick(Unit -> IO(Unit),changed,
          _ => Callback.call(String,Unit,write,Bool.pick(String,enabled,"\u{1b}[?2031h","\u{1b}[?2031l")),
          _ => IO.pure(Unit,Unit{}))(Unit{})
def runningState(+running: Bool,state: State) -> State & Bool:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,+enabled,+stopped}:
      (State{colors,schemes,listeners,retiredColors,retiredSchemes,next,enabled,Bool.not(running)},enabled && (stopped && running || Bool.not(stopped) && Bool.not(running)))
def setRunning(handle: Handle,write: Callback.Callback<String,Unit>,+running: Bool) -> IO(Unit):
  match handle:
    case Handle{state}:
      do IO<Unit>:
        enabled : Bool <- Serial.run(State,Bool,state,current => IO.pure(State & Bool,runningState(running,current)))
        Bool.pick(Unit -> IO(Unit),enabled,
          _ => Callback.call(String,Unit,write,Bool.pick(String,running,"\u{1b}[?2031h","\u{1b}[?2031l")),
          _ => IO.pure(Unit,Unit{}))(Unit{})

def disposeColors(replies: List<&2,ColorReply>) -> IO(Unit):
  match replies:
    case Nil{}: IO.pure(Unit,Unit{})
    case ColorReply{reply} <> rest:
      do IO<Unit>:
        Deferred.dispose(Maybe<&2,Colors.RgbColor>,reply)
        disposeColors(rest)
def disposeSchemes(replies: List<&2,SchemeReply>) -> IO(Unit):
  match replies:
    case Nil{}: IO.pure(Unit,Unit{})
    case SchemeReply{+reply} <> rest:
      do IO<Unit>:
        Deferred.dispose(Maybe<&2,Colors.TerminalColorScheme>,reply)
        disposeSchemes(rest)
def disposeState(value: State) -> IO(Unit):
  match value:
    case State{colors,schemes,_,retiredColors,retiredSchemes,_,_,_}:
      do IO<Unit>:
        disposeColors(colors)
        disposeColors(retiredColors)
        disposeSchemes(schemes)
        disposeSchemes(retiredSchemes)
# The caller joins all outstanding query tasks before retiring the owner.
def close(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{state}:
      do IO<Unit>:
        value : State <- Serial.retire(State,state)
        disposeState(value)

import Base
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/deferred.bend as Deferred
import ../../runtime/src/serial-resource.bend as Serial
import ./terminal-colors.bend as Colors
import ./terminal-image.bend as Image

# A timed-out OSC 11 request retains its queue slot until its reply arrives.
# Completed deferred values remain owned by the session until close, since a
# reply can arrive between registration and the caller's first observation.
type ColorReply is Data: ColorReply{value: Deferred.Deferred<Maybe<&2,Colors.RgbColor>>}
type SchemeReply is Data: SchemeReply{value: Deferred.Deferred<Maybe<&2,Colors.TerminalColorScheme>>}
type Listener is Data: Listener{id: Nat, callback: Callback.Callback<Colors.TerminalColorScheme,Unit>}
# upstream TuiInputListener / TuiInputListenerResult: None is `undefined`.
type TuiInputListenerResult is Data: TuiInputListenerResult{consume: Bool, data: Maybe<&2,String>}
type InputListener is Data: InputListener{id: Nat, callback: Callback.Callback<String,Maybe<&2,TuiInputListenerResult>>}
type State is Type:
  State{colors: List<&2,ColorReply>, schemes: List<&2,SchemeReply>, listeners: List<&2,Listener>, retiredColors: List<&2,ColorReply>, retiredSchemes: List<&2,SchemeReply>, nextListener: Nat, notifications: Bool, stopped: Bool, cells: Image.CellDimensions, inputListeners: List<&2,InputListener>}
type Owner is Type: Owner{state: Serial.Owner<State>}
type Handle is Data: Handle{state: Serial.Handle<State>}
type Consumption is Data: Consumption{consumed: Bool, listeners: List<&2,Listener>, scheme: Maybe<&2,Colors.TerminalColorScheme>}

def initial() -> State: State{Nil{},Nil{},Nil{},Nil{},Nil{},0n,False{},True{},Image.defaultCellDimensions(),Nil{}}
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
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs}:
      (State{List.append(&2,ColorReply,colors,ColorReply{reply} <> Nil{}),schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs},Unit{})
def addScheme(reply: Deferred.Deferred<Maybe<&2,Colors.TerminalColorScheme>>,state: State) -> State & Unit:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs}:
      (State{colors,SchemeReply{reply} <> schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs},Unit{})
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
    case State{Nil{},schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs}:
      IO.pure(State & Consumption,(state,Consumption{False{},Nil{},None{}}))
    case State{ColorReply{+reply} <> rest,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs}:
      do IO<State & Consumption>:
        settled : Bool <- Deferred.resolve(Maybe<&2,Colors.RgbColor>,reply,value)
        return (State{rest,schemes,listeners,ColorReply{reply} <> retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs},Consumption{True{},Nil{},None{}})

def settleSchemes(replies: List<&2,SchemeReply>,+value: Colors.TerminalColorScheme) -> IO(Unit):
  match replies:
    case Nil{}: IO.pure(Unit,Unit{})
    case SchemeReply{+reply} <> rest:
      do IO<Unit>:
        settled : Bool <- Deferred.resolve(Maybe<&2,Colors.TerminalColorScheme>,reply,Some{value})
        settleSchemes(rest,value)
def consumeScheme(state: State,+value: Colors.TerminalColorScheme) -> IO(State & Consumption):
  match state:
    case State{colors,+schemes,+listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs}:
      do IO<State & Consumption>:
        settleSchemes(schemes,value)
        return (State{colors,Nil{},listeners,retiredColors,List.append(&2,SchemeReply,schemes,retiredSchemes),next,notifications,stopped,cells,inputs},Consumption{True{},listeners,Some{value}})
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

# upstream TuiBase.consumeCellSizeResponse: a whole "ESC [ 6 ; height ; width t"
# reply (the answer to "ESC [ 16 t") is consumed; positive sizes become the
# cell dimensions that image sizing reads (terminal-image's
# setCellDimensions). Digits accumulate in F64, as parseInt does.
type CellReply is Data: CellReply{heightPx: F64,widthPx: F64}
type Digits is Data: Digits{value: F64,rest: String}
def digits(text: String,+value: F64,seen: Bool,+stop: Char) -> Maybe<&2,Digits>:
  match text:
    case SCon{+char,+rest}:
      +code = Char.to_u32(char)
      Bool.pick(Unit -> Maybe<&2,Digits>,U32.is_ge(code,48) && U32.is_le(code,57),
        _ => digits(rest,F64.add(F64.mul(value,U32.to_f64(10)),U32.to_f64((code - 48 : U32))),True{},stop),
        _ => Bool.pick(Maybe<&2,Digits>,seen && Char.is_eq(char,stop),Some{Digits{value,rest}},None{}))(Unit{})
    case SNil{}: None{}
def widthPart(+height: F64,value: Maybe<&2,Digits>) -> Maybe<&2,CellReply>:
  match value:
    case Some{Digits{width,SNil{}}}: Some{CellReply{height,width}}
    case _: None{}
def heightPart(value: Maybe<&2,Digits>) -> Maybe<&2,CellReply>:
  match value:
    case Some{Digits{height,rest}}: widthPart(height,digits(rest,U32.to_f64(0),False{},'t'))
    case None{}: None{}
def cellReplyAfter(rest: Maybe<&2,String>) -> Maybe<&2,CellReply>:
  match rest:
    case Some{rest}: heightPart(digits(rest,U32.to_f64(0),False{},';'))
    case None{}: None{}
def afterPrefix(expected: String,input: String) -> Maybe<&2,String>:
  match expected input:
    case SNil{} input: Some{input}
    case SCon{wanted,rest} SCon{+char,tail}: Bool.pick(Unit -> Maybe<&2,String>,Char.is_eq(wanted,char),_ => afterPrefix(rest,tail),_ => None{})(Unit{})
    case _ _: None{}
def parseCellSizeResponse(data: String) -> Maybe<&2,CellReply>: cellReplyAfter(afterPrefix("\u{1b}[6;",data))
def cellsSet(reply: CellReply,state: State) -> State & Bool:
  match reply state:
    case CellReply{+height,+width} State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs}:
      +valid = F64.is_gt(height,U32.to_f64(0)) && F64.is_gt(width,U32.to_f64(0))
      (State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,Bool.pick(Image.CellDimensions,valid,Image.CellDimensions{width,height},cells),inputs},valid)
def cellsParsed(handle: Handle,reply: Maybe<&2,CellReply>) -> IO(Maybe<&2,Bool>):
  match handle reply:
    case _ None{}: IO.pure(Maybe<&2,Bool>,None{})
    case Handle{state} Some{reply}:
      do IO<Maybe<&2,Bool>>:
        changed : Bool <- Serial.run(State,Bool,state,current => IO.pure(State & Bool,cellsSet(reply,current)))
        return Some{changed}
# None when `data` is not a cell size reply; Some{updated} when consumed.
def consumeCellSize(handle: Handle,data: String) -> IO(Maybe<&2,Bool>): cellsParsed(handle,parseCellSizeResponse(data))
def readCells(state: State) -> State & Image.CellDimensions:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,+cells,inputs}: (State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs},cells)
def getCellDimensions(handle: Handle) -> IO(Image.CellDimensions):
  match handle:
    case Handle{state}: Serial.run(State,Image.CellDimensions,state,current => IO.pure(State & Image.CellDimensions,readCells(current)))
# upstream TUI.addInputListener/removeInputListener. Listeners see input after
# the query replies above and before the cell size reply and dispatch, in
# registration order. A listener is removed by the id its registration
# returns (upstream returns an unsubscribe function). Each input runs the
# listeners registered when it arrives; they are called outside the lock, so
# they may register or remove listeners themselves.
def inputAdded(+callback: Callback.Callback<String,Maybe<&2,TuiInputListenerResult>>,state: State) -> State & Nat:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,+next,notifications,stopped,cells,inputs}:
      (State{colors,schemes,listeners,retiredColors,retiredSchemes,next + 1n,notifications,stopped,cells,List.append(&2,InputListener,inputs,[InputListener{next,callback}])},next)
def addInputListener(handle: Handle,callback: Callback.Callback<String,Maybe<&2,TuiInputListenerResult>>) -> IO(Nat):
  match handle:
    case Handle{state}: Serial.run(State,Nat,state,current => IO.pure(State & Nat,inputAdded(callback,current)))
def withoutInput(+id: Nat,inputs: List<&2,InputListener>) -> List<&2,InputListener>:
  match inputs:
    case Nil{}: Nil{}
    case InputListener{+key,+callback} <> +rest: Bool.pick(Unit -> List<&2,InputListener>,Nat.is_eq(key,id),_ => rest,_ => InputListener{key,callback} <> withoutInput(id,rest))(Unit{})
def inputRemoved(id: Nat,state: State) -> State & Unit:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs}:
      (State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,withoutInput(id,inputs)},Unit{})
def removeInputListener(handle: Handle,id: Nat) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State,Unit,state,current => IO.pure(State & Unit,inputRemoved(id,current)))
def readInputs(state: State) -> State & List<&2,InputListener>:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,+inputs}: (State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs},inputs)
def listenerResult(+current: String,result: Maybe<&2,TuiInputListenerResult>) -> Maybe<&2,String>:
  match result:
    case Some{TuiInputListenerResult{True{},_}}: None{}
    case Some{TuiInputListenerResult{False{},Some{data}}}: Some{data}
    case _: Some{current}
def runInputs(inputs: List<&2,InputListener>,next: Maybe<&2,String>) -> IO(Maybe<&2,String>):
  match next inputs:
    case None{} _: IO.pure(Maybe<&2,String>,None{})
    case Some{+current} Nil{}: IO.pure(Maybe<&2,String>,Bool.pick(Maybe<&2,String>,String.is_empty(current),None{},Some{current}))
    case Some{+current} InputListener{_,callback} <> rest:
      do IO<Maybe<&2,String>>:
        result : Maybe<&2,TuiInputListenerResult> <- Callback.call(String,Maybe<&2,TuiInputListenerResult>,callback,current)
        runInputs(rest,listenerResult(current,result))
def interceptListed(+data: String,+inputs: List<&2,InputListener>) -> IO(Maybe<&2,String>):
  Bool.pick(Unit -> IO(Maybe<&2,String>),List.is_empty(&2,InputListener,inputs),_ => IO.pure(Maybe<&2,String>,Some{data}),_ => runInputs(inputs,Some{data}))(Unit{})
# The input left for dispatch, or None when a listener consumed it (or left
# it empty).
def interceptInput(handle: Handle,+data: String) -> IO(Maybe<&2,String>):
  match handle:
    case Handle{state}:
      do IO<Maybe<&2,String>>:
        inputs : List<&2,InputListener> <- Serial.run(State,List<&2,InputListener>,state,current => IO.pure(State & List<&2,InputListener>,readInputs(current)))
        interceptListed(data,inputs)
def added(callback: Callback.Callback<Colors.TerminalColorScheme,Unit>,state: State) -> State & Nat:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,+next,notifications,stopped,cells,inputs}:
      (State{colors,schemes,Listener{next,callback} <> listeners,retiredColors,retiredSchemes,next + 1n,notifications,stopped,cells,inputs},next)
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
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs}:
      (State{colors,schemes,removeListener(id,listeners),retiredColors,retiredSchemes,next,notifications,stopped,cells,inputs},Unit{})
def offSchemeChange(handle: Handle,id: Nat) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State,Unit,state,current => IO.pure(State & Unit,removed(id,current)))

def notificationState(+enabled: Bool,state: State) -> State & Bool:
  match state:
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,+old,+stopped,cells,inputs}:
      (State{colors,schemes,listeners,retiredColors,retiredSchemes,next,enabled,stopped,cells,inputs},(old && Bool.not(enabled) || Bool.not(old) && enabled) && Bool.not(stopped))
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
    case State{colors,schemes,listeners,retiredColors,retiredSchemes,next,+enabled,+stopped,cells,inputs}:
      (State{colors,schemes,listeners,retiredColors,retiredSchemes,next,enabled,Bool.not(running),cells,inputs},enabled && (stopped && running || Bool.not(stopped) && Bool.not(running)))
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
    case State{colors,schemes,_,retiredColors,retiredSchemes,_,_,_,_,_}:
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

import Base
import ../../runtime/src/serial-resource.bend as Serial
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/deferred.bend as Deferred

# Incremental terminal framing. Text and paste payloads are Unicode scalars;
# bytes are decoded at the terminal boundary. Pending text is stored reversed,
# so fragmented control strings and large pastes do not copy their prefixes.
type Phase is Data:
  Plain{}
  Escape{}
  Csi{first: Bool}
  SgrMouse{fields: U32, digits: Bool, valid: Bool}
  X10{left: U32}
  Ss3{}
  Control{bell: Bool, escaped: Bool}
  Pasting{matched: U32}

type StdinBuffer is Data:
  StdinBuffer{phase: Phase, reversed: String, kitty: Maybe<&2,U32>}
type InputEvent is Data:
  DataEvent{text: String}
  PasteEvent{text: String}
type Transition is Data:
  Transition{buffer: StdinBuffer, events: List<&2,InputEvent>}
type StdinBufferOptions is Data:
  StdinBufferOptions{timeout: U32, escapeTimeout: U32}

def defaultOptions() -> StdinBufferOptions: StdinBufferOptions{50,10}
def create() -> StdinBuffer: StdinBuffer{Plain{},"",None{}}
def clear(buffer: StdinBuffer) -> StdinBuffer: create()
def destroy(buffer: StdinBuffer) -> StdinBuffer: clear(buffer)

def kittyDigits(text: String,+value: U32,+digits: Bool,+part: U32,+first: U32) -> Maybe<&2,U32>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{117},SNil{}}:
      Bool.pick(Maybe<&2,U32>,(digits || U32.is_eq(part,1)) && U32.is_ge(Bool.pick(U32,U32.is_eq(part,0),value,first),32),Some{Bool.pick(U32,U32.is_eq(part,0),value,first)},None{})
    case SCon{Chr{58},rest}:
      +rest = {rest: String}
      Bool.pick(Unit -> Maybe<&2,U32>,U32.is_lt(part,2) && (digits || U32.is_eq(part,1)),_ => kittyDigits(rest,0,False{},(part + 1 : U32),Bool.pick(U32,U32.is_eq(part,0),value,first)),_ => None{})(Unit{})
    case SCon{char,rest}:
      +char = {char: Char}
      +rest = {rest: String}
      Bool.pick(Unit -> Maybe<&2,U32>,Char.is_digit(char) && U32.is_le(value,111411),_ => kittyDigits(rest,(value * 10 + Char.to_u32(char) - 48 : U32),True{},part,first),_ => None{})(Unit{})

def printable(sequence: String) -> Maybe<&2,U32>:
  match sequence:
    case SCon{Chr{27},SCon{Chr{91},rest}}: kittyDigits(rest,0,False{},0,0)
    case _: None{}

def duplicate(sequence: String,pending: Maybe<&2,U32>) -> Bool:
  match sequence pending:
    case SCon{char,SNil{}} Some{value}: U32.is_eq(Char.to_u32(char),value)
    case _ _: False{}

def emit(+sequence: String,+pending: Maybe<&2,U32>,+events: List<&2,InputEvent>) -> Transition:
  Bool.pick(Unit -> Transition,duplicate(sequence,pending),_ => Transition{create(),events},_ => Transition{StdinBuffer{Plain{},"",printable(sequence)},DataEvent{sequence} <> events})(Unit{})

def completed(reversed: String,pending: Maybe<&2,U32>,events: List<&2,InputEvent>) -> Transition:
  emit(String.reverse(reversed),pending,events)

def startsControl(text: String) -> Bool:
  match text:
    case SCon{Chr{91},_}: True{}
    case SCon{Chr{93},_}: True{}
    case SCon{Chr{79},_}: True{}
    case SCon{Chr{80},_}: True{}
    case SCon{Chr{95},_}: True{}
    case _: False{}

def pasteCharacter(index: U32) -> Char:
  match index:
    case 0: Chr{27}
    case 1: '['
    case 2: '2'
    case 3: '0'
    case 4: '1'
    case _: '~'

def pasteStep(+char: Char,+matched: U32,+reversed: String,+events: List<&2,InputEvent>) -> Transition:
  +next = Bool.pick(U32,Char.is_eq(char,pasteCharacter(matched)),(matched + 1 : U32),Bool.pick(U32,Char.is_eq(char,Chr{27}),1,0))
  +text = {SCon{char,reversed}: String}
  Bool.pick(Unit -> Transition,U32.is_eq(next,6),_ => Transition{create(),PasteEvent{String.reverse(String.drop(text,6n))} <> events},_ => Transition{StdinBuffer{Pasting{next},text,None{}},events})(Unit{})

def csiEnd(+reversed: String,+pending: Maybe<&2,U32>,+events: List<&2,InputEvent>) -> Transition:
  Bool.pick(Unit -> Transition,String.eq(reversed,"~002[\u{1b}"),_ => Transition{StdinBuffer{Pasting{0},"",None{}},events},_ => completed(reversed,pending,events))(Unit{})

def escapeStep(char: Char,+following: String,+reversed: String,+pending: Maybe<&2,U32>,+events: List<&2,InputEvent>) -> Transition:
  match char:
    case Chr{91}: Transition{StdinBuffer{Csi{True{}},SCon{'[',reversed},pending},events}
    case Chr{93}: Transition{StdinBuffer{Control{True{},False{}},SCon{']',reversed},pending},events}
    case Chr{80}: Transition{StdinBuffer{Control{False{},False{}},SCon{'P',reversed},pending},events}
    case Chr{95}: Transition{StdinBuffer{Control{False{},False{}},SCon{'_',reversed},pending},events}
    case Chr{79}: Transition{StdinBuffer{Ss3{},SCon{'O',reversed},pending},events}
    case Chr{27}: Bool.pick(Unit -> Transition,startsControl(following),_ => Transition{StdinBuffer{Escape{},"\u{1b}",None{}},DataEvent{"\u{1b}"} <> events},_ => completed(SCon{Chr{27},reversed},pending,events))(Unit{})
    case char: completed(SCon{char,reversed},pending,events)

def csiStep(+char: Char,+first: Bool,+reversed: String,+pending: Maybe<&2,U32>,+events: List<&2,InputEvent>) -> Transition:
  +text = {SCon{char,reversed}: String}
  +ordinary = Bool.pick(Unit -> Transition,U32.is_ge(Char.to_u32(char),64) && U32.is_le(Char.to_u32(char),126),_ => csiEnd(text,pending,events),_ => Transition{StdinBuffer{Csi{False{}},text,pending},events})(Unit{})
  Bool.pick(Unit -> Transition,first && Char.is_eq(char,'M'),_ => Transition{StdinBuffer{X10{3},text,pending},events},_ => Bool.pick(Unit -> Transition,first && Char.is_eq(char,'<'),_ => Transition{StdinBuffer{SgrMouse{0,False{},True{}},text,pending},events},_ => ordinary)(Unit{}))(Unit{})

def mouseStep(+char: Char,+fields: U32,+digits: Bool,+valid: Bool,+reversed: String,+pending: Maybe<&2,U32>,+events: List<&2,InputEvent>) -> Transition:
  +separator = Char.is_eq(char,';')
  +digit = Char.is_digit(char)
  +text = {SCon{char,reversed}: String}
  +next = {SgrMouse{Bool.pick(U32,separator,U32.min((fields + 1 : U32),3),fields),digit,valid && (digit || (separator && digits && U32.is_lt(fields,2)))}: Phase}
  Bool.pick(Unit -> Transition,valid && digits && U32.is_eq(fields,2) && (Char.is_eq(char,'M') || Char.is_eq(char,'m')),_ => completed(text,pending,events),_ => Transition{StdinBuffer{next,text,pending},events})(Unit{})

def step(+char: Char,following: String,state: StdinBuffer,+events: List<&2,InputEvent>) -> Transition:
  match state:
    case StdinBuffer{Plain{},_,+pending}: Bool.pick(Unit -> Transition,Char.is_eq(char,Chr{27}),_ => Transition{StdinBuffer{Escape{},"\u{1b}",pending},events},_ => emit(SCon{char,""},pending,events))(Unit{})
    case StdinBuffer{Escape{},reversed,pending}: escapeStep(char,following,reversed,pending,events)
    case StdinBuffer{Csi{first},reversed,pending}: csiStep(char,first,reversed,pending,events)
    case StdinBuffer{SgrMouse{fields,digits,valid},reversed,pending}: mouseStep(char,fields,digits,valid,reversed,pending,events)
    case StdinBuffer{X10{+left},+reversed,+pending}: Bool.pick(Unit -> Transition,U32.is_eq(left,1),_ => completed(SCon{char,reversed},pending,events),_ => Transition{StdinBuffer{X10{(left - 1 : U32)},SCon{char,reversed},pending},events})(Unit{})
    case StdinBuffer{Ss3{},reversed,pending}: completed(SCon{char,reversed},pending,events)
    case StdinBuffer{Control{+bell,escaped},+reversed,+pending}: Bool.pick(Unit -> Transition,(escaped && Char.is_eq(char,'\\')) || (bell && Char.is_eq(char,Chr{7})),_ => completed(SCon{char,reversed},pending,events),_ => Transition{StdinBuffer{Control{bell,Char.is_eq(char,Chr{27})},SCon{char,reversed},pending},events})(Unit{})
    case StdinBuffer{Pasting{matched},reversed,_}: pasteStep(char,matched,reversed,events)

def consume(text: String,transition: Transition) -> Transition:
  match text transition:
    case SNil{} Transition{buffer,events}: Transition{buffer,List.reverse(&2,InputEvent,events)}
    case SCon{char,+rest} Transition{buffer,events}: consume(rest,step(char,rest,buffer,events))

def process(text: String,buffer: StdinBuffer) -> Transition:
  match text buffer:
    case SNil{} StdinBuffer{Plain{},_,pending}: emit("",pending,Nil{})
    case text buffer: consume(text,Transition{buffer,Nil{}})

def getBuffer(buffer: StdinBuffer) -> String:
  match buffer:
    case StdinBuffer{Pasting{_},_,_}: ""
    case StdinBuffer{_,reversed,_}: String.reverse(reversed)

def flush(buffer: StdinBuffer) -> Transition:
  match buffer:
    case StdinBuffer{Pasting{matched},reversed,pending}: Transition{StdinBuffer{Pasting{matched},reversed,pending},Nil{}}
    case StdinBuffer{Plain{},_,pending}: Transition{StdinBuffer{Plain{},"",pending},Nil{}}
    case StdinBuffer{_,reversed,_}: Transition{create(),[DataEvent{String.reverse(reversed)}]}

def pendingTimeout(buffer: StdinBuffer,options: StdinBufferOptions) -> Maybe<&2,U32>:
  match buffer options:
    case StdinBuffer{Plain{},_,_} _: None{}
    case StdinBuffer{Pasting{_},_,_} _: None{}
    case StdinBuffer{Escape{},_,_} StdinBufferOptions{_,escapeTimeout}: Some{escapeTimeout}
    case _ StdinBufferOptions{timeout,_}: Some{timeout}

# One publisher sequences listener calls outside the parser lock. A process
# operation commits input before returning; listener delivery is asynchronous.
# The callback remains caller-owned until disposeAsync has joined the worker.
type AsyncState is Data:
  AsyncState{buffer: StdinBuffer, options: StdinBufferOptions, reversedEvents: List<&2,InputEvent>, deadline: Maybe<&2,Nat>, accepting: Bool, wake: Deferred.Deferred<Unit>, timer: Maybe<&2,TimerCancel>}
type AsyncHandle is Data: AsyncHandle{resource: Serial.Handle<AsyncState>}
type AsyncOwner is Type: AsyncOwner{resource: Serial.Owner<AsyncState>, worker: Chan(Unit)}
type AsyncStep is Type:
  Publish{events: List<&2,InputEvent>}
  AwaitInput{wake: Deferred.Deferred<Unit>}
  AwaitTimeout{timer: Timer}
  Stopped{}

def cancelAsyncTimer(timer: Maybe<&2,TimerCancel>) -> IO(Unit):
  match timer:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}:
      do IO<Unit>:
        cancelled : Bool <- Timer.cancel(handle)
        return Unit{}

def inputDeadline(now: Nat, timeout: Maybe<&2,U32>) -> Maybe<&2,Nat>:
  match timeout:
    case None{}: None{}
    case Some{delay}: Some{now + U32.to_nat(delay)}

def inputCommitted(now: Nat, transition: Transition, +options: StdinBufferOptions, pending: List<&2,InputEvent>, wake: Deferred.Deferred<Unit>) -> AsyncState:
  match transition:
    case Transition{+buffer,events}:
      AsyncState{buffer,options,List.reverse.go(&2,InputEvent,events,pending),inputDeadline(now,pendingTimeout(buffer,options)),True{},wake,None{}}

def processLocked(text: String, state: AsyncState) -> IO(AsyncState & Bool):
  match state:
    case AsyncState{buffer,+options,pending,_,True{},+wake,timer}:
      do IO<AsyncState & Bool>:
        cancelAsyncTimer(timer)
        now : Nat <- IO.now()
        settled : Bool <- Deferred.resolve(Unit,wake,Unit{})
        return (inputCommitted(now,process(text,buffer),options,pending,wake),True{})
    case state: IO.pure(AsyncState & Bool,(state,False{}))

def processAsync(handle: AsyncHandle, text: String) -> IO(Bool):
  match handle:
    case AsyncHandle{resource}: Serial.run(AsyncState,Bool,resource,state => processLocked(text,state))

def bufferLocked(+state: AsyncState) -> IO(AsyncState & String):
  match state:
    case AsyncState{buffer,_,_,_,_,_,_}: IO.pure(AsyncState & String,(state,getBuffer(buffer)))

def getBufferAsync(handle: AsyncHandle) -> IO(String):
  match handle:
    case AsyncHandle{resource}: Serial.run(AsyncState,String,resource,state => bufferLocked(state))

def flushedState(transition: Transition, +options: StdinBufferOptions, pending: List<&2,InputEvent>, accepting: Bool, wake: Deferred.Deferred<Unit>) -> AsyncState & List<&2,InputEvent>:
  match transition:
    case Transition{buffer,events}: (AsyncState{buffer,options,pending,None{},accepting,wake,None{}},events)

# Like the source method, explicit flush returns input without publishing it.
def flushLocked(state: AsyncState) -> IO(AsyncState & List<&2,InputEvent>):
  match state:
    case AsyncState{buffer,options,pending,_,accepting,+wake,timer}:
      do IO<AsyncState & List<&2,InputEvent>>:
        cancelAsyncTimer(timer)
        settled : Bool <- Deferred.resolve(Unit,wake,Unit{})
        return flushedState(flush(buffer),options,pending,accepting,wake)

def flushAsync(handle: AsyncHandle) -> IO(List<&2,InputEvent>):
  match handle:
    case AsyncHandle{resource}: Serial.run(AsyncState,List<&2,InputEvent>,resource,flushLocked)

def clearLocked(+stop: Bool, state: AsyncState) -> IO(AsyncState & Unit):
  match state:
    case AsyncState{_,options,pending,_,accepting,+wake,timer}:
      do IO<AsyncState & Unit>:
        cancelAsyncTimer(timer)
        settled : Bool <- Deferred.resolve(Unit,wake,Unit{})
        return (AsyncState{create(),options,Bool.pick(List<&2,InputEvent>,stop,Nil{},pending),None{},accepting && Bool.not(stop),wake,None{}},Unit{})

def clearAsync(handle: AsyncHandle) -> IO(Unit):
  match handle:
    case AsyncHandle{resource}: Serial.run(AsyncState,Unit,resource,state => clearLocked(False{},state))

def startedInputTimer(buffer: StdinBuffer, options: StdinBufferOptions, deadline: Maybe<&2,Nat>, wake: Deferred.Deferred<Unit>, timer: Timer & TimerCancel) -> AsyncState & AsyncStep:
  match timer:
    case (owner,cancel): (AsyncState{buffer,options,Nil{},deadline,True{},wake,Some{cancel}},AwaitTimeout{owner})

def timedOut(transition: Transition, options: StdinBufferOptions, wake: Deferred.Deferred<Unit>) -> AsyncState & AsyncStep:
  match transition:
    case Transition{buffer,events}: (AsyncState{buffer,options,Nil{},None{},True{},wake,None{}},Publish{events})

def scheduleInput(+now: Nat, +buffer: StdinBuffer, +options: StdinBufferOptions, deadline: Maybe<&2,Nat>, +wake: Deferred.Deferred<Unit>) -> IO(AsyncState & AsyncStep):
  match deadline:
    case None{}: IO.pure(AsyncState & AsyncStep,(AsyncState{buffer,options,Nil{},None{},True{},wake,None{}},AwaitInput{wake}))
    case Some{+at}:
      Bool.pick(Unit -> IO(AsyncState & AsyncStep),Nat.is_le(at,now),
        _ => IO.pure(AsyncState & AsyncStep,timedOut(flush(buffer),options,wake)),
        _ => do IO<AsyncState & AsyncStep>:
          timer : Timer & TimerCancel <- Timer.new(U32.from_nat(at - now))
          return startedInputTimer(buffer,options,Some{at},wake,timer))(Unit{})

def chooseStep(now: Nat, state: AsyncState) -> IO(AsyncState & AsyncStep):
  match state:
    case AsyncState{buffer,options,Nil{},deadline,True{},wake,_}: scheduleInput(now,buffer,options,deadline,wake)
    case AsyncState{buffer,options,events,deadline,True{},wake,_}: IO.pure(AsyncState & AsyncStep,(AsyncState{buffer,options,Nil{},deadline,True{},wake,None{}},Publish{List.reverse(&2,InputEvent,events)}))
    case state: IO.pure(AsyncState & AsyncStep,(state,Stopped{}))

# There is no live observation when the worker replaces its wake. Producers
# settle the wake under this same lock, so they cannot touch a retired signal.
def nextStep(state: AsyncState) -> IO(AsyncState & AsyncStep):
  match state:
    case AsyncState{buffer,options,events,deadline,accepting,old,_}:
      do IO<AsyncState & AsyncStep>:
        Deferred.dispose(Unit,old)
        wake : Deferred.Deferred<Unit> <- Deferred.new(Unit)
        now : Nat <- IO.now()
        chooseStep(now,AsyncState{buffer,options,events,deadline,accepting,wake,None{}})

def closeInputTimer(pair: Timer & Bool) -> IO(Unit):
  match pair:
    case (owner,_): Timer.close(owner)

def deliverEvents(+observer: Callback.Callback<InputEvent,Unit>, events: List<&2,InputEvent>) -> IO(Unit):
  match events:
    case Nil{}: IO.pure(Unit,Unit{})
    case event <> rest:
      do IO<Unit>:
        Callback.call(InputEvent,Unit,observer,event)
        deliverEvents(observer,rest)

def performStep(observer: Callback.Callback<InputEvent,Unit>, step: AsyncStep) -> IO(Bool):
  match step:
    case Stopped{}: IO.pure(Bool,False{})
    case Publish{events}:
      do IO<Bool>:
        deliverEvents(observer,events)
        return True{}
    case AwaitInput{wake}:
      do IO<Bool>:
        ready : Unit <- Deferred.result(Unit,wake)
        return True{}
    case AwaitTimeout{owner}:
      do IO<Bool>:
        result : Timer & Bool <- Timer.wait(owner)
        closeInputTimer(result)
        return True{}

# External input/disposal drives this persistent loop; timers are closed before
# revisiting state. A timeout only flushes the current deadline under the lock.
@unsafe def inputWorker(+resource: Serial.Handle<AsyncState>, +observer: Callback.Callback<InputEvent,Unit>, continue: Bool) -> IO(Unit):
  match continue:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      do IO<Unit>:
        step : AsyncStep <- Serial.run(AsyncState,AsyncStep,resource,nextStep)
        again : Bool <- performStep(observer,step)
        inputWorker(resource,observer,again)

def startInputWorker(observer: Callback.Callback<InputEvent,Unit>, pair: Serial.Owner<AsyncState> & Serial.Handle<AsyncState>) -> IO(AsyncOwner):
  match pair:
    case (owner,handle):
      do IO<AsyncOwner>:
        worker : Chan(Unit) <- IO.fork(Unit,inputWorker(handle,observer,True{}))
        return AsyncOwner{owner,worker}

def createAsync(options: StdinBufferOptions, observer: Callback.Callback<InputEvent,Unit>) -> IO(AsyncOwner):
  do IO<AsyncOwner>:
    wake : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    owner : Serial.Owner<AsyncState> <- Serial.create(AsyncState,AsyncState{create(),options,Nil{},None{},True{},wake,None{}})
    startInputWorker(observer,Serial.borrow(AsyncState,owner))

def borrowedInput(worker: Chan(Unit), pair: Serial.Owner<AsyncState> & Serial.Handle<AsyncState>) -> AsyncOwner & AsyncHandle:
  match pair:
    case (owner,handle): (AsyncOwner{owner,worker},AsyncHandle{handle})

def borrowAsync(owner: AsyncOwner) -> AsyncOwner & AsyncHandle:
  match owner:
    case AsyncOwner{resource,worker}: borrowedInput(worker,Serial.borrow(AsyncState,resource))

def retireWake(state: AsyncState) -> IO(Unit):
  match state:
    case AsyncState{_,_,_,_,_,wake,_}: Deferred.dispose(Unit,wake)

def disposeInput(worker: Chan(Unit), pair: Serial.Owner<AsyncState> & Serial.Handle<AsyncState>) -> IO(Unit):
  match pair:
    case (owner,handle):
      do IO<Unit>:
        Serial.run(AsyncState,Unit,handle,state => clearLocked(True{},state))
        joined : Unit <- IO.join(Unit,worker)
        state : AsyncState <- Serial.retire(AsyncState,owner)
        retireWake(state)

# Join input producers first; borrowed handles expire on return. Listener calls
# already in progress finish before disposal returns. Do not dispose from the
# listener itself: it would join its own worker. Use clearAsync for reentry.
def disposeAsync(owner: AsyncOwner) -> IO(Unit):
  match owner:
    case AsyncOwner{resource,worker}: disposeInput(worker,Serial.borrow(AsyncState,resource))

import Base
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/deferred.bend as Deferred
import ../../runtime/src/serial-resource.bend as Serial
import ../../runtime/src/utf8.bend as UTF8
import ../../runtime/src/string.bend as Strings
import ../../runtime/src/posix-path.bend as Path
import ./stdin-buffer.bend as Input

type KeyboardProtocolNegotiationSequence is Data:
  KittyFlags{flags: U32}
  DeviceAttributes{}

def negotiationDigits(text: String, +value: U32, digits: Bool, separated: Bool) -> Maybe<&2,KeyboardProtocolNegotiationSequence>:
  match text:
    case SCon{'u',SNil{}}: Bool.pick(Maybe<&2,KeyboardProtocolNegotiationSequence>,digits && Bool.not(separated),Some{KittyFlags{value}},None{})
    case SCon{'c',SNil{}}: Some{DeviceAttributes{}}
    case SCon{';',rest}: negotiationDigits(rest,0,False{},True{})
    case SCon{char,rest}:
      +char = {char: Char}
      +rest = {rest: String}
      Bool.pick(Unit -> Maybe<&2,KeyboardProtocolNegotiationSequence>,Char.is_digit(char) && (U32.is_lt(value,429496729) || (U32.is_eq(value,429496729) && U32.is_le(Char.to_u32(char),53))),
        _ => negotiationDigits(rest,(value * 10 + Char.to_u32(char) - 48 : U32),True{},separated),_ => None{})(Unit{})
    case _: None{}

def parseKeyboardProtocolNegotiationSequence(sequence: String) -> Maybe<&2,KeyboardProtocolNegotiationSequence>:
  match sequence:
    case SCon{Chr{27},SCon{'[',SCon{'?',rest}}}: negotiationDigits(rest,0,False{},False{})
    case _: None{}

def prefixDigits(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{';',rest}: prefixDigits(rest)
    case SCon{char,rest}: Bool.pick(Unit -> Bool,Char.is_digit(char),_ => prefixDigits(rest),_ => False{})(Unit{})

def isKeyboardProtocolNegotiationSequencePrefix(sequence: String) -> Bool:
  match sequence:
    case SCon{Chr{27},SCon{'[',SNil{}}}: True{}
    case SCon{Chr{27},SCon{'[',SCon{'?',rest}}}: prefixDigits(rest)
    case _: False{}

def normalizeNativeShiftEnterInput(+data: String, detect: Bool, shift: Bool) -> String:
  Bool.pick(String,detect && shift && Strings.equal(data,"\r"),"\u{1b}[13;2u",data)
def normalizeAppleTerminalInput(data: String, apple: Bool, shift: Bool) -> String:
  normalizeNativeShiftEnterInput(data,apple,shift)

def escapeTimeoutDigits(text: String,+value: U32,seen: Bool) -> Maybe<&2,U32>:
  match text:
    case SNil{}: Bool.pick(Maybe<&2,U32>,seen && U32.is_gt(value,0),Some{value},None{})
    case SCon{char,rest}:
      +char = {char: Char}
      +rest = {rest: String}
      Bool.pick(Unit -> Maybe<&2,U32>,Char.is_digit(char) && (U32.is_lt(value,429496729) || (U32.is_eq(value,429496729) && U32.is_le(Char.to_u32(char),53))),
        _ => escapeTimeoutDigits(rest,(value * 10 + Char.to_u32(char) - 48 : U32),True{}),_ => None{})(Unit{})

def resolveEscapeTimeoutMs(configured: String, sshConnection: String, sshTty: String) -> U32:
  Maybe.default(&2,U32,escapeTimeoutDigits(configured,0,False{}),Bool.pick(U32,Bool.not(Strings.equal(sshConnection,"") && Strings.equal(sshTty,"")),100,10))

def kittyQuery() -> String: "\u{1b}[>7u\u{1b}[?u\u{1b}[c"
def progressSequence(active: Bool) -> String:
  Bool.pick(String,active,"\u{1b}]9;4;3\u{7}","\u{1b}]9;4;0\u{7}")

type Negotiation is Data:
  Negotiation{kitty: Bool, modifyOtherKeys: Bool, pushed: Bool, pending: String, deadline: Maybe<&2,Nat>}
type ProtocolTransition is Data:
  ProtocolTransition{state: Negotiation, input: List<&2,String>, output: String}

def initialNegotiation() -> Negotiation: Negotiation{False{},False{},True{},"",None{}}

def negotiated(value: KeyboardProtocolNegotiationSequence, state: Negotiation) -> ProtocolTransition:
  match value state:
    case KittyFlags{0} Negotiation{+kitty,+modify,pushed,_,_}:
      ProtocolTransition{Negotiation{kitty,modify || Bool.not(kitty),pushed,"",None{}},Nil{},Bool.pick(String,kitty || modify,"","\u{1b}[>4;2m")}
    case KittyFlags{_} Negotiation{_,modify,pushed,_,_}:
      ProtocolTransition{Negotiation{True{},False{},pushed,"",None{}},Nil{},Bool.pick(String,modify,"\u{1b}[>4;0m","")}
    case DeviceAttributes{} Negotiation{+kitty,+modify,pushed,_,_}:
      ProtocolTransition{Negotiation{kitty,modify || Bool.not(kitty),pushed,"",None{}},Nil{},Bool.pick(String,kitty || modify,"","\u{1b}[>4;2m")}

# Fragments that outlive normal sequence framing have a separate 150ms window.
def protocolFresh(+now: Nat,+sequence: String,state: Negotiation, parsed: Maybe<&2,KeyboardProtocolNegotiationSequence>) -> ProtocolTransition:
  match state parsed:
    case state Some{value}: negotiated(value,state)
    case Negotiation{+kitty,+modify,+pushed,_,_} None{}:
      Bool.pick(ProtocolTransition,isKeyboardProtocolNegotiationSequencePrefix(sequence),
        ProtocolTransition{Negotiation{kitty,modify,pushed,sequence,Some{now + 150n}},Nil{},""},
        ProtocolTransition{Negotiation{kitty,modify,pushed,"",None{}},sequence <> Nil{},""})

def replayPrefix(prefix: String,transition: ProtocolTransition) -> ProtocolTransition:
  match transition:
    case ProtocolTransition{state,input,output}: ProtocolTransition{state,prefix <> input,output}

def protocolCombined(+now: Nat,+sequence: String,+combined: String,state: Negotiation, parsed: Maybe<&2,KeyboardProtocolNegotiationSequence>) -> ProtocolTransition:
  match state parsed:
    case state Some{value}: negotiated(value,state)
    case Negotiation{+kitty,+modify,+pushed,pending,_} None{}:
      Bool.pick(Unit -> ProtocolTransition,isKeyboardProtocolNegotiationSequencePrefix(combined),
        _ => ProtocolTransition{Negotiation{kitty,modify,pushed,combined,Some{now + 150n}},Nil{},""},
        _ => replayPrefix(pending,protocolFresh(now,sequence,Negotiation{kitty,modify,pushed,"",None{}},parseKeyboardProtocolNegotiationSequence(sequence))))(Unit{})

def protocolInput(+now: Nat,+sequence: String,state: Negotiation) -> ProtocolTransition:
  match state:
    case Negotiation{kitty,modify,pushed,SNil{},deadline}:
      protocolFresh(now,sequence,Negotiation{kitty,modify,pushed,"",deadline},parseKeyboardProtocolNegotiationSequence(sequence))
    case Negotiation{kitty,modify,pushed,+pending,deadline}:
      +combined = pending ++ sequence
      protocolCombined(now,sequence,combined,Negotiation{kitty,modify,pushed,pending,deadline},parseKeyboardProtocolNegotiationSequence(combined))

def protocolTimeout(now: Nat,state: Negotiation) -> ProtocolTransition:
  match state:
    case Negotiation{+kitty,+modify,+pushed,+pending,Some{+deadline}}:
      Bool.pick(ProtocolTransition,Nat.is_ge(now,deadline),ProtocolTransition{Negotiation{kitty,modify,pushed,"",None{}},pending <> Nil{},""},ProtocolTransition{Negotiation{kitty,modify,pushed,pending,Some{deadline}},Nil{},""})
    case state: ProtocolTransition{state,Nil{},""}

def disableKeyboard(state: Negotiation) -> ProtocolTransition:
  match state:
    case Negotiation{kitty,modify,pushed,_,_}:
      ProtocolTransition{Negotiation{False{},False{},False{},"",None{}},Nil{},Bool.pick(String,kitty || pushed,"\u{1b}[<u","") ++ Bool.pick(String,modify,"\u{1b}[>4;0m","")}

type Error is Data:
  System{operation: String, code: U32, message: String}
  InvalidInput{cause: UTF8.Error}
  Closed{}
  Cleanup{errors: List<&2,Error>}
type Dimensions is Data: Dimensions{columns: U32, rows: U32}
type Options is Data:
  Options{input: U32, output: U32, escapeTimeout: U32, fallback: Dimensions, writeLogPath: Maybe<&2,String>}
def defaultOptions() -> Options: Options{0,1,10,Dimensions{80,24},None{}}
type Delivery is Data: Delivery{input: List<&2,String>, output: String}
type State is Data:
  State{protocol: Negotiation, progress: Maybe<&2,Nat>, draining: Bool, active: Bool, lastData: Nat, dimensions: Dimensions, errors: List<&2,Error>, wake: Deferred.Deferred<Unit>, timer: Maybe<&2,TimerCancel>, pending: List<&2,Delivery>}
type Output is Type: Output{pipe: Pipe, failure: Maybe<&2,Error>, log: Maybe<&2,String>}
type Handle is Data:
  Handle{state: Serial.Handle<State>, output: Serial.Handle<Output>, inputCancel: PipeCancel, outputCancel: PipeCancel, resizeCancel: PipeCancel}
type Listeners is Data:
  Listeners{handle: Handle, input: Callback.Callback<String,Unit>, resize: Callback.Callback<Unit,Unit>, settled: Callback.Callback<Unit,Unit>}
type ProcessTerminal is Type:
  ProcessTerminal{lease: TerminalLease, state: Serial.Owner<State>, output: Serial.Owner<Output>, handle: Handle, buffer: Input.AsyncOwner, observer: Callback.Callback<Input.InputEvent,Unit>, reader: Chan(Pipe), resizer: Chan(Pipe), clock: Chan(Unit)}

def osError(operation: String,result: Result<&1,&1,U32 & String,Unit>) -> Maybe<&2,Error>:
  match result:
    case Done{Unit{}}: None{}
    case Fail{(code,message)}: Some{System{operation,code,message}}
def errorResult(error: Maybe<&2,Error>) -> Result<&2,&2,Error,Unit>:
  match error:
    case None{}: Done{Unit{}}
    case Some{cause}: Fail{cause}

def written(+log: Maybe<&2,String>,bytes: List<&2,U32>,result: Pipe & Result<&1,&1,U32 & String,U32>) -> Output & Maybe<&2,List<&2,U32>>:
  match result:
    case (pipe,Done{+count}):
      Bool.pick(Pipe -> Output & Maybe<&2,List<&2,U32>>,U32.is_eq(count,0),
        pipe => (Output{pipe,Some{System{"write",5,"write made no progress"}},log},None{}),
        pipe => (Output{pipe,None{},log},Some{List.drop(&2,U32,bytes,U32.to_nat(count))})) (pipe)
    case (pipe,Fail{(code,message)}): (Output{pipe,Some{System{"write",code,message}},log},None{})

@unsafe def writeBytes(state: Output & Maybe<&2,List<&2,U32>>) -> IO(Output):
  match state:
    case (output,None{}): IO.pure(Output,output)
    case (output,Some{Nil{}}): IO.pure(Output,output)
    case (Output{pipe,Some{error},log},_): IO.pure(Output,Output{pipe,Some{error},log})
    case (Output{pipe,None{},log},Some{+bytes}):
      do IO<Output>:
        result : Pipe & Result<&1,&1,U32 & String,U32> <- Pipe.write(pipe,List.take(&2,U32,bytes,65536n))
        writeBytes(written(log,bytes,result))

def outputResult(output: Output) -> Output & Result<&2,&2,Error,Unit>:
  match output:
    case Output{pipe,+failure,log}: (Output{pipe,failure,log},errorResult(failure))
def writeLocked(text: String,output: Output) -> IO(Output & Result<&2,&2,Error,Unit>):
  do IO<Output & Result<&2,&2,Error,Unit>>:
    written : Output <- writeBytes((output,Some{UTF8.encode(text)}))
    return outputResult(written)
def writeRaw(handle: Handle,text: String) -> IO(Result<&2,&2,Error,Unit>):
  match handle:
    case Handle{_,output,_,_,_}: Serial.run(Output,Result<&2,&2,Error,Unit>,output,state => writeLocked(text,state))

def stateError(cause: Error,state: State) -> IO(State & Unit):
  match state:
    case State{protocol,progress,draining,active,lastData,dimensions,errors,wake,timer,pending}:
      IO.pure(State & Unit,(State{protocol,progress,draining,active,lastData,dimensions,cause <> errors,wake,timer,pending},Unit{}))
def remember(handle: Handle,error: Maybe<&2,Error>) -> IO(Unit):
  match handle error:
    case _ None{}: IO.pure(Unit,Unit{})
    case Handle{state,_,_,_,_} Some{cause}: Serial.run(State,Unit,state,current => stateError(cause,current))
def rememberedWrite(handle: Handle,result: Result<&2,&2,Error,Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.pure(Unit,Unit{})
    case Fail{error}: remember(handle,Some{error})

def inputCallbacks(+observer: Callback.Callback<String,Unit>, events: List<&2,String>) -> IO(Unit):
  match events:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        Callback.call(String,Unit,observer,value)
        inputCallbacks(observer,rest)
def deliver(listeners: Listeners,delivery: Delivery) -> IO(Unit):
  match listeners delivery:
    case Listeners{_,input,_,_} Delivery{events,SNil{}}: inputCallbacks(input,events)
    case Listeners{+handle,input,_,_} Delivery{events,text}:
      do IO<Unit>:
        result : Result<&2,&2,Error,Unit> <- writeRaw(handle,text)
        rememberedWrite(handle,result)
        inputCallbacks(input,events)

def applyProtocol(transition: ProtocolTransition,state: State) -> State & Delivery:
  match transition state:
    case ProtocolTransition{protocol,input,output} State{_,+progress,+draining,+active,lastData,dimensions,errors,wake,timer,pending}:
      (State{protocol,progress,draining,active,lastData,dimensions,errors,wake,timer,pending},Delivery{Bool.pick(List<&2,String>,active && Bool.not(draining),input,Nil{}),output})
def framing(now: Nat,event: Input.InputEvent,protocol: Negotiation) -> ProtocolTransition:
  match event:
    case Input.DataEvent{text}: protocolInput(now,text,protocol)
    case Input.PasteEvent{text}: ProtocolTransition{protocol,("\u{1b}[200~" ++ text ++ "\u{1b}[201~") <> Nil{},""}
def queuedDelivery(result: State & Delivery) -> State & Unit:
  match result:
    case (State{protocol,progress,draining,active,lastData,dimensions,errors,wake,timer,pending},delivery):
      (State{protocol,progress,draining,active,lastData,dimensions,errors,wake,timer,delivery <> pending},Unit{})
def frameLocked(now: Nat,event: Input.InputEvent,+state: State) -> IO(State & Unit):
  match state:
    case State{protocol,_,_,True{},_,_,_,wake,timer,_}:
      do IO<State & Unit>:
        Input.cancelAsyncTimer(timer)
        settled : Bool <- Deferred.resolve(Unit,wake,Unit{})
        return queuedDelivery(applyProtocol(framing(now,event,protocol),state))
    case _: IO.pure(State & Unit,(state,Unit{}))
def onFrame(listeners: Listeners,event: Input.InputEvent) -> IO(Unit):
  match listeners:
    case Listeners{Handle{state,_,_,_,_},_,_,_}:
      do IO<Unit>:
        now : Nat <- IO.now()
        Serial.run(State,Unit,state,current => frameLocked(now,event,current))

def byteActivity(now: Nat,state: State) -> IO(State & Unit):
  match state:
    case State{protocol,progress,draining,active,_,dimensions,errors,wake,timer,pending}:
      IO.pure(State & Unit,(State{protocol,progress,draining,active,now,dimensions,errors,wake,timer,pending},Unit{}))
def markInput(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{state,_,_,_,_}:
      do IO<Unit>:
        now : Nat <- IO.now()
        Serial.run(State,Unit,state,current => byteActivity(now,current))
def decodedInput(handle: Handle,result: Result<&2,&2,UTF8.Error,Bool>) -> IO(Bool):
  match result:
    case Done{accepted}: IO.pure(Bool,accepted)
    case Fail{cause}:
      do IO<Bool>:
        remember(handle,Some{InvalidInput{cause}})
        return False{}

def readStep(+handle: Handle,buffer: Input.AsyncHandle, result: Pipe & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Pipe & Bool):
  match result:
    case (pipe,Done{Nil{}}):
      do IO<Pipe & Bool>:
        result : Result<&2,&2,UTF8.Error,Bool> <- Input.finishBytesAsync(buffer)
        valid : Bool <- decodedInput(handle,result)
        return (pipe,False{})
    case (pipe,Done{bytes}):
      do IO<Pipe & Bool>:
        markInput(handle)
        result : Result<&2,&2,UTF8.Error,Bool> <- Input.processBytesAsync(buffer,bytes)
        accepted : Bool <- decodedInput(handle,result)
        return (pipe,accepted)
    case (pipe,Fail{(125,_)}): IO.pure(Pipe & Bool,(pipe,False{}))
    case (pipe,Fail{(code,message)}):
      do IO<Pipe & Bool>:
        remember(handle,Some{System{"read",code,message}})
        return (pipe,False{})
@unsafe def inputReader(+handle: Handle,+buffer: Input.AsyncHandle,state: Pipe & Bool) -> IO(Pipe):
  match state:
    case (pipe,False{}): IO.pure(Pipe,pipe)
    case (pipe,True{}):
      do IO<Pipe>:
        result : Pipe & Result<&1,&1,U32 & String,List<&2,U32>> <- Pipe.read(pipe,65536)
        next : Pipe & Bool <- readStep(handle,buffer,result)
        inputReader(handle,buffer,next)

def minimumDeadline(a: Maybe<&2,Nat>,b: Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match a b:
    case None{} b: b
    case a None{}: a
    case Some{+x} Some{+y}: Some{Bool.pick(Nat,Nat.is_le(x,y),x,y)}
def protocolDeadline(protocol: Negotiation) -> Maybe<&2,Nat>:
  match protocol:
    case Negotiation{_,_,_,_,deadline}: deadline

def clockAdvanced(+now: Nat,transition: ProtocolTransition,state: State) -> State:
  match transition state:
    case ProtocolTransition{protocol,input,_} State{_,+progress,+draining,active,lastData,dimensions,errors,wake,timer,pending}:
      +due = Maybe.default(&2,Bool,Maybe.map(&2,Nat,Bool,at => Nat.is_ge(now,at),progress),False{})
      +delivery = {Delivery{Bool.pick(List<&2,String>,draining,Nil{},input),Bool.pick(String,due,progressSequence(True{}),"")}: Delivery}
      State{protocol,Bool.pick(Maybe<&2,Nat>,due,Some{now + 1000n},progress),draining,active,lastData,dimensions,errors,wake,timer,delivery <> pending}

type ClockStep is Type:
  Publish{events: List<&2,Delivery>}
  Sleep{timer: Timer}
  Wait{wake: Deferred.Deferred<Unit>}
  End{}
def timedClock(state: State,pair: Timer & TimerCancel) -> State & ClockStep:
  match state pair:
    case State{protocol,progress,draining,active,lastData,dimensions,errors,wake,_,pending} Tuple{owner,cancel}:
      (State{protocol,progress,draining,active,lastData,dimensions,errors,wake,Some{cancel},pending},Sleep{owner})
def waitClock(now: Nat,+state: State,deadline: Maybe<&2,Nat>) -> IO(State & ClockStep):
  match state deadline:
    case State{_,_,_,_,_,_,_,wake,_,_} None{}: IO.pure(State & ClockStep,(state,Wait{wake}))
    case _ Some{at}:
      do IO<State & ClockStep>:
        pair : Timer & TimerCancel <- Timer.new(U32.from_nat(at - now))
        return timedClock(state,pair)

def nonemptyDelivery(delivery: Delivery) -> Bool:
  match delivery:
    case Delivery{Nil{},SNil{}}: False{}
    case _: True{}
def usefulDeliveries(events: List<&2,Delivery>,+reversed: List<&2,Delivery>) -> List<&2,Delivery>:
  match events:
    case Nil{}: reversed
    case +head <> rest: usefulDeliveries(rest,Bool.pick(List<&2,Delivery>,nonemptyDelivery(head),head <> reversed,reversed))
def chooseClock(now: Nat,state: State,events: List<&2,Delivery>) -> IO(State & ClockStep):
  match state events:
    case State{+protocol,+progress,draining,True{},lastData,dimensions,errors,wake,timer,_} Nil{}:
      waitClock(now,State{protocol,progress,draining,True{},lastData,dimensions,errors,wake,timer,Nil{}},minimumDeadline(protocolDeadline(protocol),progress))
    case State{protocol,progress,draining,True{},lastData,dimensions,errors,wake,timer,_} events:
      IO.pure(State & ClockStep,(State{protocol,progress,draining,True{},lastData,dimensions,errors,wake,timer,Nil{}},Publish{events}))
    case state _: IO.pure(State & ClockStep,(state,End{}))
def advancedClock(now: Nat,+state: State) -> IO(State & ClockStep):
  match state:
    case State{_,_,_,_,_,_,_,_,_,events}: chooseClock(now,state,usefulDeliveries(events,Nil{}))
def nextClock(state: State) -> IO(State & ClockStep):
  match state:
    case State{+protocol,progress,draining,active,lastData,dimensions,errors,old,_,pending}:
      do IO<State & ClockStep>:
        Deferred.dispose(Unit,old)
        wake : Deferred.Deferred<Unit> <- Deferred.new(Unit)
        +now : Nat <- IO.now()
        advancedClock(now,clockAdvanced(now,protocolTimeout(now,protocol),State{protocol,progress,draining,active,lastData,dimensions,errors,wake,None{},pending}))
def deliveries(+listeners: Listeners,events: List<&2,Delivery>) -> IO(Unit):
  match events:
    case Nil{}: IO.pure(Unit,Unit{})
    case event <> rest:
      do IO<Unit>:
        deliver(listeners,event)
        deliveries(listeners,rest)
# All input framed from one read is published together; `settled` then runs,
# as Node runs nextTick callbacks after a stdin data handler returns.
def settle(listeners: Listeners) -> IO(Unit):
  match listeners:
    case Listeners{_,_,_,settled}: Callback.call(Unit,Unit,settled,Unit{})
def clockStep(+listeners: Listeners,step: ClockStep) -> IO(Bool):
  match step:
    case End{}: IO.pure(Bool,False{})
    case Publish{events}:
      do IO<Bool>:
        deliveries(listeners,events)
        settle(listeners)
        return True{}
    case Wait{wake}:
      do IO<Bool>:
        ready : Unit <- Deferred.result(Unit,wake)
        return True{}
    case Sleep{timer}:
      do IO<Bool>:
        result : Timer & Bool <- Timer.wait(timer)
        Input.closeInputTimer(result)
        return True{}
@unsafe def terminalClock(+listeners: Listeners,again: Bool) -> IO(Unit):
  match listeners again:
    case _ False{}: IO.pure(Unit,Unit{})
    case Listeners{Handle{state,_,_,_,_},_,_,_} True{}:
      do IO<Unit>:
        step : ClockStep <- Serial.run(State,ClockStep,state,nextClock)
        next : Bool <- clockStep(listeners,step)
        terminalClock(listeners,next)

def dimensionsResult(fallback: Dimensions,result: Result<&1,&1,U32 & String,U32 & U32>) -> Dimensions:
  match fallback result:
    case Dimensions{columns,rows} Done{(+width,+height)}:
      Dimensions{Bool.pick(U32,U32.is_gt(width,0),width,columns),Bool.pick(U32,U32.is_gt(height,0),height,rows)}
    case fallback _: fallback

def resizeLocked(+size: Dimensions,state: State) -> IO(State & Bool):
  match size state:
    case Dimensions{a,b} State{protocol,progress,draining,+active,lastData,Dimensions{c,d},errors,wake,timer,pending}:
      IO.pure(State & Bool,(State{protocol,progress,draining,active,lastData,size,errors,wake,timer,pending},active && Bool.not(U32.is_eq(a,c) && U32.is_eq(b,d))))
def readDimensions(+state: State) -> IO(State & Dimensions):
  match state:
    case State{_,_,_,_,_,size,_,_,_,_}: IO.pure(State & Dimensions,(state,size))
def getDimensions(handle: Handle) -> IO(Dimensions):
  match handle:
    case Handle{state,_,_,_,_}: Serial.run(State,Dimensions,state,value => readDimensions(value))
def notifyResize(listeners: Listeners) -> IO(Unit):
  match listeners:
    case Listeners{Handle{+state,_,_,outputCancel,_},_,resize,_}:
      do IO<Unit>:
        previous : Dimensions <- Serial.run(State,Dimensions,state,value => readDimensions(value))
        measured : Result<&1,&1,U32 & String,U32 & U32> <- Terminal.dimensions(outputCancel)
        changed : Bool <- Serial.run(State,Bool,state,value => resizeLocked(dimensionsResult(previous,measured),value))
        Bool.pick(Unit -> IO(Unit),changed,_ => Callback.call(Unit,Unit,resize,Unit{}),_ => IO.pure(Unit,Unit{}))(Unit{})
def resizeFailure(listeners: Listeners,error: Error) -> IO(Unit):
  match listeners:
    case Listeners{handle,_,_,_}: remember(handle,Some{error})
def resizeStep(+listeners: Listeners,result: Pipe & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Pipe & Bool):
  match result:
    case (pipe,Done{Nil{}}): IO.pure(Pipe & Bool,(pipe,False{}))
    case (pipe,Done{_}):
      do IO<Pipe & Bool>:
        notifyResize(listeners)
        return (pipe,True{})
    case (pipe,Fail{(125,_)}): IO.pure(Pipe & Bool,(pipe,False{}))
    case (pipe,Fail{(code,message)}):
      do IO<Pipe & Bool>:
        resizeFailure(listeners,System{"resize notification",code,message})
        return (pipe,False{})
@unsafe def resizeReader(+listeners: Listeners,state: Pipe & Bool) -> IO(Pipe):
  match state:
    case (pipe,False{}): IO.pure(Pipe,pipe)
    case (pipe,True{}):
      do IO<Pipe>:
        result : Pipe & Result<&1,&1,U32 & String,List<&2,U32>> <- Pipe.read(pipe,4096)
        next : Pipe & Bool <- resizeStep(listeners,result)
        resizeReader(listeners,next)

def wakeState(+state: State) -> IO(State & Unit):
  match state:
    case State{_,_,_,_,_,_,_,wake,timer,_}:
      do IO<State & Unit>:
        Input.cancelAsyncTimer(timer)
        settled : Bool <- Deferred.resolve(Unit,wake,Unit{})
        return (state,Unit{})
def progressLocked(+active: Bool,now: Nat,state: State) -> IO(State & Unit):
  match state:
    case State{protocol,progress,draining,True{},lastData,dimensions,errors,wake,timer,pending}:
      wakeState(State{protocol,Bool.pick(Maybe<&2,Nat>,active,Some{Maybe.default(&2,Nat,progress,now + 1000n)},None{}),draining,True{},lastData,dimensions,errors,wake,timer,pending})
    case state: IO.pure(State & Unit,(state,Unit{}))
def setProgress(+handle: Handle,+active: Bool) -> IO(Unit):
  match handle:
    case Handle{state,_,_,_,_}:
      do IO<Unit>:
        now : Nat <- IO.now()
        Serial.run(State,Unit,state,value => progressLocked(active,now,value))
        result : Result<&2,&2,Error,Unit> <- writeRaw(handle,progressSequence(active))
        rememberedWrite(handle,result)

def stoppedState(transition: ProtocolTransition,state: State) -> State & String:
  match transition state:
    case ProtocolTransition{protocol,_,output} State{_,progress,_,_,lastData,dimensions,errors,wake,timer,_}:
      (State{protocol,None{},False{},False{},lastData,dimensions,errors,wake,timer,Nil{}},Bool.pick(String,Maybe.is_some(&2,Nat,progress),progressSequence(False{}),"") ++ "\u{1b}[?2004l" ++ output)
def stopLocked(+state: State) -> IO(State & String):
  match state:
    case State{protocol,_,_,_,_,_,_,wake,timer,_}:
      do IO<State & String>:
        Input.cancelAsyncTimer(timer)
        settled : Bool <- Deferred.resolve(Unit,wake,Unit{})
        return stoppedState(disableKeyboard(protocol),state)
def cancel(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{state,_,input,output,resize}:
      do IO<Unit>:
        ignored : String <- Serial.run(State,String,state,value => stopLocked(value))
        a : Bool <- Pipe.cancel(input)
        b : Bool <- Pipe.cancel(output)
        c : Bool <- Pipe.cancel(resize)
        return Unit{}

def addError(error: Maybe<&2,Error>,errors: List<&2,Error>) -> List<&2,Error>:
  match error:
    case None{}: errors
    case Some{cause}: cause <> errors
def closeOutput(output: Output) -> IO(List<&2,Error>):
  match output:
    case Output{pipe,failure,log}:
      do IO<List<&2,Error>>:
        closed : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(pipe)
        return addError(osError("close output",closed),addError(failure,Nil{}))
def finalErrors(errors: List<&2,Error>) -> Result<&2,&2,Error,Unit>:
  match errors:
    case Nil{}: Done{Unit{}}
    case error <> Nil{}: Fail{error}
    case errors: Fail{Cleanup{List.reverse(&2,Error,errors)}}
def finishStop(lease: TerminalLease,state: State,errors: List<&2,Error>) -> IO(Result<&2,&2,Error,Unit>):
  match state:
    case State{_,_,_,_,_,_,prior,wake,_,_}:
      do IO<Result<&2,&2,Error,Unit>>:
        Deferred.dispose(Unit,wake)
        restored : Result<&1,&1,U32 & String,Unit> <- Terminal.restore(lease)
        return finalErrors(addError(osError("restore terminal",restored),List.append(&2,Error,errors,prior)))

# Retire producers, parser and publisher before their callbacks/resources.
# Raw settings restoration runs even when cleanup output or a close fails.
def stop(owner: ProcessTerminal) -> IO(Result<&2,&2,Error,Unit>):
  match owner:
    case ProcessTerminal{lease,state,output,Handle{+resource,outputRef,+inputCancel,outputCancel,+resizeCancel},buffer,observer,reader,resizer,clock}:
      do IO<Result<&2,&2,Error,Unit>>:
        cleanup : String <- Serial.run(State,String,resource,value => stopLocked(value))
        a : Bool <- Pipe.cancel(inputCancel)
        b : Bool <- Pipe.cancel(resizeCancel)
        input : Pipe <- IO.join(Pipe,reader)
        resize : Pipe <- IO.join(Pipe,resizer)
        Input.disposeAsync(buffer)
        joined : Unit <- IO.join(Unit,clock)
        Callback.dispose(Input.InputEvent,Unit,observer)
        written : Result<&2,&2,Error,Unit> <- writeRaw(Handle{resource,outputRef,inputCancel,outputCancel,resizeCancel},cleanup)
        inClosed : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(input)
        resizeClosed : Result<&1,&1,U32 & String,Unit> <- Pipe.close_checked(resize)
        outputValue : Output <- Serial.retire(Output,output)
        outputErrors : List<&2,Error> <- closeOutput(outputValue)
        stateValue : State <- Serial.retire(State,state)
        finishStop(lease,stateValue,addError(osError("close input",inClosed),addError(osError("close resize",resizeClosed),outputErrors)))

def borrow(owner: ProcessTerminal) -> ProcessTerminal & Handle:
  match owner:
    case ProcessTerminal{lease,state,output,+handle,buffer,observer,reader,resizer,clock}:
      (ProcessTerminal{lease,state,output,handle,buffer,observer,reader,resizer,clock},handle)
def readKitty(+state: State) -> IO(State & Bool):
  match state:
    case State{Negotiation{kitty,_,_,_,_},_,_,_,_,_,_,_,_,_}: IO.pure(State & Bool,(state,kitty))
def kittyProtocolActive(handle: Handle) -> IO(Bool):
  match handle:
    case Handle{state,_,_,_,_}: Serial.run(State,Bool,state,value => readKitty(value))
def columnsOf(size: Dimensions) -> U32:
  match size:
    case Dimensions{columns,_}: columns
def rowsOf(size: Dimensions) -> U32:
  match size:
    case Dimensions{_,rows}: rows
def getColumns(handle: Handle) -> IO(U32):
  do IO<U32>:
    size : Dimensions <- getDimensions(handle)
    return columnsOf(size)
def getRows(handle: Handle) -> IO(U32):
  do IO<U32>:
    size : Dimensions <- getDimensions(handle)
    return rowsOf(size)
def hideCursor(handle: Handle) -> IO(Result<&2,&2,Error,Unit>): writeRaw(handle,"\u{1b}[?25l")
def showCursor(handle: Handle) -> IO(Result<&2,&2,Error,Unit>): writeRaw(handle,"\u{1b}[?25h")
def clearLine(handle: Handle) -> IO(Result<&2,&2,Error,Unit>): writeRaw(handle,"\u{1b}[K")
def clearFromCursor(handle: Handle) -> IO(Result<&2,&2,Error,Unit>): writeRaw(handle,"\u{1b}[J")
def clearScreen(handle: Handle) -> IO(Result<&2,&2,Error,Unit>): writeRaw(handle,"\u{1b}[2J\u{1b}[H")
def setTitle(handle: Handle,title: String) -> IO(Result<&2,&2,Error,Unit>): writeRaw(handle,"\u{1b}]0;" ++ title ++ "\u{7}")
# Direction is explicit because Bend's native integers are unsigned.
def moveBy(handle: Handle,up: Bool,+lines: U32) -> IO(Result<&2,&2,Error,Unit>):
  writeRaw(handle,Bool.pick(String,U32.is_eq(lines,0),"","\u{1b}[" ++ U32.show(lines) ++ Bool.pick(String,up,"A","B")))

def failedStart(error: Error,cleanup: Result<&2,&2,Error,Unit>) -> Result<&2,&1,Error,ProcessTerminal>:
  match cleanup:
    case Done{Unit{}}: Fail{error}
    case Fail{cause}: Fail{Cleanup{error <> cause <> Nil{}}}
def started(owner: ProcessTerminal,result: Result<&2,&2,Error,Unit>) -> IO(Result<&2,&1,Error,ProcessTerminal>):
  match result:
    case Done{Unit{}}: IO.pure(Result<&2,&1,Error,ProcessTerminal>,Done{owner})
    case Fail{error}:
      do IO<Result<&2,&1,Error,ProcessTerminal>>:
        cleanup : Result<&2,&2,Error,Unit> <- stop(owner)
        return failedStart(error,cleanup)
def startWorkers(lease: TerminalLease,state: Serial.Owner<State>,output: Serial.Owner<Output>,+listeners: Listeners,observer: Callback.Callback<Input.InputEvent,Unit>,input: Pipe,resize: Pipe,pair: Input.AsyncOwner & Input.AsyncHandle) -> IO(Result<&2,&1,Error,ProcessTerminal>):
  match listeners pair:
    case Listeners{+handle,_,_,_} Tuple{buffer,inputHandle}:
      do IO<Result<&2,&1,Error,ProcessTerminal>>:
        reader : Chan(Pipe) <- IO.fork(Pipe,inputReader(handle,inputHandle,(input,True{})))
        resizer : Chan(Pipe) <- IO.fork(Pipe,resizeReader(listeners,(resize,True{})))
        clock : Chan(Unit) <- IO.fork(Unit,terminalClock(listeners,True{}))
        result : Result<&2,&2,Error,Unit> <- writeRaw(handle,"\u{1b}[?2004h" ++ kittyQuery())
        started(ProcessTerminal{lease,state,output,handle,buffer,observer,reader,resizer,clock},result)
def startBuffer(lease: TerminalLease,state: Serial.Owner<State>,output: Serial.Owner<Output>,+listeners: Listeners,input: Pipe,resize: Pipe,escape: U32) -> IO(Result<&2,&1,Error,ProcessTerminal>):
  do IO<Result<&2,&1,Error,ProcessTerminal>>:
    +observer : Callback.Callback<Input.InputEvent,Unit> <- Callback.create(~Listeners,~Input.InputEvent,~Unit,~onFrame,listeners)
    buffer : Input.AsyncOwner <- Input.createAsync(Input.StdinBufferOptions{50,escape},observer)
    startWorkers(lease,state,output,listeners,observer,input,resize,Input.borrowAsync(buffer))
def startResources(lease: TerminalLease,options: Options,onInput: Callback.Callback<String,Unit>,onResize: Callback.Callback<Unit,Unit>,onSettled: Callback.Callback<Unit,Unit>,input: Pipe & PipeCancel,resize: Pipe & PipeCancel,outputCancel: PipeCancel,state: Serial.Owner<State> & Serial.Handle<State>,output: Serial.Owner<Output> & Serial.Handle<Output>) -> IO(Result<&2,&1,Error,ProcessTerminal>):
  match options input resize state output:
    case Options{_,_,escape,_,_} Tuple{input,inputCancel} Tuple{resize,resizeCancel} Tuple{state,stateHandle} Tuple{output,outputHandle}:
      startBuffer(lease,state,output,Listeners{Handle{stateHandle,outputHandle,inputCancel,outputCancel,resizeCancel},onInput,onResize,onSettled},input,resize,escape)
def acquired(+options: Options,onInput: Callback.Callback<String,Unit>,onResize: Callback.Callback<Unit,Unit>,onSettled: Callback.Callback<Unit,Unit>,result: Result<&1,&1,U32 & String,TerminalLease & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)>) -> IO(Result<&2,&1,Error,ProcessTerminal>):
  match options result:
    case _ Fail{(code,message)}: IO.pure(Result<&2,&1,Error,ProcessTerminal>,Fail{System{"acquire terminal",code,message}})
    case Options{_,_,_,fallback,log} Done{(lease,input,(output,outputCancel),resize)}:
      +outputCancel = {outputCancel: PipeCancel}
      do IO<Result<&2,&1,Error,ProcessTerminal>>:
        measured : Result<&1,&1,U32 & String,U32 & U32> <- Terminal.dimensions(outputCancel)
        wake : Deferred.Deferred<Unit> <- Deferred.new(Unit)
        now : Nat <- IO.now()
        state : Serial.Owner<State> <- Serial.create(State,State{initialNegotiation(),None{},False{},True{},now,dimensionsResult(fallback,measured),Nil{},wake,None{},Nil{}})
        output : Serial.Owner<Output> <- Serial.create(Output,Output{output,None{},log})
        startResources(lease,options,onInput,onResize,onSettled,input,resize,outputCancel,Serial.borrow(State,state),Serial.borrow(Output,output))

# The terminal owns its IO and workers; input/resize callbacks stay caller-owned.
# Stop before disposing listeners. Borrowed operations must be joined before stop.
def start(+options: Options,onInput: Callback.Callback<String,Unit>,onResize: Callback.Callback<Unit,Unit>,onSettled: Callback.Callback<Unit,Unit>) -> IO(Result<&2,&1,Error,ProcessTerminal>):
  match options:
    case Options{input,output,_,_,_}:
      do IO<Result<&2,&1,Error,ProcessTerminal>>:
        result : Result<&1,&1,U32 & String,TerminalLease & (Pipe & PipeCancel) & (Pipe & PipeCancel) & (Pipe & PipeCancel)> <- Terminal.acquire(input,output)
        acquired(options,onInput,onResize,onSettled,result)

def drainState(now: Nat,transition: ProtocolTransition,state: State) -> State & Maybe<&2,String>:
  match transition state:
    case ProtocolTransition{protocol,_,output} State{_,progress,False{},True{},_,dimensions,errors,wake,timer,_}:
      (State{protocol,progress,True{},True{},now,dimensions,errors,wake,timer,Nil{}},Some{output})
    case _ state: (state,None{})
def beginDrain(+now: Nat,+state: State) -> IO(State & Maybe<&2,String>):
  match state:
    case State{protocol,_,_,_,_,_,_,wake,timer,_}:
      do IO<State & Maybe<&2,String>>:
        Input.cancelAsyncTimer(timer)
        settled : Bool <- Deferred.resolve(Unit,wake,Unit{})
        return drainState(now,disableKeyboard(protocol),state)
def endDrain(state: State) -> IO(State & Unit):
  match state:
    case State{protocol,progress,_,active,lastData,dimensions,errors,wake,timer,pending}:
      IO.pure(State & Unit,(State{protocol,progress,False{},active,lastData,dimensions,errors,wake,timer,pending},Unit{}))
def drainRemaining(+now: Nat,+end: Nat,idle: Nat,+state: State) -> IO(State & Nat):
  match state:
    case State{_,_,_,True{},lastData,_,_,_,_,_}:
      IO.pure(State & Nat,(state,Nat.min(end - now,lastData + idle - now)))
    case _: IO.pure(State & Nat,(state,0n))
def sleepOwned(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case (timer,_):
      do IO<Unit>:
        result : Timer & Bool <- Timer.wait(timer)
        Input.closeInputTimer(result)
@unsafe def waitDrain(+state: Serial.Handle<State>,+end: Nat,+idle: Nat,delay: Nat) -> IO(Unit):
  match delay:
    case Zero{}: IO.pure(Unit,Unit{})
    case delay:
      do IO<Unit>:
        timer : Timer & TimerCancel <- Timer.new(U32.from_nat(delay))
        sleepOwned(timer)
        +now : Nat <- IO.now()
        remaining : Nat <- Serial.run(State,Nat,state,current => drainRemaining(now,end,idle,current))
        waitDrain(state,end,idle,remaining)
def draining(+handle: Handle,+state: Serial.Handle<State>,+end: Nat,+idle: Nat,cleanup: Maybe<&2,String>) -> IO(Result<&2,&2,Error,Unit>):
  match cleanup:
    case None{}: IO.pure(Result<&2,&2,Error,Unit>,Fail{Closed{}})
    case Some{text}:
      do IO<Result<&2,&2,Error,Unit>>:
        result : Result<&2,&2,Error,Unit> <- writeRaw(handle,text)
        +now : Nat <- IO.now()
        waitDrain(state,end,idle,Nat.min(end - now,idle))
        Serial.run(State,Unit,state,endDrain)
        return result
# Disables keyboard reporting first, discards late input, and waits for idle or
# the caller's maximum deadline. This borrowed operation is joined before stop.
def drainInput(+handle: Handle,maxMs: U32,idleMs: U32) -> IO(Result<&2,&2,Error,Unit>):
  match handle:
    case Handle{+state,_,_,_,_}:
      do IO<Result<&2,&2,Error,Unit>>:
        +now : Nat <- IO.now()
        cleanup : Maybe<&2,String> <- Serial.run(State,Maybe<&2,String>,state,current => beginDrain(now,current))
        draining(handle,state,now + U32.to_nat(maxMs),U32.to_nat(idleMs),cleanup)

def envText(value: Result<&1,&1,U32 & String,String>) -> String:
  match value:
    case Done{text}: text
    case Fail{_}: ""
def dimensionFallback(value: Result<&1,&1,U32 & String,String>,fallback: U32) -> U32:
  Maybe.default(&2,U32,escapeTimeoutDigits(envText(value),0,False{}),fallback)
def logField(+value: U32) -> String:
  Bool.pick(String,U32.is_lt(value,10),"0","") ++ U32.show(value)
def logFilename(time: LocalTime,pid: U32) -> String:
  match time:
    case LocalTime{year,month,day,hour,minute,second}:
      "tui-" ++ U32.show(year) ++ "-" ++ logField(month) ++ "-" ++ logField(day) ++ "_" ++ logField(hour) ++ "-" ++ logField(minute) ++ "-" ++ logField(second) ++ "-" ++ U32.show(pid) ++ ".log"
def directoryLogPath(+path: String,pid: U32,time: Result<&1,&1,U32 & String,LocalTime>) -> Maybe<&2,String>:
  match time:
    case Done{time}: Some{Path.join(path,logFilename(time,pid))}
    case Fail{_}: Some{path}
def logPathKind(+path: String,result: Result<&1,&1,U32 & String,U32>) -> IO(Maybe<&2,String>):
  match result:
    case Done{2}:
      do IO<Maybe<&2,String>>:
        pid : U32 <- Process.id()
        time : Result<&1,&1,U32 & String,LocalTime> <- Clock.localTime()
        return directoryLogPath(path,pid,time)
    case _: IO.pure(Maybe<&2,String>,Some{path})
def resolveLogPath(path: String) -> IO(Maybe<&2,String>):
  match path:
    case SNil{}: IO.pure(Maybe<&2,String>,None{})
    case +path:
      do IO<Maybe<&2,String>>:
        kind : Result<&1,&1,U32 & String,U32> <- File.kind(path)
        logPathKind(path,kind)
def processOptions() -> IO(Options):
  do IO<Options>:
    escape : Result<&1,&1,U32 & String,String> <- IO.get_env("PI_TUI_ESC_TIMEOUT")
    connection : Result<&1,&1,U32 & String,String> <- IO.get_env("SSH_CONNECTION")
    tty : Result<&1,&1,U32 & String,String> <- IO.get_env("SSH_TTY")
    columns : Result<&1,&1,U32 & String,String> <- IO.get_env("COLUMNS")
    rows : Result<&1,&1,U32 & String,String> <- IO.get_env("LINES")
    logging : Result<&1,&1,U32 & String,String> <- IO.get_env("PI_TUI_WRITE_LOG")
    logPath : Maybe<&2,String> <- resolveLogPath(envText(logging))
    return Options{0,1,resolveEscapeTimeoutMs(envText(escape),envText(connection),envText(tty)),Dimensions{dimensionFallback(columns,80),dimensionFallback(rows,24)},logPath}
def startProcess(input: Callback.Callback<String,Unit>,resize: Callback.Callback<Unit,Unit>,settled: Callback.Callback<Unit,Unit>) -> IO(Result<&2,&1,Error,ProcessTerminal>):
  do IO<Result<&2,&1,Error,ProcessTerminal>>:
    options : Options <- processOptions()
    start(options,input,resize,settled)


def loggedClose(primary: Maybe<&2,Error>,closed: Result<&1,&1,U32 & String,Unit>) -> Result<&2,&2,Error,Unit>:
  finalErrors(addError(osError("close write log",closed),addError(primary,Nil{})))
def logWritten(pair: File & Result<&1,&1,U32 & String,Unit>) -> IO(Result<&2,&2,Error,Unit>):
  match pair:
    case (file,result):
      do IO<Result<&2,&2,Error,Unit>>:
        closed : Result<&1,&1,U32 & String,Unit> <- File.close_checked(file)
        return loggedClose(osError("write log",result),closed)
def openedLog(text: String,result: Result<&1,&1,U32 & String,File>) -> IO(Result<&2,&2,Error,Unit>):
  match result:
    case Fail{(code,message)}: IO.pure(Result<&2,&2,Error,Unit>,Fail{System{"open write log",code,message}})
    case Done{file}:
      do IO<Result<&2,&2,Error,Unit>>:
        result : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,text)
        logWritten(result)
def appendLog(path: Maybe<&2,String>,text: String) -> IO(Result<&2,&2,Error,Unit>):
  match path:
    case None{}: IO.pure(Result<&2,&2,Error,Unit>,Done{Unit{}})
    case Some{path}:
      do IO<Result<&2,&2,Error,Unit>>:
        opened : Result<&1,&1,U32 & String,File> <- File.open_mode(path,"a",438)
        openedLog(text,opened)
def logOutput(text: String,pair: Output & Result<&2,&2,Error,Unit>) -> IO(Output & Result<&2,&2,Error,Unit>):
  match pair:
    case (output,Fail{error}): IO.pure(Output & Result<&2,&2,Error,Unit>,(output,Fail{error}))
    case (Output{pipe,failure,+log},Done{Unit{}}):
      do IO<Output & Result<&2,&2,Error,Unit>>:
        result : Result<&2,&2,Error,Unit> <- appendLog(log,text)
        return (Output{pipe,failure,log},result)
def writeLogged(+text: String,output: Output) -> IO(Output & Result<&2,&2,Error,Unit>):
  do IO<Output & Result<&2,&2,Error,Unit>>:
    result : Output & Result<&2,&2,Error,Unit> <- writeLocked(text,output)
    logOutput(text,result)
def write(handle: Handle,text: String) -> IO(Result<&2,&2,Error,Unit>):
  match handle:
    case Handle{_,output,_,_,_}: Serial.run(Output,Result<&2,&2,Error,Unit>,output,state => writeLogged(text,state))

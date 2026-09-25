import Base
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/deferred.bend as Deferred
import ../../runtime/src/serial-resource.bend as Serial
import ./component.bend as Component
import ./overlays.bend as O
import ./terminal.bend as Terminal
import ./terminal-query.bend as Query
import ./tui-base.bend as Tui
import ./layout-node.bend as Layout
import ./tui.bend as T
import ./tui-main-screen.bend as Screen
import ./tui-alt-screen.bend as Alt

# Rendering is a transaction: the owner publishes mouse bounds and the screen
# retains its new diff state only after every ordered terminal effect succeeds.
type ScreenState is Data: Main{state: Screen.State} Fullscreen{state: Alt.State}
type Session is Data: Session{tui: Tui.TuiBase,screen: ScreenState}
type Error is Data:
  Owner{cause: Tui.Error}
  InvalidFrame{cause: Screen.RenderError}
  Output{cause: Terminal.Error}
type Draw is Data:
  Drawn{session: Session}
  Rejected{session: Session,cause: Error}
type Input is Data: Input{outcome: Draw,handled: Bool,owed: Bool}

def initial() -> Session: Session{Tui.newTui(),Main{Screen.initial()}}
def options(tui: Tui.TuiBase,termux: Bool) -> Screen.Options:
  match tui:
    case Tui.TuiBase{_,O.State{entries,_,_,_,_},_,_,Tui.RenderSchedule{_,_,_,_,_,stopped},show,clear,_}:
      Screen.Options{termux,clear,Bool.not(List.is_empty(&2,O.Entry,entries)),show,stopped}
def frame(prepared: Tui.PreparedFrame,width: Nat,height: Nat) -> Screen.Frame:
  match prepared:
    case Tui.PreparedFrame{_,_,lines,cursor}: Screen.Frame{lines,cursor,width,height}
def planned(+prepared: Tui.PreparedFrame,screen: Screen.State,termux: Bool,width: Nat,height: Nat) -> Result<&2,&2,Screen.RenderError,Screen.Plan>:
  match prepared:
    case Tui.PreparedFrame{+tui,_,_,_}:
      Screen.checkedPlan(screen,frame(prepared,width,height),options(tui,termux))

def effect(handle: Terminal.Handle,value: Screen.Effect) -> IO(Result<&2,&2,Terminal.Error,Unit>):
  match value:
    case Screen.Write{value}: Terminal.write(handle,value)
    case Screen.Visibility{True{}}: Terminal.showCursor(handle)
    case Screen.Visibility{False{}}: Terminal.hideCursor(handle)
@unsafe def writeNext(+handle: Terminal.Handle,batch: Maybe<&2,Screen.Batch>) -> IO(Result<&2,&2,Terminal.Error,Unit>):
  match batch:
    case None{}: IO.pure(Result<&2,&2,Terminal.Error,Unit>,Done{Unit{}})
    case Some{Screen.Batch{value,rest}}:
      do IO<Result<&2,&2,Terminal.Error,Unit>>:
        +result : Result<&2,&2,Terminal.Error,Unit> <- effect(handle,value)
        Bool.pick(Unit -> IO(Result<&2,&2,Terminal.Error,Unit>),Result.is_done(&2,&2,Terminal.Error,Unit,result),
          _ => writeNext(handle,Screen.nextEffect(rest)),
          _ => IO.pure(Result<&2,&2,Terminal.Error,Unit>,result))(Unit{})
def writeEffects(handle: Terminal.Handle,output: Screen.Stream) -> IO(Result<&2,&2,Terminal.Error,Unit>):
  writeNext(handle,Screen.nextEffect(output))
def finished(result: Result<&2,&2,Terminal.Error,Unit>,old: Session,prepared: Tui.PreparedFrame,next: Screen.State) -> Draw:
  match result old:
    case Done{_} _: Drawn{Session{Tui.commitFrame(prepared),Main{next}}}
    case Fail{error} Session{tui,Main{screen}}: Rejected{Session{tui,Main{Screen.resetRenderState(screen)}},Output{error}}
    case Fail{error} Session{tui,Fullscreen{screen}}: Rejected{Session{tui,Fullscreen{Alt.reset(screen)}},Output{error}}
def finishedAlt(result: Result<&2,&2,Terminal.Error,Unit>,old: Session,prepared: Tui.PreparedFrame,next: Alt.State) -> Draw:
  match result old:
    case Done{_} _: Drawn{Session{Tui.commitFrame(prepared),Fullscreen{next}}}
    case Fail{error} Session{tui,screen}: Rejected{Session{tui,screen},Output{error}}
def executePlan(result: Result<&2,&2,Screen.RenderError,Screen.Plan>,old: Session,prepared: Tui.PreparedFrame,handle: Terminal.Handle) -> IO(Draw):
  match result:
    case Fail{error}: IO.pure(Draw,Rejected{old,InvalidFrame{error}})
    case Done{Screen.Plan{next,output,_}}:
      do IO<Draw>:
        written : Result<&2,&2,Terminal.Error,Unit> <- writeEffects(handle,output)
        return finished(written,old,prepared,next)
def executeAltPlan(value: Alt.Plan,old: Session,prepared: Tui.PreparedFrame,handle: Terminal.Handle) -> IO(Draw):
  match value:
    case Alt.Plan{next,output}:
      do IO<Draw>:
        written : Result<&2,&2,Terminal.Error,Unit> <- writeEffects(handle,output)
        return finishedAlt(written,old,prepared,next)
def indicatorText(screen: Alt.State,row: Maybe<&2,Nat>) -> IO(String):
  match row:
    case None{}: IO.pure(String,"")
    case Some{_}: Callback.call(Unit,String,Alt.indicator(screen),Unit{})
def executeAlt(+prepared: Tui.PreparedFrame,old: Session,+screen: Alt.State,handle: Terminal.Handle,width: Nat,height: Nat) -> IO(Draw):
  match prepared:
    case Tui.PreparedFrame{+tui,_,+lines,+cursor}:
      do IO<Draw>:
        +row : Maybe<&2,Nat> <- IO.pure(Maybe<&2,Nat>,Tui.indicatorRow(tui))
        label : String <- indicatorText(screen,row)
        executeAltPlan(Alt.planWithIndicator(screen,lines,cursor,width,height,row,label),old,prepared,handle)
def executePrepared(result: Tui.ResultOf(Tui.PreparedFrame),+old: Session,handle: Terminal.Handle,termux: Bool,width: Nat,height: Nat) -> IO(Draw):
  match result:
    case Fail{error}: IO.pure(Draw,Rejected{old,Owner{error}})
    case Done{+prepared}:
      match old:
        case Session{_,Main{+screen}}: executePlan(planned(prepared,screen,termux,width,height),old,prepared,handle)
        case Session{_,Fullscreen{+screen}}: executeAlt(prepared,old,screen,handle,width,height)
def sized(+session: Session,handle: Terminal.Handle,termux: Bool,+columns: U32,+rows: U32) -> IO(Draw):
  match session:
    case Session{+tui,_}:
      do IO<Draw>:
        prepared : Tui.ResultOf(Tui.PreparedFrame) <- Tui.renderRoot(tui,U32.to_nat(columns),U32.to_nat(rows))
        executePrepared(prepared,session,handle,termux,U32.to_nat(columns),U32.to_nat(rows))
def draw(session: Session,+handle: Terminal.Handle,termux: Bool) -> IO(Draw):
  do IO<Draw>:
    columns : U32 <- Terminal.getColumns(handle)
    rows : U32 <- Terminal.getRows(handle)
    sized(session,handle,termux,columns,rows)

# Input callbacks run before the latency-sensitive redraw. As upstream's
# requestImmediateRender, a frame is owed and drawn once after all input of
# one terminal read (the `settled` callback), in the same owner/screen
# transaction as a manually requested frame.
def afterInput(result: Tui.ResultOf(Tui.InputResult),old: Session,handle: Terminal.Handle,termux: Bool) -> IO(Input):
  match result old:
    case Fail{error} old: IO.pure(Input,Input{Rejected{old,Owner{error}},False{},False{}})
    case Done{Tui.InputResult{tui,handled,immediate}} Session{_,screen}: IO.pure(Input,Input{Drawn{Session{tui,screen}},handled,immediate})
type ViewportAction is Data: Scroll{motion: Layout.ScrollMotion} Consume{} Pass{}
def viewportAction(+data: String) -> ViewportAction:
  match data:
    case "\u{1b}[5~": Scroll{Layout.ScrollPageUp{}}
    case "\u{1b}[6~": Scroll{Layout.ScrollPageDown{}}
    case _:
      Bool.pick(Unit -> ViewportAction,String.starts_with(data,"\u{1b}[<64;"),_ => Scroll{Layout.ScrollLines{T.Backward{1n}}},
        _ => Bool.pick(Unit -> ViewportAction,String.starts_with(data,"\u{1b}[<65;"),_ => Scroll{Layout.ScrollLines{T.Forward{1n}}},
          _ => Bool.pick(Unit -> ViewportAction,String.starts_with(data,"\u{1b}[<72;"),_ => Scroll{Layout.ScrollLines{T.Backward{5n}}},
            _ => Bool.pick(Unit -> ViewportAction,String.starts_with(data,"\u{1b}[<73;"),_ => Scroll{Layout.ScrollLines{T.Forward{5n}}},
              _ => Bool.pick(ViewportAction,String.starts_with(data,"\u{1b}[<"),Consume{},Pass{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def scrollInput(result: Tui.ScrollChange,screen: Alt.State) -> Input:
  match result:
    case Tui.ScrollChange{next,_,render}: Input{Drawn{Session{next,Fullscreen{screen}}},True{},render}
def viewportScrolled(tui: Tui.TuiBase,screen: Alt.State,motion: Layout.ScrollMotion) -> IO(Input):
  do IO<Input>:
    now : Nat <- IO.now()
    return scrollInput(Tui.scrollPrimaryBy(tui,motion,now),screen)
def fullscreenAction(action: ViewportAction,+tui: Tui.TuiBase,+screen: Alt.State,registry: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,data: String,handle: Terminal.Handle,termux: Bool) -> IO(Input):
  match action:
    case Scroll{motion}: viewportScrolled(tui,screen,motion)
    case Consume{}: IO.pure(Input,Input{Drawn{Session{tui,Fullscreen{screen}}},True{},False{}})
    case Pass{}:
      do IO<Input>:
        result : Tui.ResultOf(Tui.InputResult) <- Tui.dispatchInput(tui,registry,mounted,data)
        afterInput(result,Session{tui,Fullscreen{screen}},handle,termux)
def fullscreenInput(tui: Tui.TuiBase,screen: Alt.State,registry: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,+data: String,handle: Terminal.Handle,termux: Bool) -> IO(Input):
  fullscreenAction(viewportAction(data),tui,screen,registry,mounted,data,handle,termux)
def input(+session: Session,registry: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,data: String,handle: Terminal.Handle,termux: Bool) -> IO(Input):
  match session:
    case Session{tui,Fullscreen{screen}}: fullscreenInput(tui,screen,registry,mounted,data,handle,termux)
    case Session{+tui,_}:
      do IO<Input>:
        result : Tui.ResultOf(Tui.InputResult) <- Tui.dispatchInput(tui,registry,mounted,data)
        afterInput(result,session,handle,termux)

# The application owns the terminal and serial state. Its listener callbacks
# share this context, so input, resize and application updates cannot interleave
# between a component callback and the frame it produces.
type Active is Data:
  Active{session: Session,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,lastError: Maybe<&2,Error>,owed: Bool,ticks: Nat}
type EventSink is Data:
  EventSink{state: Serial.Handle<Active>,ready: Deferred.Deferred<Terminal.Handle>,queries: Query.Handle,termux: Bool}
type QueryReady is Data:
  QueryReady{queries: Query.Handle,terminal: Terminal.Handle,write: Callback.Callback<String,Unit>,requestRender: Callback.Callback<Unit,Unit>}
type QueryWriter is Data:
  QueryWriter{terminal: Terminal.Handle,stopped: Deferred.Deferred<Unit>,failure: Deferred.Deferred<Terminal.Error>}
def active(session: Session,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>) -> Active:
  Active{session,components,mounted,None{},False{},0n}
def inputFinished(event: Input,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,previous: Maybe<&2,Error>,+owed: Bool,ticks: Nat) -> Active & Unit:
  match event:
    case Input{Drawn{session},_,now}: (Active{session,components,mounted,previous,owed || now,ticks},Unit{})
    case Input{Rejected{session,error},_,_}: (Active{session,components,mounted,Some{error},owed,ticks},Unit{})
def inputOperation(current: Active,data: String,handle: Terminal.Handle,termux: Bool) -> IO(Active & Unit):
  match current:
    case Active{session,+components,+mounted,previous,owed,ticks}:
      do IO<Active & Unit>:
        event : Input <- input(session,components,mounted,data,handle,termux)
        return inputFinished(event,components,mounted,previous,owed,ticks)
# Render scheduling follows upstream TUI: requestRender queues a scheduling
# step (process.nextTick), which starts a timer honouring the 16 ms minimum
# frame interval; input and resize draw at once and cancel a pending timer.
# `ticks` counts spawned scheduling tasks so shutdown can wait for them.
def spawned(effects: List<&2,Tui.RenderEffect>) -> Nat:
  match effects:
    case Nil{}: 0n
    case Tui.QueueSchedule{} <> rest: 1n + spawned(rest)
    case Tui.QueueImmediate{} <> rest: 1n + spawned(rest)
    case Tui.StartTimer{_,_} <> rest: 1n + spawned(rest)
    case _ <> rest: spawned(rest)
def completes(event: Tui.RenderEvent) -> Nat:
  match event:
    case Tui.ScheduleRender{}: 1n
    case Tui.ImmediateRender{}: 1n
    case Tui.TimerFired{_}: 1n
    case _: 0n
def drawsFrame(effects: List<&2,Tui.RenderEffect>) -> Bool:
  match effects:
    case Nil{}: False{}
    case Tui.DrawFrame{} <> _: True{}
    case _ <> rest: drawsFrame(rest)
def drawIf(frame: Bool,session: Session,handle: Terminal.Handle,termux: Bool) -> IO(Draw):
  match frame:
    case True{}: draw(session,handle,termux)
    case False{}: IO.pure(Draw,Drawn{session})
def scheduledActive(outcome: Draw,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,previous: Maybe<&2,Error>,+owed: Bool,drew: Bool,ticks: Nat) -> Active:
  match outcome:
    case Drawn{session}: Active{session,components,mounted,previous,owed && Bool.not(drew),ticks}
    case Rejected{session,error}: Active{session,components,mounted,Some{error},False{},ticks}
def afterSchedule(pair: Tui.TuiBase & List<&2,Tui.RenderEffect>,screen: ScreenState,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,previous: Maybe<&2,Error>,owed: Bool,ticks: Nat,handle: Terminal.Handle,termux: Bool) -> IO(Active & List<&2,Tui.RenderEffect>):
  match pair:
    case (tui,+effects):
      do IO<Active & List<&2,Tui.RenderEffect>>:
        +drew : Bool <- IO.pure(Bool,drawsFrame(effects))
        outcome : Draw <- drawIf(drew,Session{tui,screen},handle,termux)
        return (scheduledActive(outcome,components,mounted,previous,owed,drew,ticks + spawned(effects)),effects)
def scheduledOperation(+event: Tui.RenderEvent,current: Active,handle: Terminal.Handle,termux: Bool) -> IO(Active & List<&2,Tui.RenderEffect>):
  match current:
    case Active{Session{tui,screen},components,mounted,previous,owed,ticks}:
      do IO<Active & List<&2,Tui.RenderEffect>>:
        now : Nat <- IO.now()
        afterSchedule(Tui.scheduleRender(tui,event,now),screen,components,mounted,previous,owed,ticks - completes(event),handle,termux)
def withoutEffects(pair: Active & List<&2,Tui.RenderEffect>) -> Active & Unit:
  match pair:
    case (value,_): (value,Unit{})
def drawNow(current: Active,handle: Terminal.Handle,termux: Bool) -> IO(Active & Unit):
  do IO<Active & Unit>:
    pair : Active & List<&2,Tui.RenderEffect> <- scheduledOperation(Tui.RenderNow{False{}},current,handle,termux)
    return withoutEffects(pair)
def resizeOperation(current: Active,handle: Terminal.Handle,termux: Bool) -> IO(Active & Unit): drawNow(current,handle,termux)
def settledOperation(current: Active,handle: Terminal.Handle,termux: Bool) -> IO(Active & Unit):
  match current:
    case Active{_,_,_,_,False{},_}: IO.pure(Active & Unit,(current,Unit{}))
    case current: drawNow(current,handle,termux)
def dispatchInput(listener: EventSink,+data: String) -> IO(Unit):
  match listener:
    case EventSink{state,ready,queries,termux}:
      do IO<Unit>:
        consumed : Bool <- Query.consume(queries,data)
        Bool.pick(Unit -> IO(Unit),consumed,
          _ => IO.pure(Unit,Unit{}),
          _ => do IO<Unit>:
            handle : Terminal.Handle <- Deferred.result(Terminal.Handle,ready)
            Serial.run(Active,Unit,state,current => inputOperation(current,data,handle,termux)))(Unit{})
def onInput(listener: EventSink,data: String) -> IO(Unit): dispatchInput(listener,data)
def onResize(listener: EventSink,value: Unit) -> IO(Unit):
  match listener:
    case EventSink{state,ready,_,termux}:
      do IO<Unit>:
        handle : Terminal.Handle <- Deferred.result(Terminal.Handle,ready)
        Serial.run(Active,Unit,state,current => resizeOperation(current,handle,termux))
def onSettled(listener: EventSink,value: Unit) -> IO(Unit):
  match listener:
    case EventSink{state,ready,_,termux}:
      do IO<Unit>:
        handle : Terminal.Handle <- Deferred.result(Terminal.Handle,ready)
        Serial.run(Active,Unit,state,current => settledOperation(current,handle,termux))
def closedTimer(pair: Timer & Bool) -> IO(Unit):
  match pair:
    case (owner,_): Timer.close(owner)
def slept(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case (owner,_):
      do IO<Unit>:
        waited : Timer & Bool <- Timer.wait(owner)
        closedTimer(waited)
def scheduled(listener: EventSink,event: Tui.RenderEvent) -> IO(List<&2,Tui.RenderEffect>):
  match listener:
    case EventSink{state,ready,_,termux}:
      do IO<List<&2,Tui.RenderEffect>>:
        handle : Terminal.Handle <- Deferred.result(Terminal.Handle,ready)
        Serial.run(Active,List<&2,Tui.RenderEffect>,state,current => scheduledOperation(event,current,handle,termux))
# Like Node's setTimeout, a frame timer waits at least 1 ms: an expired Timer
# completes at once, while a pending one fires only once no task is ready, so
# events already received (upstream's queued microtasks) are handled first.
def timerFired(+listener: EventSink,id: Nat,delay: Nat) -> IO(Unit):
  do IO<Unit>:
    timer : Timer & TimerCancel <- Timer.new(U32.from_nat(Nat.max(1n,delay)))
    slept(timer)
    effects : List<&2,Tui.RenderEffect> <- scheduled(listener,Tui.TimerFired{id})
    return Unit{}
def startTimers(+listener: EventSink,effects: List<&2,Tui.RenderEffect>) -> IO(Unit):
  match effects:
    case Nil{}: IO.pure(Unit,Unit{})
    case Tui.StartTimer{id,delay} <> rest:
      do IO<Unit>:
        IO.spawn(Unit,timerFired(listener,id,delay))
        startTimers(listener,rest)
    case _ <> rest: startTimers(listener,rest)
def scheduleTick(+listener: EventSink) -> IO(Unit):
  do IO<Unit>:
    effects : List<&2,Tui.RenderEffect> <- scheduled(listener,Tui.ScheduleRender{})
    startTimers(listener,effects)
def immediateTick(listener: EventSink) -> IO(Unit):
  do IO<Unit>:
    effects : List<&2,Tui.RenderEffect> <- scheduled(listener,Tui.ImmediateRender{})
    return Unit{}
def queueTicks(+listener: EventSink,effects: List<&2,Tui.RenderEffect>) -> IO(Unit):
  match effects:
    case Nil{}: IO.pure(Unit,Unit{})
    case Tui.QueueSchedule{} <> rest:
      do IO<Unit>:
        IO.spawn(Unit,scheduleTick(listener))
        queueTicks(listener,rest)
    case Tui.QueueImmediate{} <> rest:
      do IO<Unit>:
        IO.spawn(Unit,immediateTick(listener))
        queueTicks(listener,rest)
    case _ <> rest: queueTicks(listener,rest)
# The application's requestRender (upstream TUI.requestRender()) only
# schedules: it may be called while input or a render holds the TUI state
# (e.g. a key handler whose session event requests a frame), so the request
# is registered by its own task.
def requested(+listener: EventSink) -> IO(Unit):
  do IO<Unit>:
    effects : List<&2,Tui.RenderEffect> <- scheduled(listener,Tui.RequestRender{False{}})
    queueTicks(listener,effects)
def onRequest(listener: EventSink,value: Unit) -> IO(Unit): IO.spawn(Unit,requested(listener))

# The caller's stop signal is settled by its input/application callbacks. The
# terminal and serialized TUI state remain owned here until all listeners stop.
def unchanged(current: Active) -> IO(Active & Unit): IO.pure(Active & Unit,(current,Unit{}))
def pendingTicks(current: Active) -> IO(Active & Nat):
  match current:
    case Active{session,components,mounted,error,owed,+ticks}: IO.pure(Active & Nat,(Active{session,components,mounted,error,owed,ticks},ticks))
def ticksDrained(+handle: Serial.Handle<Active>,fuel: Nat,pending: Nat) -> IO(Unit):
  match fuel pending:
    case _ Zero{}: IO.pure(Unit,Unit{})
    case Zero{} _: IO.pure(Unit,Unit{})
    case Succ{left} _:
      do IO<Unit>:
        timer : Timer & TimerCancel <- Timer.new(1)
        slept(timer)
        remaining : Nat <- Serial.run(Active,Nat,handle,pendingTicks)
        ticksDrained(handle,left,remaining)
# Scheduled renders stop at shutdown; their in-flight tasks (at most one frame
# interval) finish before the state is retired. `fuel` bounds the wait in ms.
def waitTicks(+handle: Serial.Handle<Active>,fuel: Nat) -> IO(Unit):
  do IO<Unit>:
    pending : Nat <- Serial.run(Active,Nat,handle,pendingTicks)
    ticksDrained(handle,fuel,pending)
def completed(closed: Result<&2,&2,Terminal.Error,Unit>,state: Active) -> Result<&2,&2,Terminal.Error,Active>:
  match closed:
    case Done{_}: Done{state}
    case Fail{error}: Fail{error}
def matchWrite(result: Result<&2,&2,Terminal.Error,Unit>,stopped: Deferred.Deferred<Unit>,failure: Deferred.Deferred<Terminal.Error>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{error}:
      do IO<Unit>:
        recorded : Bool <- Deferred.resolve(Terminal.Error,failure,error)
        settled : Bool <- Deferred.resolve(Unit,stopped,Unit{})
        return Unit{}
def queryWrite(writer: QueryWriter,text: String) -> IO(Unit):
  match writer:
    case QueryWriter{terminal,stopped,failure}:
      do IO<Unit>:
        result : Result<&2,&2,Terminal.Error,Unit> <- Terminal.write(terminal,text)
        matchWrite(result,stopped,failure)
def notifyReady(callback: Maybe<&2,Callback.Callback<QueryReady,Unit>>,value: QueryReady) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{listener}: Callback.call(QueryReady,Unit,listener,value)
def notifyStopping(callback: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit,Unit{})
    case Some{listener}: Callback.call(Unit,Unit,listener,Unit{})
def queryResult(closed: Result<&2,&2,Terminal.Error,Unit>,failure: Maybe<&2,Terminal.Error>,state: Active) -> Result<&2,&2,Terminal.Error,Active>:
  match failure:
    case Some{error}: Fail{error}
    case None{}: completed(closed,state)
def afterDocument(document: Tui.TuiBase & List<&2,String>,state: Alt.State,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,error: Maybe<&2,Error>,owed: Bool,ticks: Nat,width: Nat) -> Active & Screen.Stream:
  match document:
    case (next,lines): (Active{Session{next,Fullscreen{state}},components,mounted,error,owed,ticks},Alt.leaveWithDocument(lines,width))
def beforeStop(current: Active,+width: Nat) -> IO(Active & Screen.Stream):
  match current:
    case Active{Session{tui,Main{+state}},components,mounted,error,owed,ticks}:
      IO.pure(Active & Screen.Stream,(Active{Session{tui,Main{state}},components,mounted,error,owed,ticks},Screen.beforeTerminalStop(state,False{})))
    case Active{Session{tui,Fullscreen{state}},components,mounted,error,owed,ticks}:
      do IO<Active & Screen.Stream>:
        document : Tui.TuiBase & List<&2,String> <- Tui.renderDocument(tui,width)
        return afterDocument(document,state,components,mounted,error,owed,ticks,width)
def isFullscreen(current: Active) -> IO(Active & Bool):
  match current:
    case Active{Session{_,Main{_}},_,_,_,_,_}: IO.pure(Active & Bool,(current,False{}))
    case Active{Session{_,Fullscreen{_}},_,_,_,_,_}: IO.pure(Active & Bool,(current,True{}))
def stoppedResult(cleanup: Result<&2,&2,Terminal.Error,Unit>,closed: Result<&2,&2,Terminal.Error,Unit>,failure: Maybe<&2,Terminal.Error>,state: Active) -> Result<&2,&2,Terminal.Error,Active>:
  match cleanup:
    case Done{_}: queryResult(closed,failure,state)
    case Fail{error}: Fail{error}
# The callback receives borrowed handles while the terminal is live. It may
# await queries here; any forked query must finish before the stop signal.
def runStarted(pair: Terminal.ProcessTerminal & Terminal.Handle,owner: Serial.Owner<Active>,+handle: Serial.Handle<Active>,ready: Deferred.Deferred<Terminal.Handle>,+queries: Query.Handle,onReady: Maybe<&2,Callback.Callback<QueryReady,Unit>>,onStopping: Maybe<&2,Callback.Callback<Unit,Unit>>,requestRender: Callback.Callback<Unit,Unit>,+stopped: Deferred.Deferred<Unit>,+termux: Bool) -> IO(Result<&2,&2,Terminal.Error,Active>):
  match pair:
    case (terminal,+terminalHandle):
      do IO<Result<&2,&2,Terminal.Error,Active>>:
        settled : Bool <- Deferred.resolve(Terminal.Handle,ready,terminalHandle)
        +failure : Deferred.Deferred<Terminal.Error> <- Deferred.new(Terminal.Error)
        +writer : Callback.Callback<String,Unit> <- Callback.create(~QueryWriter,~String,~Unit,~queryWrite,QueryWriter{terminalHandle,stopped,failure})
        Query.setRunning(queries,writer,True{})
        fullscreen : Bool <- Serial.run(Active,Bool,handle,isFullscreen)
        entered : Result<&2,&2,Terminal.Error,Unit> <- Bool.pick(Unit -> IO(Result<&2,&2,Terminal.Error,Unit>),fullscreen,_ => Terminal.write(terminalHandle,Alt.enter()),_ => IO.pure(Result<&2,&2,Terminal.Error,Unit>,Done{Unit{}}))(Unit{})
        matchWrite(entered,stopped,failure)
        notifyReady(onReady,QueryReady{queries,terminalHandle,writer,requestRender})
        initial : Unit <- Serial.run(Active,Unit,handle,current => resizeOperation(current,terminalHandle,termux))
        finished : Unit <- Deferred.result(Unit,stopped)
        notifyStopping(onStopping)
        drained : Unit <- Serial.run(Active,Unit,handle,unchanged)
        stopRendering : List<&2,Tui.RenderEffect> <- Serial.run(Active,List<&2,Tui.RenderEffect>,handle,current => scheduledOperation(Tui.StopRendering{},current,terminalHandle,termux))
        waitTicks(handle,1000n)
        Query.setRunning(queries,writer,False{})
        columns : U32 <- Terminal.getColumns(terminalHandle)
        cleanup : Screen.Stream <- Serial.run(Active,Screen.Stream,handle,current => beforeStop(current,U32.to_nat(columns)))
        written : Result<&2,&2,Terminal.Error,Unit> <- writeEffects(terminalHandle,cleanup)
        closed : Result<&2,&2,Terminal.Error,Unit> <- Terminal.stop(terminal)
        final : Active <- Serial.retire(Active,owner)
        failed : Maybe<&2,Terminal.Error> <- Deferred.peek(Terminal.Error,failure)
        Callback.dispose(String,Unit,writer)
        Deferred.dispose(Terminal.Error,failure)
        return stoppedResult(written,closed,failed,final)
def awaitProcess(started: Result<&2,&1,Terminal.Error,Terminal.ProcessTerminal>,owner: Serial.Owner<Active>,handle: Serial.Handle<Active>,ready: Deferred.Deferred<Terminal.Handle>,+queries: Query.Handle,onReady: Maybe<&2,Callback.Callback<QueryReady,Unit>>,onStopping: Maybe<&2,Callback.Callback<Unit,Unit>>,requestRender: Callback.Callback<Unit,Unit>,+stopped: Deferred.Deferred<Unit>,termux: Bool) -> IO(Result<&2,&2,Terminal.Error,Active>):
  match started:
    case Fail{error}:
      do IO<Result<&2,&2,Terminal.Error,Active>>:
        old : Active <- Serial.retire(Active,owner)
        return Fail{error}
    case Done{terminal}: runStarted(Terminal.borrow(terminal),owner,handle,ready,queries,onReady,onStopping,requestRender,stopped,termux)

def runQueries(pair: Query.Owner & Query.Handle,owner: Serial.Owner<Active>,+state: Serial.Handle<Active>,+ready: Deferred.Deferred<Terminal.Handle>,+stopped: Deferred.Deferred<Unit>,+termux: Bool,onReady: Maybe<&2,Callback.Callback<QueryReady,Unit>>,onStopping: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Result<&2,&2,Terminal.Error,Active>):
  match pair:
    case (queries,+queryHandle):
      do IO<Result<&2,&2,Terminal.Error,Active>>:
        +input : Callback.Callback<String,Unit> <- Callback.create(~EventSink,~String,~Unit,~onInput,EventSink{state,ready,queryHandle,termux})
        +resize : Callback.Callback<Unit,Unit> <- Callback.create(~EventSink,~Unit,~Unit,~onResize,EventSink{state,ready,queryHandle,termux})
        +settled : Callback.Callback<Unit,Unit> <- Callback.create(~EventSink,~Unit,~Unit,~onSettled,EventSink{state,ready,queryHandle,termux})
        +request : Callback.Callback<Unit,Unit> <- Callback.create(~EventSink,~Unit,~Unit,~onRequest,EventSink{state,ready,queryHandle,termux})
        started : Result<&2,&1,Terminal.Error,Terminal.ProcessTerminal> <- Terminal.startProcess(input,resize,settled)
        result : Result<&2,&2,Terminal.Error,Active> <- awaitProcess(started,owner,state,ready,queryHandle,onReady,onStopping,request,stopped,termux)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Unit,Unit,resize)
        Callback.dispose(Unit,Unit,settled)
        Callback.dispose(Unit,Unit,request)
        Deferred.dispose(Terminal.Handle,ready)
        Query.close(queries)
        return result
def runOwner(pair: Serial.Owner<Active> & Serial.Handle<Active>,stopped: Deferred.Deferred<Unit>,+termux: Bool,onReady: Maybe<&2,Callback.Callback<QueryReady,Unit>>,onStopping: Maybe<&2,Callback.Callback<Unit,Unit>>) -> IO(Result<&2,&2,Terminal.Error,Active>):
  match pair:
    case (owner,+state):
      do IO<Result<&2,&2,Terminal.Error,Active>>:
        +ready : Deferred.Deferred<Terminal.Handle> <- Deferred.new(Terminal.Handle)
        queries : Query.Owner <- Query.create()
        runQueries(Query.borrow(queries),owner,state,ready,stopped,termux,onReady,onStopping)
def runProcessWithQueries(initial: Active,stopped: Deferred.Deferred<Unit>,termux: Bool,onReady: Callback.Callback<QueryReady,Unit>) -> IO(Result<&2,&2,Terminal.Error,Active>):
  do IO<Result<&2,&2,Terminal.Error,Active>>:
    owner : Serial.Owner<Active> <- Serial.create(Active,initial)
    runOwner(Serial.borrow(Active,owner),stopped,termux,Some{onReady},None{})
def runProcessWithLifecycle(initial: Active,stopped: Deferred.Deferred<Unit>,termux: Bool,onReady: Callback.Callback<QueryReady,Unit>,onStopping: Callback.Callback<Unit,Unit>) -> IO(Result<&2,&2,Terminal.Error,Active>):
  do IO<Result<&2,&2,Terminal.Error,Active>>:
    owner : Serial.Owner<Active> <- Serial.create(Active,initial)
    runOwner(Serial.borrow(Active,owner),stopped,termux,Some{onReady},Some{onStopping})
def runProcess(initial: Active,stopped: Deferred.Deferred<Unit>,termux: Bool) -> IO(Result<&2,&2,Terminal.Error,Active>):
  do IO<Result<&2,&2,Terminal.Error,Active>>:
    owner : Serial.Owner<Active> <- Serial.create(Active,initial)
    runOwner(Serial.borrow(Active,owner),stopped,termux,None{},None{})

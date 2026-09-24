import Base
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/deferred.bend as Deferred
import ../../runtime/src/serial-resource.bend as Serial
import ./component.bend as Component
import ./overlays.bend as O
import ./terminal.bend as Terminal
import ./terminal-query.bend as Query
import ./tui-base.bend as Tui
import ./tui-main-screen.bend as Screen

# Rendering is a transaction: the owner publishes mouse bounds and the screen
# retains its new diff state only after every ordered terminal effect succeeds.
type Session is Data: Session{tui: Tui.TuiBase,screen: Screen.State}
type Error is Data:
  Owner{cause: Tui.Error}
  InvalidFrame{cause: Screen.RenderError}
  Output{cause: Terminal.Error}
type Draw is Data:
  Drawn{session: Session}
  Rejected{session: Session,cause: Error}
type Input is Data: Input{outcome: Draw,handled: Bool,owed: Bool}

def initial() -> Session: Session{Tui.newTui(),Screen.initial()}
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
    case Done{_} _: Drawn{Session{Tui.commitFrame(prepared),next}}
    case Fail{error} Session{tui,screen}: Rejected{Session{tui,Screen.resetRenderState(screen)},Output{error}}
def executePlan(result: Result<&2,&2,Screen.RenderError,Screen.Plan>,old: Session,prepared: Tui.PreparedFrame,handle: Terminal.Handle) -> IO(Draw):
  match result:
    case Fail{error}: IO.pure(Draw,Rejected{old,InvalidFrame{error}})
    case Done{Screen.Plan{next,output,_}}:
      do IO<Draw>:
        written : Result<&2,&2,Terminal.Error,Unit> <- writeEffects(handle,output)
        return finished(written,old,prepared,next)
def executePrepared(result: Tui.ResultOf(Tui.PreparedFrame),+old: Session,handle: Terminal.Handle,termux: Bool,width: Nat,height: Nat) -> IO(Draw):
  match result:
    case Fail{error}: IO.pure(Draw,Rejected{old,Owner{error}})
    case Done{+prepared}:
      match old:
        case Session{_,+screen}: executePlan(planned(prepared,screen,termux,width,height),old,prepared,handle)
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
def input(+session: Session,registry: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,data: String,handle: Terminal.Handle,termux: Bool) -> IO(Input):
  match session:
    case Session{+tui,_}:
      do IO<Input>:
        result : Tui.ResultOf(Tui.InputResult) <- Tui.dispatchInput(tui,registry,mounted,data)
        afterInput(result,session,handle,termux)

# The application owns the terminal and serial state. Its listener callbacks
# share this context, so input, resize and application updates cannot interleave
# between a component callback and the frame it produces.
type Active is Data:
  Active{session: Session,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,lastError: Maybe<&2,Error>,owed: Bool}
type EventSink is Data:
  EventSink{state: Serial.Handle<Active>,ready: Deferred.Deferred<Terminal.Handle>,queries: Query.Handle,termux: Bool}
type QueryReady is Data:
  QueryReady{queries: Query.Handle,terminal: Terminal.Handle,write: Callback.Callback<String,Unit>,requestRender: Callback.Callback<Unit,Unit>}
type QueryWriter is Data:
  QueryWriter{terminal: Terminal.Handle,stopped: Deferred.Deferred<Unit>,failure: Deferred.Deferred<Terminal.Error>}
def active(session: Session,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>) -> Active:
  Active{session,components,mounted,None{},False{}}
def afterDraw(outcome: Draw,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,previous: Maybe<&2,Error>) -> Active:
  match outcome:
    case Drawn{session}: Active{session,components,mounted,previous,False{}}
    case Rejected{session,error}: Active{session,components,mounted,Some{error},False{}}
def inputFinished(event: Input,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,previous: Maybe<&2,Error>,+owed: Bool) -> Active & Unit:
  match event:
    case Input{Drawn{session},_,now}: (Active{session,components,mounted,previous,owed || now},Unit{})
    case Input{Rejected{session,error},_,_}: (Active{session,components,mounted,Some{error},owed},Unit{})
def inputOperation(current: Active,data: String,handle: Terminal.Handle,termux: Bool) -> IO(Active & Unit):
  match current:
    case Active{session,+components,+mounted,previous,owed}:
      do IO<Active & Unit>:
        event : Input <- input(session,components,mounted,data,handle,termux)
        return inputFinished(event,components,mounted,previous,owed)
def resizeOperation(current: Active,handle: Terminal.Handle,termux: Bool) -> IO(Active & Unit):
  match current:
    case Active{session,components,mounted,previous,_}:
      do IO<Active & Unit>:
        outcome : Draw <- draw(session,handle,termux)
        return (afterDraw(outcome,components,mounted,previous),Unit{})
def settledOperation(current: Active,handle: Terminal.Handle,termux: Bool) -> IO(Active & Unit):
  match current:
    case Active{_,_,_,_,False{}}: IO.pure(Active & Unit,(current,Unit{}))
    case current: resizeOperation(current,handle,termux)
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

# The caller's stop signal is settled by its input/application callbacks. The
# terminal and serialized TUI state remain owned here until all listeners stop.
def unchanged(current: Active) -> IO(Active & Unit): IO.pure(Active & Unit,(current,Unit{}))
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
def beforeStop(current: Active) -> IO(Active & Screen.Stream):
  match current:
    case Active{Session{tui,+screen},components,mounted,error,owed}:
      IO.pure(Active & Screen.Stream,(Active{Session{tui,screen},components,mounted,error,owed},Screen.beforeTerminalStop(screen,False{})))
def stoppedResult(cleanup: Result<&2,&2,Terminal.Error,Unit>,closed: Result<&2,&2,Terminal.Error,Unit>,failure: Maybe<&2,Terminal.Error>,state: Active) -> Result<&2,&2,Terminal.Error,Active>:
  match cleanup:
    case Done{_}: queryResult(closed,failure,state)
    case Fail{error}: Fail{error}
# The callback receives borrowed handles while the terminal is live. It may
# await queries here; any forked query must finish before the stop signal.
def runStarted(pair: Terminal.ProcessTerminal & Terminal.Handle,owner: Serial.Owner<Active>,+handle: Serial.Handle<Active>,ready: Deferred.Deferred<Terminal.Handle>,+queries: Query.Handle,onReady: Maybe<&2,Callback.Callback<QueryReady,Unit>>,onStopping: Maybe<&2,Callback.Callback<Unit,Unit>>,requestRender: Callback.Callback<Unit,Unit>,+stopped: Deferred.Deferred<Unit>,termux: Bool) -> IO(Result<&2,&2,Terminal.Error,Active>):
  match pair:
    case (terminal,+terminalHandle):
      do IO<Result<&2,&2,Terminal.Error,Active>>:
        settled : Bool <- Deferred.resolve(Terminal.Handle,ready,terminalHandle)
        +failure : Deferred.Deferred<Terminal.Error> <- Deferred.new(Terminal.Error)
        +writer : Callback.Callback<String,Unit> <- Callback.create(~QueryWriter,~String,~Unit,~queryWrite,QueryWriter{terminalHandle,stopped,failure})
        Query.setRunning(queries,writer,True{})
        notifyReady(onReady,QueryReady{queries,terminalHandle,writer,requestRender})
        initial : Unit <- Serial.run(Active,Unit,handle,current => resizeOperation(current,terminalHandle,termux))
        finished : Unit <- Deferred.result(Unit,stopped)
        notifyStopping(onStopping)
        drained : Unit <- Serial.run(Active,Unit,handle,unchanged)
        Query.setRunning(queries,writer,False{})
        cleanup : Screen.Stream <- Serial.run(Active,Screen.Stream,handle,beforeStop)
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
        started : Result<&2,&1,Terminal.Error,Terminal.ProcessTerminal> <- Terminal.startProcess(input,resize,settled)
        result : Result<&2,&2,Terminal.Error,Active> <- awaitProcess(started,owner,state,ready,queryHandle,onReady,onStopping,resize,stopped,termux)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Unit,Unit,resize)
        Callback.dispose(Unit,Unit,settled)
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

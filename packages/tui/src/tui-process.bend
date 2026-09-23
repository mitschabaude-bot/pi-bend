import Base
import ../../runtime/src/deferred.bend as Deferred
import ../../runtime/src/serial-resource.bend as Serial
import ./component.bend as Component
import ./overlays.bend as O
import ./terminal.bend as Terminal
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
type Input is Data: Input{outcome: Draw,handled: Bool}

def initial() -> Session: Session{Tui.newTui(),Screen.initial()}
def options(tui: Tui.TuiBase,termux: Bool) -> Screen.Options:
  match tui:
    case Tui.TuiBase{_,O.State{entries,_,_,_,_},_,_,Tui.RenderSchedule{_,_,_,_,_,stopped},show,clear}:
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

# Input callbacks run before the latency-sensitive redraw, using the same
# owner/screen transaction as a manually requested frame.
def afterInput(result: Tui.ResultOf(Tui.InputResult),old: Session,handle: Terminal.Handle,termux: Bool) -> IO(Input):
  match result old:
    case Fail{error} old: IO.pure(Input,Input{Rejected{old,Owner{error}},False{}})
    case Done{Tui.InputResult{+tui,+handled,immediate}} Session{_,+screen}:
      Bool.pick(Unit -> IO(Input),immediate,
        _ => do IO<Input>:
          outcome : Draw <- draw(Session{tui,screen},handle,termux)
          return Input{outcome,handled},
        _ => IO.pure(Input,Input{Drawn{Session{tui,screen}},handled}))(Unit{})
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
  Active{session: Session,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,lastError: Maybe<&2,Error>}
type EventSink is Data:
  EventSink{state: Serial.Handle<Active>,ready: Deferred.Deferred<Terminal.Handle>,termux: Bool}
def active(session: Session,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>) -> Active:
  Active{session,components,mounted,None{}}
def afterDraw(outcome: Draw,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,previous: Maybe<&2,Error>) -> Active:
  match outcome:
    case Drawn{session}: Active{session,components,mounted,previous}
    case Rejected{session,error}: Active{session,components,mounted,Some{error}}
def inputFinished(event: Input,components: List<&2,Component.Component>,mounted: List<&2,Component.ComponentId>,previous: Maybe<&2,Error>) -> Active & Unit:
  match event:
    case Input{outcome,_}: (afterDraw(outcome,components,mounted,previous),Unit{})
def inputOperation(current: Active,data: String,handle: Terminal.Handle,termux: Bool) -> IO(Active & Unit):
  match current:
    case Active{session,+components,+mounted,previous}:
      do IO<Active & Unit>:
        event : Input <- input(session,components,mounted,data,handle,termux)
        return inputFinished(event,components,mounted,previous)
def resizeOperation(current: Active,handle: Terminal.Handle,termux: Bool) -> IO(Active & Unit):
  match current:
    case Active{session,components,mounted,previous}:
      do IO<Active & Unit>:
        outcome : Draw <- draw(session,handle,termux)
        return (afterDraw(outcome,components,mounted,previous),Unit{})
def onInput(listener: EventSink,data: String) -> IO(Unit):
  match listener:
    case EventSink{state,ready,termux}:
      do IO<Unit>:
        handle : Terminal.Handle <- Deferred.result(Terminal.Handle,ready)
        Serial.run(Active,Unit,state,current => inputOperation(current,data,handle,termux))
def onResize(listener: EventSink,value: Unit) -> IO(Unit):
  match listener:
    case EventSink{state,ready,termux}:
      do IO<Unit>:
        handle : Terminal.Handle <- Deferred.result(Terminal.Handle,ready)
        Serial.run(Active,Unit,state,current => resizeOperation(current,handle,termux))

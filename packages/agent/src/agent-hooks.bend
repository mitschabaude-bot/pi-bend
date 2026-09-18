import Base
import ./types.bend as T
import ./agent-lifecycle.bend as Life
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/abort.bend as Abort

def Signal() -> Data: Abort.AbortSignal<Unit>
def PrepareResult(-Update: Data, -Error: Data) -> Data: Result<&2, &2, Error, Maybe<&2, Update>>
def StopHook(-Turn: Data, -Error: Data) -> Data: C.Callback<T.ToolHookInput<Turn, Signal()>, Result<&2, &2, Error, Bool>>
def LegacyHook(-Update: Data, -Error: Data) -> Data: C.Callback<Maybe<&2, Signal()>, PrepareResult(Update, Error)>
def ContextHook(-Turn: Data, -Update: Data, -Error: Data) -> Data: C.Callback<T.ToolHookInput<Turn, Signal()>, PrepareResult(Update, Error)>

# These handles are borrowed from the Agent's mutable options. Preparation
# rereads both forms on every invocation; stop hooks are captured per run.
type Hooks<-Turn: Data, -Update: Data, -Error: Data> is Data:
  Hooks{shouldStopAfterTurn: Maybe<&2, StopHook(Turn, Error)>, prepareNextTurn: Maybe<&2, LegacyHook(Update, Error)>, prepareNextTurnWithContext: Maybe<&2, ContextHook(Turn, Update, Error)>}
type Adapters<-Turn: Data, -Update: Data, -Error: Data> is Data:
  Adapters{shouldStopAfterTurn: Maybe<&2, C.Callback<Turn, Result<&2, &2, Error, Bool>>>, prepareNextTurn: Maybe<&2, C.Callback<Turn, PrepareResult(Update, Error)>>}
type StopCapture<-State: Data, -Turn: Data, -Error: Data> is Data:
  StopCapture{lifecycle: Life.Lifecycle<State>, hook: StopHook(Turn, Error)}
type PrepareCapture<-State: Data, -Turn: Data, -Update: Data, -Error: Data> is Data:
  PrepareCapture{lifecycle: Life.Lifecycle<State>, hooks: R.Ref<Hooks<Turn, Update, Error>>}

def signal(-State: Data, lifecycle: Life.Lifecycle<State>) -> IO(Maybe<&2, Signal()>):
  do IO<Maybe<&2, Signal()>>:
    active : Maybe<&2, Life.ActiveRun> <- Life.activeRun(State, lifecycle)
    return Maybe.map(&2, Life.ActiveRun, Signal(), run => Life.signal(run), active)
def stopBody(-State: Data, -Turn: Data, -Error: Data, capture: StopCapture<State, Turn, Error>, context: Turn) -> IO(Result<&2, &2, Error, Bool>):
  match capture:
    case StopCapture{lifecycle, hook}:
      do IO<Result<&2, &2, Error, Bool>>:
        active : Maybe<&2, Signal()> <- signal(State, lifecycle)
        C.call(T.ToolHookInput<Turn, Signal()>, Result<&2, &2, Error, Bool>, hook, T.ToolHookInput{context, active})
def prepareSelected(-State: Data, -Turn: Data, -Update: Data, -Error: Data, lifecycle: Life.Lifecycle<State>, hooks: Hooks<Turn, Update, Error>, context: Turn) -> IO(PrepareResult(Update, Error)):
  match hooks:
    case Hooks{_, _, Some{hook}}:
      do IO<PrepareResult(Update, Error)>:
        active : Maybe<&2, Signal()> <- signal(State, lifecycle)
        C.call(T.ToolHookInput<Turn, Signal()>, PrepareResult(Update, Error), hook, T.ToolHookInput{context, active})
    case Hooks{_, Some{hook}, None{}}:
      do IO<PrepareResult(Update, Error)>:
        active : Maybe<&2, Signal()> <- signal(State, lifecycle)
        C.call(Maybe<&2, Signal()>, PrepareResult(Update, Error), hook, active)
    case Hooks{_, None{}, None{}}: IO.pure(PrepareResult(Update, Error), Done{None{}})
def prepareBody(-State: Data, -Turn: Data, -Update: Data, -Error: Data, capture: PrepareCapture<State, Turn, Update, Error>, context: Turn) -> IO(PrepareResult(Update, Error)):
  match capture:
    case PrepareCapture{lifecycle, hooks}:
      do IO<PrepareResult(Update, Error)>:
        selected : Hooks<Turn, Update, Error> <- R.read(Hooks<Turn, Update, Error>, hooks)
        prepareSelected(State, Turn, Update, Error, lifecycle, selected, context)
def createStop(~State: Data, ~Turn: Data, ~Error: Data, lifecycle: Life.Lifecycle<State>, hook: Maybe<&2, StopHook(Turn, Error)>) -> IO(Maybe<&2, C.Callback<Turn, Result<&2, &2, Error, Bool>>>):
  match hook:
    case None{}: IO.pure(Maybe<&2, C.Callback<Turn, Result<&2, &2, Error, Bool>>>, None{})
    case Some{callback}:
      do IO<Maybe<&2, C.Callback<Turn, Result<&2, &2, Error, Bool>>>>:
        adapted : C.Callback<Turn, Result<&2, &2, Error, Bool>> <- C.create(~StopCapture<State, Turn, Error>, ~Turn, ~Result<&2, &2, Error, Bool>, ~(stopBody(State, Turn, Error)), StopCapture{lifecycle, callback})
        return Some{adapted}
def hasPreparation(-Turn: Data, -Update: Data, -Error: Data, hooks: Hooks<Turn, Update, Error>) -> Bool:
  match hooks:
    case Hooks{_, None{}, None{}}: False{}
    case _: True{}
def createPrepare(~State: Data, ~Turn: Data, ~Update: Data, ~Error: Data, lifecycle: Life.Lifecycle<State>, hooks: R.Ref<Hooks<Turn, Update, Error>>, enabled: Bool) -> IO(Maybe<&2, C.Callback<Turn, PrepareResult(Update, Error)>>):
  match enabled:
    case False{}: IO.pure(Maybe<&2, C.Callback<Turn, PrepareResult(Update, Error)>>, None{})
    case True{}:
      do IO<Maybe<&2, C.Callback<Turn, PrepareResult(Update, Error)>>>:
        adapted : C.Callback<Turn, PrepareResult(Update, Error)> <- C.create(~PrepareCapture<State, Turn, Update, Error>, ~Turn, ~PrepareResult(Update, Error), ~(prepareBody(State, Turn, Update, Error)), PrepareCapture{lifecycle, hooks})
        return Some{adapted}
def stopValue(-Turn: Data, -Update: Data, -Error: Data, hooks: Hooks<Turn, Update, Error>) -> Maybe<&2, StopHook(Turn, Error)>:
  match hooks:
    case Hooks{stop, _, _}: stop
def create(~State: Data, ~Turn: Data, ~Update: Data, ~Error: Data, +lifecycle: Life.Lifecycle<State>, +hooks: R.Ref<Hooks<Turn, Update, Error>>) -> IO(Adapters<Turn, Update, Error>):
  do IO<Adapters<Turn, Update, Error>>:
    +current : Hooks<Turn, Update, Error> <- R.read(Hooks<Turn, Update, Error>, hooks)
    stop : Maybe<&2, C.Callback<Turn, Result<&2, &2, Error, Bool>>> <- createStop(~State, ~Turn, ~Error, lifecycle, stopValue(Turn, Update, Error, current))
    prepare : Maybe<&2, C.Callback<Turn, PrepareResult(Update, Error)>> <- createPrepare(~State, ~Turn, ~Update, ~Error, lifecycle, hooks, hasPreparation(Turn, Update, Error, current))
    return Adapters{stop, prepare}
def disposeCallback(-Input: Data, -Output: Data, callback: Maybe<&2, C.Callback<Input, Output>>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}: C.dispose(Input, Output, value)
# Drain in-flight calls before disposing adapters. Original hooks, option
# storage and lifecycle remain caller-owned, including replaced callbacks.
def dispose(-Turn: Data, -Update: Data, -Error: Data, adapters: Adapters<Turn, Update, Error>) -> IO(Unit):
  match adapters:
    case Adapters{stop, prepare}:
      do IO<Unit>:
        disposeCallback(Turn, Result<&2, &2, Error, Bool>, stop)
        disposeCallback(Turn, PrepareResult(Update, Error), prepare)

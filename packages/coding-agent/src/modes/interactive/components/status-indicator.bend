import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/components/loader.bend as Loader
import ../../../../../tui/src/utils.bend as Utils
import ../theme/theme.bend as Theme
import ./countdown-timer.bend as Countdown

type StatusIndicatorKind is Data: Working{} Retry{} Compaction{} BranchSummary{}
type CompactionStatusReason is Data: Manual{} Threshold{} Overflow{}
type Indicator is Data:
  WorkingStatusIndicator{message: String,indicator: Maybe<&2,Loader.Indicator>}
  RetryStatusIndicator{attempt: Nat,maxAttempts: Nat,delayMs: Nat,cancelKey: String}
  CompactionStatusIndicator{reason: CompactionStatusReason,cancelKey: String}
  BranchSummaryStatusIndicator{cancelKey: String}
type Appearance is Data:
  Appearance{theme: Ref.Ref<Theme.Theme>,workingColor: Maybe<&2,Callback.Callback<String,String>>,requestRender: Callback.Callback<Unit,Unit>}
type Handle is Data: Handle{kind: StatusIndicatorKind,loader: Loader.Handle}
type Owner is Type:
  Owner{indicator: Indicator,appearance: Appearance,loader: Loader.Owner,colors: List<&2,Callback.Callback<String,String>>,countdown: Maybe<&1,Countdown.Owner>,tick: Maybe<&2,Callback.Callback<Nat,Unit>>}
type Paint is Data: Paint{theme: Ref.Ref<Theme.Theme>,key: String}
type RetryTick is Data: RetryTick{loader: Loader.Handle,attempt: Nat,maxAttempts: Nat,cancelKey: String}

def kind(indicator: Indicator) -> StatusIndicatorKind:
  match indicator:
    case WorkingStatusIndicator{_,_}: Working{}
    case RetryStatusIndicator{_,_,_,_}: Retry{}
    case CompactionStatusIndicator{_,_}: Compaction{}
    case BranchSummaryStatusIndicator{_}: BranchSummary{}
def sameKind(left: StatusIndicatorKind,right: StatusIndicatorKind) -> Bool:
  match left right:
    case Working{} Working{}: True{}
    case Retry{} Retry{}: True{}
    case Compaction{} Compaction{}: True{}
    case BranchSummary{} BranchSummary{}: True{}
    case _ _: False{}
def retryMessage(attempt: Nat,maxAttempts: Nat,seconds: Nat,cancelKey: String) -> String:
  "Retrying (" ++ Nat.show(attempt) ++ "/" ++ Nat.show(maxAttempts) ++ ") in " ++ Nat.show(seconds) ++ "s... (" ++ cancelKey ++ " to cancel)"
def message(indicator: Indicator) -> String:
  match indicator:
    case WorkingStatusIndicator{text,_}: text
    case RetryStatusIndicator{attempt,maxAttempts,delay,cancel}: retryMessage(attempt,maxAttempts,Countdown.seconds(delay),cancel)
    case CompactionStatusIndicator{Manual{},cancel}: "Compacting context... (" ++ cancel ++ " to cancel)"
    case CompactionStatusIndicator{Threshold{},cancel}: "Auto-compacting... (" ++ cancel ++ " to cancel)"
    case CompactionStatusIndicator{Overflow{},cancel}: "Context overflow detected, Auto-compacting... (" ++ cancel ++ " to cancel)"
    case BranchSummaryStatusIndicator{cancel}: "Summarizing branch... (" ++ cancel ++ " to cancel)"
def paint(context: Paint,text: String) -> IO(String):
  match context:
    case Paint{theme,key}:
      do IO<String>:
        current : Theme.Theme <- Ref.read(Theme.Theme,theme)
        return Theme.fg(current,key,text)
def retryTick(context: RetryTick,seconds: Nat) -> IO(Unit):
  match context:
    case RetryTick{loader,attempt,maxAttempts,cancel}: Loader.updateMessage(loader,retryMessage(attempt,maxAttempts,seconds,cancel))
def started(indicator: Indicator,appearance: Appearance,pair: Loader.Owner & Loader.Handle,colors: List<&2,Callback.Callback<String,String>>) -> IO(Owner):
  match indicator appearance pair:
    case RetryStatusIndicator{+attempt,+maxAttempts,+delay,+cancel} Appearance{theme,workingColor,+redraw} Tuple{owner,handle}:
      do IO<Owner>:
        +update : Callback.Callback<Nat,Unit> <- Callback.create(~RetryTick,~Nat,~Unit,~retryTick,RetryTick{handle,attempt,maxAttempts,cancel})
        # Loader.updateMessage already requests rendering for each tick.
        countdown : Countdown.Owner <- Countdown.create(delay,None{},update,redraw)
        return Owner{RetryStatusIndicator{attempt,maxAttempts,delay,cancel},Appearance{theme,workingColor,redraw},owner,colors,Some{countdown},Some{update}}
    case spec appearance Tuple{owner,_}: IO.pure(Owner,Owner{spec,appearance,owner,colors,None{},None{}})
def configuration(indicator: Indicator) -> Maybe<&2,Loader.Indicator>:
  match indicator: case WorkingStatusIndicator{_,value}: value case _: None{}
def withColors(+indicator: Indicator,+appearance: Appearance,spinner: Callback.Callback<String,String>,color: Callback.Callback<String,String>,owned: List<&2,Callback.Callback<String,String>>) -> IO(Owner):
  match appearance:
    case Appearance{_,_,redraw}:
      do IO<Owner>:
        +frames : Maybe<&2,Loader.Indicator> <- IO.pure(Maybe<&2,Loader.Indicator>,configuration(indicator))
        loader : Loader.Owner <- Loader.create(message(indicator),frames,spinner,color,redraw)
        started(indicator,appearance,Loader.borrow(loader),owned)
def spinnerKey(indicator: Indicator) -> String:
  match indicator: case RetryStatusIndicator{_,_,_,_}: "warning" case _: "accent"
def create(+indicator: Indicator,+appearance: Appearance) -> IO(Owner):
  match indicator appearance:
    case WorkingStatusIndicator{_,_} Appearance{_,Some{+color},_}: withColors(indicator,appearance,color,color,Nil{})
    case _ Appearance{+theme,_,_}:
      do IO<Owner>:
        +spinner : Callback.Callback<String,String> <- Callback.create(~Paint,~String,~String,~paint,Paint{theme,spinnerKey(indicator)})
        +color : Callback.Callback<String,String> <- Callback.create(~Paint,~String,~String,~paint,Paint{theme,"muted"})
        withColors(indicator,appearance,spinner,color,[spinner,color])
def borrow(owner: Owner) -> Owner & Handle:
  match owner:
    case Owner{+indicator,appearance,Loader.Owner{resource,+handle,animation},colors,countdown,tick}:
      (Owner{indicator,appearance,Loader.Owner{resource,handle,animation},colors,countdown,tick},Handle{kind(indicator),handle})
def render(handle: Handle,width: Nat) -> IO(List<&2,String>):
  match handle: case Handle{_,loader}: Loader.renderLive(loader,width)
def renderInBorder(handle: Handle,+width: Nat) -> IO(String):
  do IO<String>:
    rows : List<&2,String> <- render(handle,width + 2n)
    +line : String <- IO.pure(String,Maybe.default(&2,String,List.get(&2,String,rows,1n),""))
    return Utils.truncateToWidth(Utils.trimEnd(Bool.pick(String,String.starts_with(line," "),String.drop(line,1n),line)),width,"",False{})
def renderSpinnerInBorder(handle: Handle,width: Nat) -> IO(String):
  match handle:
    case Handle{_,loader}:
      do IO<String>:
        spinner : String <- Loader.getRenderedIndicator(loader)
        return Utils.truncateToWidth(spinner,width,"",False{})
def idleStatus(width: Nat) -> List<&2,String>:
  +blank = Utils.spaces(width,"")
  [blank,blank]
def stop(owner: Owner) -> IO(Owner):
  match owner:
    case Owner{indicator,appearance,loader,colors,countdown,tick}:
      do IO<Owner>:
        stopped : Loader.Owner <- Loader.stop(loader)
        return Owner{indicator,appearance,stopped,colors,countdown,tick}
def start(owner: Owner) -> IO(Owner):
  match owner:
    case Owner{indicator,appearance,loader,colors,countdown,tick}:
      do IO<Owner>:
        started : Loader.Owner <- Loader.start(loader)
        return Owner{indicator,appearance,started,colors,countdown,tick}
def disposeTick(tick: Maybe<&2,Callback.Callback<Nat,Unit>>) -> IO(Unit):
  match tick: case None{}: IO.pure(Unit,Unit{}) case Some{callback}: Callback.dispose(Nat,Unit,callback)
def disposeCountdown(owner: Maybe<&1,Countdown.Owner>,tick: Maybe<&2,Callback.Callback<Nat,Unit>>) -> IO(Unit):
  match owner:
    case None{}: IO.pure(Unit,Unit{})
    case Some{timer}:
      do IO<Unit>:
        Countdown.dispose(timer)
        disposeTick(tick)
def disposeColors(colors: List<&2,Callback.Callback<String,String>>) -> IO(Unit):
  match colors:
    case Nil{}: IO.pure(Unit,Unit{})
    case color <> rest:
      do IO<Unit>:
        Callback.dispose(String,String,color)
        disposeColors(rest)
def retire(owner: Owner) -> IO(Appearance):
  match owner:
    case Owner{_,appearance,loader,colors,countdown,tick}:
      do IO<Appearance>:
        disposeCountdown(countdown,tick)
        Loader.dispose(loader)
        disposeColors(colors)
        return appearance
def replace(owner: Owner,indicator: Indicator) -> IO(Owner):
  do IO<Owner>:
    appearance : Appearance <- retire(owner)
    create(indicator,appearance)
def dispose(owner: Owner) -> IO(Unit):
  do IO<Unit>:
    discarded : Appearance <- retire(owner)
    return Unit{}

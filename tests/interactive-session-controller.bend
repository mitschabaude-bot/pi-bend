import Base
import ../packages/coding-agent/src/modes/interactive/session-controller.bend as Control
import ../packages/coding-agent/src/modes/interactive/interactive-mode.bend as Interactive
import ../packages/coding-agent/src/modes/interactive/run.bend as Run
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/runtime/src/ref.bend as Ref

type Fake is Data: Fake{started: Chan(String),release: Chan(Unit),seen: Ref.Ref<List<&2,String>>}
def handled(fake: Fake,request: Control.Submission) -> IO(Result<&2,&2,String,Unit>):
  match fake request:
    case Fake{started,release,seen} Control.Submission{+text,_,_}:
      do IO<Result<&2,&2,String,Unit>>:
        sent : Bool <- Chan.send(String,started,text)
        Ref.requireSent(sent)
        ready : Maybe<&1,Unit> <- Chan.recv(Unit,release)
        Ref.modify(List<&2,String>,Unit,seen,old => (text <> old,Unit{}))
        return Bool.pick(Result<&2,&2,String,Unit>,String.eq(text,"two"),Fail{"failed two"},Done{Unit{}})
def accepted(result: Result<&2,&2,Control.SubmitError,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{_}: IO.die(Unit,1,"submission rejected unexpectedly")
def full(result: Result<&2,&2,Control.SubmitError,Unit>) -> IO(Unit):
  match result:
    case Fail{Control.Full{}}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"bounded queue did not reject fourth submission")
def received(input: Maybe<&1,String>,expected: String) -> IO(Unit):
  match input:
    case None{}: IO.die(Unit,1,"worker stopped unexpectedly")
    case Some{value}: Bool.pick(Unit -> IO(Unit),String.eq(value,expected),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"submission order changed"))(Unit{})
def releaseOne(release: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Unit,release,Unit{})
    Ref.requireSent(sent)
def checkedError(value: Maybe<&2,Control.PromptFailure>) -> IO(Unit):
  match value:
    case Some{Control.PromptFailure{message}}: Bool.pick(Unit -> IO(Unit),String.eq(message,"failed two"),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"wrong prompt failure"))(Unit{})
    case None{}: IO.die(Unit,1,"prompt failure was lost")
type Visible is Data:
  Visible{failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
def observedFailure(visible: Visible,value: Control.PromptFailure) -> IO(Unit):
  match visible:
    case Visible{failure,redraw}: Run.promptFailed(Run.WorkerFailure{failure,redraw},value)
def requested(count: Ref.Ref<Nat>,_: Unit) -> IO(Unit):
  Ref.modify(Nat,Unit,count,old => (old + 1n,Unit{}))
def isCount(count: Ref.Ref<Nat>,expected: Nat) -> IO(Unit):
  do IO<Unit>:
    actual : Nat <- Ref.read(Nat,count)
    Bool.pick(Unit -> IO(Unit),Nat.is_eq(actual,expected),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"unexpected redraw count"))(Unit{})
def visible(failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,theme: Theme.Theme,expected: String) -> IO(Unit):
  do IO<Unit>:
    current : Maybe<&2,Interactive.SubmissionFailure> <- Ref.read(Maybe<&2,Interactive.SubmissionFailure>,failure)
    +lines : List<&2,String> <- IO.pure(List<&2,String>,Run.withFailure(Nil{},current,theme,80n))
    # pi-mono f07218c4d interactive-mode.ts:4463 prefixes and colors errors.
    Bool.pick(Unit -> IO(Unit),String.contains(String.join(lines,"\n"),expected),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"failure row missing"))(Unit{})
def hidden(failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>) -> IO(Unit):
  do IO<Unit>:
    current : Maybe<&2,Interactive.SubmissionFailure> <- Ref.read(Maybe<&2,Interactive.SubmissionFailure>,failure)
    Bool.pick(Unit -> IO(Unit),Maybe.is_none(&2,Interactive.SubmissionFailure,current),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"accepted submission did not clear error"))(Unit{})
def loaded(value: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match value:
    case Done{theme}: IO.pure(Theme.Theme,theme)
    case Fail{_}: IO.die(Theme.Theme,1,"theme unavailable")
def scenario(pair: Control.Controller & Control.Handle,+started: Chan(String),+release: Chan(Unit),seen: Ref.Ref<List<&2,String>>,+failure: Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>>,+redrawCount: Ref.Ref<Nat>,stopped: Deferred.Deferred<Unit>,+theme: Theme.Theme) -> IO(Unit):
  match pair:
    case (owner,+handle):
      do IO<Unit>:
        first : Result<&2,&2,Control.SubmitError,Unit> <- Control.submitText(handle,"one")
        accepted(first)
        one : Maybe<&1,String> <- Chan.recv(String,started)
        received(one,"one")
        second : Result<&2,&2,Control.SubmitError,Unit> <- Control.submitText(handle,"two")
        accepted(second)
        third : Result<&2,&2,Control.SubmitError,Unit> <- Control.submitText(handle,"three")
        accepted(third)
        fourth : Result<&2,&2,Control.SubmitError,Unit> <- Control.submitText(handle,"four")
        full(fourth)
        Interactive.submitted(Interactive.SubmissionInput{handle,stopped,failure},"five")
        isCount(redrawCount,0n)
        visible(failure,theme,"Error: Submission queue is full")
        Interactive.submittedResult(failure,Fail{Control.Closed{}})
        visible(failure,theme,"Error: Session is closed")
        Interactive.submittedResult(failure,Done{Unit{}})
        hidden(failure)
        IO.print("accepted while first prompt waited; fourth rejected at capacity")
        releaseOne(release)
        two : Maybe<&1,String> <- Chan.recv(String,started)
        received(two,"two")
        releaseOne(release)
        three : Maybe<&1,String> <- Chan.recv(String,started)
        received(three,"three")
        error : Maybe<&2,Control.PromptFailure> <- Control.lastError(handle)
        checkedError(error)
        isCount(redrawCount,1n)
        visible(failure,theme,"Error: failed two")
        IO.print("FIFO order and prompt failure retained and observed")
        +stopped : Chan(Unit) <- IO.fork(Unit,Control.stop(owner))
        releaseOne(release)
        joined : Maybe<&1,Unit> <- Chan.recv(Unit,stopped)
        Chan.close(Unit,stopped)
        history : List<&2,String> <- Ref.dispose(List<&2,String>,seen)
        Bool.pick(Unit -> IO(Unit),String.eq(String.join(List.reverse(&2,String,history),","),"one,two,three"),_ => IO.print("shutdown joined worker and disposed callbacks"),_ => IO.die(Unit,1,"worker history changed"))(Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    +started : Chan(String) <- Chan.new(String,1)
    +release : Chan(Unit) <- Chan.new(Unit,1)
    +seen : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
    +prompt : Callback.Callback<Control.Submission,Result<&2,&2,String,Unit>> <- Callback.create(~Fake,~Control.Submission,~Result<&2,&2,String,Unit>,~handled,Fake{started,release,seen})
    +failure : Ref.Ref<Maybe<&2,Interactive.SubmissionFailure>> <- Ref.new(Maybe<&2,Interactive.SubmissionFailure>,None{})
    +redrawCount : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +request : Callback.Callback<Unit,Unit> <- Callback.create(~Ref.Ref<Nat>,~Unit,~Unit,~requested,redrawCount)
    +redraw : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,Some{request})
    +stopped : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    loadedTheme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
    +theme : Theme.Theme <- loaded(loadedTheme)
    observer : Callback.Callback<Control.PromptFailure,Unit> <- Callback.create(~Visible,~Control.PromptFailure,~Unit,~observedFailure,Visible{failure,redraw})
    pair : Control.Controller & Control.Handle <- Control.startWithPrompt(prompt,2n,Some{observer})
    scenario(pair,started,release,seen,failure,redrawCount,stopped,theme)
    Chan.close(String,started)
    Chan.close(Unit,release)
    retiredFailure : Maybe<&2,Interactive.SubmissionFailure> <- Ref.dispose(Maybe<&2,Interactive.SubmissionFailure>,failure)
    retiredRedraw : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
    Callback.dispose(Unit,Unit,request)
    retiredCount : Nat <- Ref.dispose(Nat,redrawCount)
    Deferred.dispose(Unit,stopped)

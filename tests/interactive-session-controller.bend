import Base
import ../packages/coding-agent/src/modes/interactive/session-controller.bend as Control
import ../packages/coding-agent/src/modes/interactive/interactive-mode.bend as Interactive
import ../packages/coding-agent/src/modes/interactive/run.bend as Run
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/runtime/src/ref.bend as Ref
import ../packages/coding-agent/src/modes/interactive/transcript.bend as Transcript
import ../packages/coding-agent/src/modes/interactive/viewport.bend as View
import ../packages/coding-agent/src/modes/interactive/theme/markdown-theme.bend as Styles
import ../packages/coding-agent/src/utils/syntax-highlight.bend as SyntaxHighlight
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/components/markdown.bend as Markdown
import ../packages/tui/src/utils.bend as Utils

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
# Failures are reported into the transcript as error rows (pi-mono f07218c4d
# interactive-mode.ts showError: "Error: " and the message, one row per
# report, each requesting a render), so the observed state is the rendered
# transcript document.
type Visible is Data:
  Visible{failure: Interactive.StatusSink,redraw: Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>>}
def observedFailure(visible: Visible,value: Control.PromptFailure) -> IO(Unit):
  match visible:
    case Visible{failure,redraw}: Run.promptFailed(Run.WorkerFailure{failure,redraw},value)
def requested(count: Ref.Ref<Nat>,_: Unit) -> IO(Unit):
  Ref.modify(Nat,Unit,count,old => (old + 1n,Unit{}))
def isCount(count: Ref.Ref<Nat>,expected: Nat) -> IO(Unit):
  do IO<Unit>:
    actual : Nat <- Ref.read(Nat,count)
    Bool.pick(Unit -> IO(Unit),Nat.is_eq(actual,expected),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"unexpected redraw count"))(Unit{})
def plain(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> rest: Utils.stripTerminalSequences(line) ++ "\n" ++ plain(rest)
def occurrences(+text: String,+needle: String,+count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{+head,+rest}: occurrences(rest,needle,Bool.pick(Nat,String.starts_with(SCon{head,rest},needle),count + 1n,count))
def errorRows(document: Component.Component) -> IO(Nat):
  do IO<Nat>:
    lines : List<&2,String> <- Component.render(document,80n)
    return occurrences(plain(lines),"Error: ",0n)
def visible(document: Component.Component,+expected: String) -> IO(Unit):
  do IO<Unit>:
    lines : List<&2,String> <- Component.render(document,80n)
    Bool.pick(Unit -> IO(Unit),String.contains(plain(lines),expected),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"failure row missing: " ++ expected))(Unit{})
def rowsAre(document: Component.Component,+expected: Nat) -> IO(Unit):
  do IO<Unit>:
    rows : Nat <- errorRows(document)
    Bool.pick(Unit -> IO(Unit),Nat.is_eq(rows,expected),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"accepted submission added an error row"))(Unit{})
def loaded(value: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match value:
    case Done{theme}: IO.pure(Theme.Theme,theme)
    case Fail{_}: IO.die(Theme.Theme,1,"theme unavailable")
def scenario(pair: Control.Controller & Control.Handle,+started: Chan(String),+release: Chan(Unit),seen: Ref.Ref<List<&2,String>>,+failure: Interactive.StatusSink,+redrawCount: Ref.Ref<Nat>,stopped: Deferred.Deferred<Unit>,+document: Component.Component) -> IO(Unit):
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
        isCount(redrawCount,1n)
        visible(document,"Error: Submission queue is full")
        Interactive.submittedResult(failure,Fail{Control.Closed{}})
        isCount(redrawCount,2n)
        visible(document,"Error: Session is closed")
        Interactive.submittedResult(failure,Done{Unit{}})
        isCount(redrawCount,2n)
        rowsAre(document,2n)
        IO.print("accepted while first prompt waited; fourth rejected at capacity")
        releaseOne(release)
        two : Maybe<&1,String> <- Chan.recv(String,started)
        received(two,"two")
        releaseOne(release)
        three : Maybe<&1,String> <- Chan.recv(String,started)
        received(three,"three")
        error : Maybe<&2,Control.PromptFailure> <- Control.lastError(handle)
        checkedError(error)
        isCount(redrawCount,3n)
        visible(document,"Error: failed two")
        rowsAre(document,3n)
        IO.print("FIFO order and prompt failure retained and observed")
        +stopped : Chan(Unit) <- IO.fork(Unit,Control.stop(owner))
        releaseOne(release)
        joined : Maybe<&1,Unit> <- Chan.recv(Unit,stopped)
        Chan.close(Unit,stopped)
        history : List<&2,String> <- Ref.dispose(List<&2,String>,seen)
        Bool.pick(Unit -> IO(Unit),String.eq(String.join(List.reverse(&2,String,history),","),"one,two,three"),_ => IO.print("shutdown joined worker and disposed callbacks"),_ => IO.die(Unit,1,"worker history changed"))(Unit{})
def run(+transcript: Transcript.Handle,+document: Component.Component) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(String) <- Chan.new(String,1)
    +release : Chan(Unit) <- Chan.new(Unit,1)
    +seen : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
    +prompt : Callback.Callback<Control.Submission,Result<&2,&2,String,Unit>> <- Callback.create(~Fake,~Control.Submission,~Result<&2,&2,String,Unit>,~handled,Fake{started,release,seen})
    +redrawCount : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +request : Callback.Callback<Unit,Unit> <- Callback.create(~Ref.Ref<Nat>,~Unit,~Unit,~requested,redrawCount)
    +redraw : Ref.Ref<Maybe<&2,Callback.Callback<Unit,Unit>>> <- Ref.new(Maybe<&2,Callback.Callback<Unit,Unit>>,Some{request})
    +failure : Interactive.StatusSink = Interactive.StatusSink{transcript,redraw}
    +stopped : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    observer : Callback.Callback<Control.PromptFailure,Unit> <- Callback.create(~Visible,~Control.PromptFailure,~Unit,~observedFailure,Visible{failure,redraw})
    pair : Control.Controller & Control.Handle <- Control.startWithPrompt(prompt,2n,Some{observer})
    scenario(pair,started,release,seen,failure,redrawCount,stopped,document)
    Chan.close(String,started)
    Chan.close(Unit,release)
    retiredRedraw : Maybe<&2,Callback.Callback<Unit,Unit>> <- Ref.dispose(Maybe<&2,Callback.Callback<Unit,Unit>>,redraw)
    Callback.dispose(Unit,Unit,request)
    retiredCount : Nat <- Ref.dispose(Nat,redrawCount)
    Deferred.dispose(Unit,stopped)

def withTranscript(pair: Transcript.Owner & Transcript.Handle,view: View.View,+document: Component.Component,styles: Styles.Styles) -> IO(Unit):
  match pair:
    case (owner,handle):
      do IO<Unit>:
        run(handle,document)
        Transcript.dispose(owner)
        View.dispose(view)
        Styles.dispose(styles)
def withStyles(pair: Styles.Styles & Markdown.MarkdownTheme,view: View.View,+document: Component.Component,+viewHandle: View.Handle,theme: Theme.Theme) -> IO(Unit):
  match pair:
    case (styles,markdown):
      do IO<Unit>:
        owner : Transcript.Owner <- Transcript.create(viewHandle,theme,markdown)
        withTranscript(Transcript.borrow(owner),view,document,styles)
def withView(pair: View.View & Component.Component & View.Handle,theme: Theme.Theme,styles: Styles.Styles) -> IO(Unit):
  match pair:
    case (view,document,handle): withStyles(Styles.borrow(styles),view,document,handle,theme)
def main() -> IO(Unit):
  do IO<Unit>:
    loadedTheme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
    +theme : Theme.Theme <- loaded(loadedTheme)
    highlighter : SyntaxHighlight.Highlighter <- SyntaxHighlight.create("packages/runtime/data/highlight")
    styles : Styles.Styles <- Styles.create(theme,highlighter)
    view : View.View <- View.create(Component.ComponentId{1n})
    withView(View.borrow(view),theme,styles)

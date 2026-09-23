import Base
import ../packages/coding-agent/src/modes/interactive/session-controller.bend as Control
import ../packages/runtime/src/callback.bend as Callback
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
def scenario(pair: Control.Controller & Control.Handle,+started: Chan(String),+release: Chan(Unit),seen: Ref.Ref<List<&2,String>>) -> IO(Unit):
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
        IO.print("accepted while first prompt waited; fourth rejected at capacity")
        releaseOne(release)
        two : Maybe<&1,String> <- Chan.recv(String,started)
        received(two,"two")
        releaseOne(release)
        three : Maybe<&1,String> <- Chan.recv(String,started)
        received(three,"three")
        error : Maybe<&2,Control.PromptFailure> <- Control.lastError(handle)
        checkedError(error)
        IO.print("FIFO order and prompt failure retained")
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
    pair : Control.Controller & Control.Handle <- Control.startWithPrompt(prompt,2n)
    scenario(pair,started,release,seen)
    Chan.close(String,started)
    Chan.close(Unit,release)

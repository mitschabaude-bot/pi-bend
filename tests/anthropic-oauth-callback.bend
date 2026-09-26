import Base
import ../packages/ai/src/auth/oauth/browser.bend as OAuth
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deferred.bend as Deferred

def manual(answer: Deferred.Deferred<OAuth.CodeResult()>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(100)
    settled : Bool <- Deferred.resolve(OAuth.CodeResult(),answer,Done{"manual"})
    return Unit{}
def cancelMode(mode: String,answer: Deferred.Deferred<OAuth.CodeResult()>) -> IO(Maybe<&1,Chan(Unit)>):
  match mode:
    case "manual":
      do IO<Maybe<&1,Chan(Unit)>>:
        task : Chan(Unit) <- IO.fork(Unit,manual(answer))
        return Some{task}
    case _: IO.pure(Maybe<&1,Chan(Unit)>,None{})
def joinManual(task: Maybe<&1,Chan(Unit)>) -> IO(Unit):
  match task:
    case None{}: IO.pure(Unit,Unit{})
    case Some{work}: IO.join(Unit,work)
def printResult(result: OAuth.CodeResult()) -> IO(Unit):
  match result:
    case Done{value}: IO.print(value)
    case Fail{error}: IO.die(Unit,1,error)
def run(listener: Listener,mode: String) -> IO(Unit):
  do IO<Unit>:
    +answer : Deferred.Deferred<OAuth.CodeResult()> <- Deferred.new(OAuth.CodeResult())
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    worker : Chan(Unit) <- IO.fork(Unit,OAuth.callbackRun(OAuth.Listening{listener},answer,OAuth.CallbackConfig{"http://localhost:53692/callback","/callback","state_test"},Abort.signal(Unit,controller)))
    cancel : Maybe<&1,Chan(Unit)> <- cancelMode(mode,answer)
    result : OAuth.CodeResult() <- Deferred.result(OAuth.CodeResult(),answer)
    IO.join(Unit,worker)
    joinManual(cancel)
    Deferred.dispose(OAuth.CodeResult(),answer)
    Abort.dispose(Unit,controller)
    printResult(result)
def started(result: Result<&1,&1,U32 & String,Listener>,mode: String) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"could not bind callback")
    case Done{listener}: run(listener,mode)
def modeOf(args: List<String>) -> String:
  match args:
    case mode <> _: mode
    case Nil{}: "browser"
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    mode : String <- IO.pure(String,modeOf(args))
    listener : Result<&1,&1,U32 & String,Listener> <- OAuth.listenCallback(53692)
    started(listener,mode)

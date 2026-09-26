import Base
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/auth/oauth/browser.bend as Browser
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/deferred.bend as D

type PromptState is Data: PromptState{mode: String, parent: Abort.AbortController<Unit>}
def observed(ticket: D.Observation<Abort.AbortReason<Unit>>) -> IO(Browser.CodeResult()):
  match ticket:
    case D.Observation{waiter,_}:
      do IO<Browser.CodeResult()>:
        value : Maybe<&2,Abort.AbortReason<Unit>> <- D.wait(Maybe<&2,Abort.AbortReason<Unit>>,waiter)
        return Fail{"Login cancelled"}
def prompt(state: PromptState,input: Auth.AuthPrompt) -> IO(Browser.CodeResult()):
  match state input:
    case PromptState{"manual",_} _: IO.pure(Browser.CodeResult(),Done{"manual_code#test_state"})
    case PromptState{"error",_} _: IO.pure(Browser.CodeResult(),Fail{"prompt failed"})
    case PromptState{"wrong-state",_} _: IO.pure(Browser.CodeResult(),Done{"manual_code#wrong"})
    case PromptState{"cancel",parent} Auth.ManualCodePrompt{_,_,Some{signal}}:
      do IO<Browser.CodeResult()>:
        stop : Bool <- Abort.abort(Unit,parent,None{})
        ticket : D.Observation<Abort.AbortReason<Unit>> <- Abort.observe(Unit,signal)
        observed(ticket)
    case _ Auth.ManualCodePrompt{_,_,Some{signal}}:
      do IO<Browser.CodeResult()>:
        ticket : D.Observation<Abort.AbortReason<Unit>> <- Abort.observe(Unit,signal)
        observed(ticket)
    case _ _: IO.pure(Browser.CodeResult(),Fail{"Expected cancellable manual prompt"})
def notify(_: Unit,event: Auth.AuthEvent) -> IO(Unit):
  match event:
    case Auth.AuthUrlEvent{url,_}: IO.print("ready " ++ url)
    case _: IO.die(Unit,1,"Expected authorization URL")
def report(result: Browser.CodeResult()) -> IO(Unit):
  match result:
    case Done{code}: IO.print("code " ++ code)
    case Fail{error}: IO.print("error " ++ error)
def mode(args: List<String>) -> String:
  match args:
    case value <> _: value
    case Nil{}: "browser"
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +parent : Abort.AbortController<Unit> <- Abort.new(Unit)
    +input : C.Callback<Auth.AuthPrompt,Browser.CodeResult()> <- C.create(~PromptState,~Auth.AuthPrompt,~Browser.CodeResult(),~prompt,PromptState{mode(args),parent})
    +notice : C.Callback<Auth.AuthEvent,Unit> <- C.create(~Unit,~Auth.AuthEvent,~Unit,~notify,Unit{})
    listener : Result<&1,&1,U32 & String,Listener> <- TCP.listen_host("127.0.0.1",53693)
    result : Browser.CodeResult() <- Browser.promptCode(Browser.CallbackConfig{"http://localhost:53693/auth/callback","/auth/callback","test_state"},listener,Auth.ProviderAuthInteraction{Abort.signal(Unit,parent),input,notice},"https://example.test/authorize","Complete browser login or paste a code:","Complete login in your browser.")
    C.dispose(Auth.AuthPrompt,Browser.CodeResult(),input)
    C.dispose(Auth.AuthEvent,Unit,notice)
    Abort.dispose(Unit,parent)
    report(result)

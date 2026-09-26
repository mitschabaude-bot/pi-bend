import Base
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/runtime/src/abort.bend as Abort
import ../packages/coding-agent/src/modes/interactive/components/login-dialog.bend as Login
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/record.bend as Record
import ../packages/runtime/src/word-segmenter.bend as Words
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/components/input.bend as Input
import ../packages/tui/src/keybindings.bend as Bindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/tui/src/utils.bend as Utils

def check(valid: Bool,message: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),valid,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,message))(Unit{})
def empty(_: Unit,_: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,Nil{})
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def cancel(counter: Ref.Ref<Nat>,_: Unit) -> IO(Unit): Ref.modify(Nat,Unit,counter,n => (Succ{n},Unit{}))
def state(host: Login.Host) -> IO(Login.State):
  match host: case Login.Host{current,_,_,_,_,_,_,_,_}: Ref.read(Login.State,current)
def value(current: Login.State) -> String:
  match current:
    case Login.Prompt{_,_,_,input}: Input.getValue(input)
    case Login.Manual{_,input}: Input.getValue(input)
    case _: ""
def waiting(current: Login.State) -> Bool:
  match current: case Login.Waiting{}: True{} case _: False{}
def send(+host: Login.Host,keys: List<&2,String>) -> IO(Unit):
  match keys:
    case Nil{}: IO.pure(Unit,Unit{})
    case key <> rest:
      do IO<Unit>:
        Login.receive(host,key)
        send(host,rest)
def testPrompt(+host: Login.Host) -> IO(Unit):
  do IO<Unit>:
    +answer : Deferred.Deferred<String> <- Deferred.new(String)
    Login.showPrompt(host,"Login to OpenAI","Enter OpenAI API key:",True{},answer)
    # Paste markers and payload can arrive in separate reads. Enter in a paste
    # is data, so it must not submit the incomplete key.
    send(host,["\u{1b}[200~sk-","parity\n","new\u{1b}[201~"])
    initial : Login.State <- state(host)
    check(String.eq(value(initial),"sk-paritynew"),"bracketed paste preserves the key and removes embedded newlines as upstream Input does")
    send(host,["\u{1b}[D","\u{1b}[D","\u{7f}","\u{1b}[F","!"])
    edited : Login.State <- state(host)
    check(String.eq(value(edited),"sk-parityew!"),"left/backspace/end edit the stored key at its cursor")
    +lines : List<&2,String> <- Login.draw(host,12n)
    +rendered : String <- IO.pure(String,Utils.stripTerminalSequences(String.join(lines,"\n")))
    check(Bool.not(String.contains(rendered,"sk-parity")) && String.contains(rendered,"•"),"secret rendering masks the value while retaining a visible cursor")
    Login.receive(host,"\r")
    submitted : String <- Deferred.result(String,answer)
    check(String.eq(submitted,"sk-parityew!"),"submission returns the actual value, not its masked presentation")
    after : Login.State <- state(host)
    check(waiting(after),"the input result cannot overwrite the submission's phase change")
    Deferred.dispose(String,answer)
def testManual(+host: Login.Host,+counter: Ref.Ref<Nat>) -> IO(Unit):
  do IO<Unit>:
    +answer : Deferred.Deferred<String> <- Deferred.new(String)
    Login.showManual(host,"https://example.test/authorize",answer)
    send(host,["\u{1b}[200~http://localhost/callback?code=abc&state=test\u{1b}[201~","\u{1b}[H","x","\u{1b}[D","\u{1b}[3~"])
    current : Login.State <- state(host)
    check(String.eq(value(current),"http://localhost/callback?code=abc&state=test"),"pasted redirect URLs support home and forward delete")
    Login.receive(host,"\u{1b}")
    canceled : Nat <- Ref.read(Nat,counter)
    check(Nat.is_eq(canceled,1n),"escape still calls the login cancellation callback")
    Login.close(host)
    Deferred.dispose(String,answer)
def testWords(+host: Login.Host) -> IO(Unit):
  do IO<Unit>:
    +answer : Deferred.Deferred<String> <- Deferred.new(String)
    Login.showPrompt(host,"Login","Account:",False{},answer)
    send(host,["one two","\u{17}"])
    deleted : Login.State <- state(host)
    check(String.eq(value(deleted),"one "),"word deletion uses the shared Unicode word-navigation engine")
    Login.receive(host,"\u{19}")
    restored : Login.State <- state(host)
    check(String.eq(value(restored),"one two"),"yank restores the deleted word")
    Login.close(host)
    Deferred.dispose(String,answer)
def doneText(result: Result<&2,&2,String,String>) -> String:
  match result:
    case Done{text}: text
    case Fail{message}: "error:" ++ message
def testAuth(+host: Login.Host) -> IO(Unit):
  do IO<Unit>:
    +whole : Abort.AbortController<Unit> <- Abort.new(Unit)
    Login.openDirect(host)
    Login.notify(host,"Login to Example",Auth.AuthUrlEvent{"https://example.test/authorize?state=keep",Some{"Continue in your browser"}})
    +manualAnswer : Deferred.Deferred<String> <- Deferred.new(String)
    Login.showAuthPrompt(host,"Login to Example",Auth.ManualCodePrompt{"Paste the redirect URL",None{},None{}},manualAnswer)
    +rows : List<&2,String> <- Login.draw(host,24n)
    check(String.contains(String.join(rows,"\n"),"\u{1b}]8;;https://example.test/authorize?state=keep\u{7}"),"manual prompts preserve the full authorization hyperlink")
    send(host,["\u{1b}[200~http://localhost/callback?code=done\u{1b}[201~","\r"])
    submitted : Result<&2,&2,String,String> <- Login.awaitAuthAnswer(manualAnswer,Abort.signal(Unit,whole),None{})
    check(String.eq(doneText(submitted),"http://localhost/callback?code=done"),"generic manual-code prompts return pasted input")
    Login.finishAuthPrompt(host,None{})
    Deferred.dispose(String,manualAnswer)
    +previous : Login.State <- Login.authState(host)
    +selection : Deferred.Deferred<String> <- Deferred.new(String)
    Login.showAuthPrompt(host,"Login to Example",Auth.SelectPrompt{"Choose login method",[Auth.AuthSelectOption{"browser","Browser",None{}},Auth.AuthSelectOption{"device_code","Headless",None{}}],None{}},selection)
    send(host,["\u{1b}[B","\r"])
    chosen : Result<&2,&2,String,String> <- Login.awaitAuthAnswer(selection,Abort.signal(Unit,whole),None{})
    check(String.eq(doneText(chosen),"device_code"),"selection returns the option id rather than its label")
    Login.finishAuthPrompt(host,Some{previous})
    Deferred.dispose(String,selection)
    Login.notify(host,"Login to Example",Auth.InfoEvent{"Account selected",[Auth.AuthInfoLink{"https://example.test/account",Some{"Account"}}]})
    Login.notify(host,"Login to Example",Auth.ProgressEvent{"Exchanging code"})
    +displayed : List<&2,String> <- Login.draw(host,100n)
    +text : String = String.join(displayed,"\n")
    check(String.contains(text,"https://example.test/authorize?state=keep") && String.contains(text,"Account selected") && String.contains(text,"Exchanging code"),"selection restoration and notifications retain the preceding login content")
    +local : Abort.AbortController<Unit> <- Abort.new(Unit)
    +pending : Deferred.Deferred<String> <- Deferred.new(String)
    Login.showAuthPrompt(host,"Login to Example",Auth.TextPrompt{"Temporary prompt",Some{"Account name"},Some{Abort.signal(Unit,local)}},pending)
    worker : Chan(Result<&2,&2,String,String>) <- IO.fork(Result<&2,&2,String,String>,Login.awaitAuthAnswer(pending,Abort.signal(Unit,whole),Some{Abort.signal(Unit,local)}))
    won : Bool <- Abort.abort(Unit,local,None{})
    rejected : Result<&2,&2,String,String> <- IO.join(Result<&2,&2,String,String>,worker)
    check(String.eq(doneText(rejected),"error:Login cancelled"),"per-prompt cancellation rejects its pending input")
    unchanged : Bool <- Abort.aborted(Unit,Abort.signal(Unit,whole))
    check(Bool.not(unchanged),"per-prompt cancellation does not abort the provider login")
    Login.finishAuthPrompt(host,None{})
    Deferred.dispose(String,pending)
    Abort.dispose(Unit,local)
    Abort.dispose(Unit,whole)
    Login.close(host)
def selectedApi(selection: Maybe<&2,Login.ProviderSelection>) -> Bool:
  match selection:
    case Some{Login.ProviderSelection{"example",Auth.ApiKeyType{}}}: True{}
    case _: False{}
def testProviderSelector(+host: Login.Host) -> IO(Unit):
  do IO<Unit>:
    +choices : List<&2,Login.Choice> = [
      Login.Choice{Login.AuthChoice{Login.ProviderSelection{"example",Auth.OAuthType{}}},"Example"," • unconfigured","Example example oauth Account"},
      Login.Choice{Login.AuthChoice{Login.ProviderSelection{"example",Auth.ApiKeyType{}}},"Example"," ✓ configured","Example example api_key Token"}]
    +answer : Deferred.Deferred<Maybe<&2,Login.ProviderSelection>> <- Login.openAuthMenu(host,Login.Provider{},"Select provider to configure:",choices,"")
    rows : List<&2,String> <- Login.draw(host,80n)
    +text : String = Utils.stripTerminalSequences(String.join(rows,"\n"))
    check(String.contains(text,"[subscription]") && String.contains(text,"[API key]"),"mixed menus distinguish methods for the same provider")
    send(host,["Token"])
    filteredRows : List<&2,String> <- Login.draw(host,80n)
    check(String.contains(Utils.stripTerminalSequences(String.join(filteredRows,"\n")),"[API key]"),"auth labels survive filtering to one method")
    Login.receive(host,"\r")
    selection : Maybe<&2,Login.ProviderSelection> <- Deferred.result(Maybe<&2,Login.ProviderSelection>,answer)
    check(selectedApi(selection),"selection retains both provider identity and auth type")
    Deferred.dispose(Maybe<&2,Login.ProviderSelection>,answer)
    +cancelled : Deferred.Deferred<Maybe<&2,Login.ProviderSelection>> <- Login.openAuthMenu(host,Login.Provider{},"Select provider to configure:",choices,"missing")
    emptyRows : List<&2,String> <- Login.draw(host,80n)
    check(String.contains(Utils.stripTerminalSequences(String.join(emptyRows,"\n")),"No matching providers"),"unknown direct names remain searchable instead of rejecting the dialog")
    handled : Bool <- Login.cancelSelector(host)
    check(handled,"selector cancellation is handled without aborting a provider operation")
    result : Maybe<&2,Login.ProviderSelection> <- Deferred.result(Maybe<&2,Login.ProviderSelection>,cancelled)
    check(Maybe.is_none(&2,Login.ProviderSelection,result),"cancelled provider selections have no fabricated provider id")
    Deferred.dispose(Maybe<&2,Login.ProviderSelection>,cancelled)
    Login.close(host)
def exercise(pair: Login.Owner & Login.Host & Component.Component,counter: Ref.Ref<Nat>) -> IO(Unit):
  match pair:
    case (owner,+host,_):
      do IO<Unit>:
        testPrompt(host)
        testManual(host,counter)
        testWords(host)
        testAuth(host)
        testProviderSelector(host)
        Login.dispose(owner)
def main() -> IO(Unit):
  do IO<Unit>:
    +theme : Ref.Ref<Theme.Theme> <- Ref.new(Theme.Theme,Theme.create("test",Color.TrueColor{},Record.new(Color.Color),Record.new(Color.Color)))
    +counter : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +onCancel : Callback.Callback<Unit,Unit> <- Callback.create(~Ref.Ref<Nat>,~Unit,~Unit,~cancel,counter)
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Unit,~Nat,~List<&2,String>,~empty,Unit{})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    bindings : Bindings.KeybindingsManager <- IO.pure(Bindings.KeybindingsManager,Bindings.create(Bindings.TUI_KEYBINDINGS(),Record.new(List<&2,Keys.KeyId>)))
    owner : Login.Owner <- Login.create(Component.Component{Component.ComponentId{1n},render,None{},None{},invalidate,None{},False{}},theme,Words.Pending{"packages/runtime/data"},bindings,Keys.defaults(),onCancel)
    exercise(Login.borrow(owner),counter)
    Callback.dispose(Unit,Unit,onCancel)
    Callback.dispose(Nat,List<&2,String>,render)
    Callback.dispose(Unit,Unit,invalidate)
    unused : Theme.Theme <- Ref.dispose(Theme.Theme,theme)
    discarded : Nat <- Ref.dispose(Nat,counter)
    IO.print("login input: paste, cursor editing, masking, submission and cancellation passed")

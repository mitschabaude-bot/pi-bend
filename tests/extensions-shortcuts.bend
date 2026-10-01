import Base

# Shortcut-conflict cases from pi-mono test/extensions-runner.test.ts.
# Factories are native Bend; assertions include warning reset and retained snapshots.
import ../packages/coding-agent/src/core/extensions/runner.bend as Runner
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/types.bend as T
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/coding-agent/src/core/keybindings.bend as App
import ../packages/coding-agent/src/core/diagnostics.bend as D
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/record.bend as R
import ../packages/tui/src/keys.bend as K
import ../packages/tui/src/keybindings.bend as B
import ./model-runtime-fixture.bend as Models
import ../packages/coding-agent/src/core/model-runtime.bend as ModelRuntime

def check(ok: Bool,+name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),ok,_ => IO.print("ok " ++ name),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def noop(_: Unit,ctx: Ctx.ExtensionContext) -> IO(Result<&2,&2,String,Unit>): IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}})
def register(+key: String,api: T.ExtensionAPI) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    handler : T.ShortcutHandler() <- C.create(~Unit,~Ctx.ExtensionContext,~Result<&2,&2,String,Unit>,~noop,Unit{})
    Loader.registerShortcut(api,key,T.ShortcutOptions{None{},handler})
def extension(path: String,+key: String) -> IO(T.InlineExtension):
  do IO<T.InlineExtension>:
    +factory : T.ExtensionFactory() <- C.create(~String,~T.ExtensionAPI,~Result<&2,&2,String,Unit>,~(environment => api => register(environment,api)),key)
    return T.InlineExtension{path,factory,False{}}
def loaded(+extensions: List<&2,T.InlineExtension>) -> IO(Runner.ExtensionRunner):
  do IO<Runner.ExtensionRunner>:
    +runtime : T.ExtensionRuntime() <- Loader.createExtensionRuntime()
    errors : List<&2,T.LoadError> <- Loader.loadExtensionFactories(runtime,extensions)
    Loader.disposeInlineExtensions(extensions)
    models : ModelRuntime.ModelRuntime <- Models.create(Nil{})
    Runner.create(runtime,"/tmp/pi-shortcuts",models)
def key(value: Maybe<&2,K.KeyId>) -> K.KeyId:
  match value:
    case Some{found}: found
    case None{}: K.KeyId{K.Escape{},K.Modifiers{False{},False{},False{},False{}}}
def keys(values: List<&2,String>) -> List<&2,K.KeyId>:
  match values:
    case Nil{}: Nil{}
    case text <> rest: key(K.parseKeyId(text)) <> keys(rest)
def binding(config: B.KeybindingsConfig(),action: String,texts: List<&2,String>) -> B.KeybindingsConfig(): R.set(List<&2,K.KeyId>,config,action,keys(texts))
def defaults() -> B.KeybindingsConfig(): B.getResolvedBindings(B.create(App.KEYBINDINGS(App.Environment{"linux",None{},None{}}),R.new(List<&2,K.KeyId>)))
def present(value: Maybe<&2,T.ExtensionShortcut>) -> Bool:
  match value: case Some{_}: True{} case None{}: False{}
def warningText(values: List<&2,D.ResourceDiagnostic>) -> String:
  match values: case Nil{}: "" case D.ResourceDiagnostic{_,text,_,_} <> rest: text ++ "\n" ++ warningText(rest)
def assertion(+shortcut: String,config: B.KeybindingsConfig(),expected: Bool,+needle: String,name: String) -> IO(Unit):
  do IO<Unit>:
    first : T.InlineExtension <- extension("test",shortcut)
    +runner : Runner.ExtensionRunner <- loaded([first])
    +result : R.Record<T.ExtensionShortcut> <- Runner.getShortcuts(runner,config)
    +warnings : List<&2,D.ResourceDiagnostic> <- Runner.getShortcutDiagnostics(runner)
    check(Bool.pick(Bool,expected,present(R.get(T.ExtensionShortcut,result,Runner.shortcutName(shortcut))),Bool.not(present(R.get(T.ExtensionShortcut,result,Runner.shortcutName(shortcut))))) && Bool.pick(Bool,String.is_empty(needle),Bool.not(String.contains(warningText(warnings),"conflicts with built-in")),String.contains(warningText(warnings),needle)),name)
    Runner.dispose(runner)
def winner(value: Maybe<&2,T.ExtensionShortcut>) -> String:
  match value: case None{}: "" case Some{shortcut}: Runner.shortcutPath(shortcut)
def duplicateShortcuts() -> IO(Unit):
  do IO<Unit>:
    first : T.InlineExtension <- extension("first","ctrl+shift+x")
    last : T.InlineExtension <- extension("last","CTRL+SHIFT+X")
    +runner : Runner.ExtensionRunner <- loaded([first,last])
    selected : R.Record<T.ExtensionShortcut> <- Runner.getShortcuts(runner,R.new(List<&2,K.KeyId>))
    +warnings : List<&2,D.ResourceDiagnostic> <- Runner.getShortcutDiagnostics(runner)
    check(String.eq(winner(R.get(T.ExtensionShortcut,selected,Runner.shortcutName("ctrl+shift+x"))),"<inline:last>") && String.contains(warningText(warnings),"registered by both"),"warns when two extensions register same shortcut")
    blocked : R.Record<T.ExtensionShortcut> <- Runner.getShortcuts(runner,binding(R.new(List<&2,K.KeyId>),"app.clear",["ctrl+shift+x"]))
    next : List<&2,D.ResourceDiagnostic> <- Runner.getShortcutDiagnostics(runner)
    check(Nat.is_eq(List.length(&2,D.ResourceDiagnostic,next),2n) && Nat.is_eq(List.length(&2,D.ResourceDiagnostic,warnings),1n),"resolving again replaces diagnostics and preserves earlier snapshots")
    Runner.dispose(runner)
def main() -> IO(Unit):
  do IO<Unit>:
    assertion("ctrl+c",defaults(),False{},"conflicts with built-in","warns when extension shortcut conflicts with built-in")
    assertion("ctrl+p",binding(defaults(),"app.model.cycleForward",["ctrl+n"]),True{},"","allows a shortcut when the reserved set no longer contains the default key")
    assertion("ctrl+v",defaults(),True{},"built-in shortcut for app.clipboard.pasteImage","warns but allows when extension uses non-reserved built-in shortcut")
    assertion("ctrl+x",binding(defaults(),"app.model.cycleForward",["ctrl+x"]),False{},"conflicts with built-in","blocks shortcuts for reserved actions even when rebound")
    assertion("ctrl+p",defaults(),False{},"conflicts with built-in","blocks shortcuts when a key is shared by reserved and non-reserved actions")
    assertion("ctrl+y",binding(defaults(),"app.clear",["ctrl+x","ctrl+y"]),False{},"conflicts with built-in","blocks shortcuts when reserved action has multiple keys")
    assertion("ctrl+y",binding(defaults(),"app.clipboard.pasteImage",["ctrl+x","ctrl+y"]),True{},"built-in shortcut for app.clipboard.pasteImage","warns but allows when non-reserved action has multiple keys")
    duplicateShortcuts()
    assertion("ctrl+x",binding(binding(R.new(List<&2,K.KeyId>),"app.clear",["ctrl+x"]),"app.clipboard.pasteImage",["ctrl+x"]),False{},"conflicts with built-in","reserved binding dominates a later non-reserved binding")
    assertion("ctrl+x",binding(binding(R.new(List<&2,K.KeyId>),"app.clipboard.pasteImage",["ctrl+x"]),"app.clear",["ctrl+x"]),False{},"conflicts with built-in","reserved binding dominates an earlier non-reserved binding")

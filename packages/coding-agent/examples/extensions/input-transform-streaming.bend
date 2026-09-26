import Base
import ../../src/core/extensions/types.bend as Ext
import ../../src/core/extensions/loader.bend as Loader
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/ecma-regex.bend as Re
import ../../../runtime/src/text.bend as Text

# pi v0.87.1 examples/extensions/input-transform-streaming.ts: a
# streaming-aware input gate. When the input mentions changes and is not a
# steering message, `git diff --stat` is appended; during steering the exec
# is skipped so the correction reaches the model at once.

def Reply() -> Data: Result<&2, &2, String, Maybe<&2, Ext.InputEventResult>>

def continued() -> Reply(): Done{Some{Ext.InputContinue{}}}

def triggered(+text: String) -> Bool:
  Result.default(&2, &2, Re.Error, Bool, Result.map(&2, &2, Re.Error, Re.RegExp, Bool, regex => Re.test(regex, text), Re.compile("\\b(changes?|diff|modified)\\b", "i")), False{})

def withChanges(+text: String, result: Loader.ExecResult) -> Reply():
  match result:
    case Loader.ExecResult{stdout, _, code, _}:
      +changes = Text.trim(stdout)
      Bool.pick(Reply(), U32.is_eq(code, 0) && Bool.not(String.is_empty(changes)), Done{Some{Ext.InputTransform{text ++ "\n\nCurrent uncommitted changes:\n```\n" ++ changes ++ "\n```", None{}}}}, continued())

def gated(+api: Ext.ExtensionAPI, +text: String) -> IO(Reply()):
  Bool.pick(Unit -> IO(Reply()), triggered(text),
    _ => IO.bind(Loader.ExecResult, Reply(), Loader.exec(api, "git", ["diff", "--stat"], Loader.noExecOptions()), result => IO.pure(Reply(), withChanges(text, result))),
    _ => IO.pure(Reply(), continued()))(Unit{})

def onInput(api: Ext.ExtensionAPI, call: Ext.HandlerCall<Ext.InputEvent>) -> IO(Reply()):
  match call:
    case Ext.HandlerCall{Ext.InputEvent{_, _, _, Some{Ext.UserSteer{}}}, _}: IO.pure(Reply(), continued())
    case Ext.HandlerCall{Ext.InputEvent{text, _, _, _}, _}: gated(api, text)

def subscribe(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.InputEvent, Ext.InputEventResult) <- C.create(~Ext.ExtensionAPI, ~Ext.HandlerCall<Ext.InputEvent>, ~Reply(), ~onInput, api)
    subscribed : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnInput{handler})
    return Result.map(&2, &2, String, Loader.Unsubscribe, Unit, done => Unit{}, subscribed)

def inputTransformStreaming(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): subscribe(api)

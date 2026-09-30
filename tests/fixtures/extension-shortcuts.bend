import Base
import ../../packages/coding-agent/src/core/extensions/types.bend as T
import ../../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../../packages/runtime/src/callback.bend as C

def immediate(_: Unit,context: Ctx.ExtensionContext) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    Ctx.setEditorText(context,"SHORTCUT-OK")
    return Done{Unit{}}
def delayed(_: Unit,context: Ctx.ExtensionContext) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    IO.sleep(1000)
    Ctx.setEditorText(context,"ASYNC-OK")
    return Done{Unit{}}
def failed(_: Unit,context: Ctx.ExtensionContext) -> IO(Result<&2,&2,String,Unit>):
  IO.pure(Result<&2,&2,String,Unit>,Fail{"shortcut fixture failure"})
def extension(+api: T.ExtensionAPI) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    immediate : T.ShortcutHandler() <- C.create(~Unit,~Ctx.ExtensionContext,~Result<&2,&2,String,Unit>,~immediate,Unit{})
    delayed : T.ShortcutHandler() <- C.create(~Unit,~Ctx.ExtensionContext,~Result<&2,&2,String,Unit>,~delayed,Unit{})
    failed : T.ShortcutHandler() <- C.create(~Unit,~Ctx.ExtensionContext,~Result<&2,&2,String,Unit>,~failed,Unit{})
    a : Result<&2,&2,String,Unit> <- Loader.registerShortcut(api,"ctrl+v",T.ShortcutOptions{None{},immediate})
    b : Result<&2,&2,String,Unit> <- Loader.registerShortcut(api,"ctrl+o",T.ShortcutOptions{None{},delayed})
    Loader.registerShortcut(api,"ctrl+g",T.ShortcutOptions{None{},failed})

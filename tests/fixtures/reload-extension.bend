import Base
import ../../packages/runtime/src/callback.bend as C
import ../../packages/runtime/src/filesystem.bend as FS
import ../../packages/runtime/src/utf8.bend as Utf8
import ../../packages/coding-agent/src/core/extensions/types.bend as T
import ../../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../../packages/coding-agent/src/core/extensions/context.bend as Ctx

# The tag is read at factory execution, not at event or command dispatch.
# Editing it distinguishes a rebuilt generation from retained registrations.
def started(tag: String,call: T.HandlerCall<T.SessionStartEvent>) -> IO(Result<&2,&2,String,Maybe<&2,Unit>>):
  match call:
    case T.HandlerCall{_,ctx}:
      do IO<Result<&2,&2,String,Maybe<&2,Unit>>>:
        Ctx.setStatus(ctx,"reload-probe",Some{"factory-" ++ tag})
        return Done{None{}}
def commanded(tag: String,call: T.CommandCall) -> IO(Result<&2,&2,String,Unit>):
  match call:
    case T.CommandCall{_,ctx}:
      do IO<Result<&2,&2,String,Unit>>:
        Ctx.setStatus(Ctx.commandContext(ctx),"reload-probe",Some{"command-" ++ tag})
        return Done{Unit{}}
def tagOf(result: Result<&2,&2,FS.Error,Result<&2,&2,Utf8.Error,String>>) -> Result<&2,&2,String,String>:
  match result:
    case Done{Done{tag}}: Done{tag}
    case _: Fail{"Cannot read reload-tag.txt"}
def registered(+api: T.ExtensionAPI,+tag: String) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    start : T.ExtensionHandler(T.SessionStartEvent,Unit) <- C.create(~String,~T.HandlerCall<T.SessionStartEvent>,~Result<&2,&2,String,Maybe<&2,Unit>>,~started,tag)
    subscription : Result<&2,&2,String,Loader.Unsubscribe> <- Loader.on(api,T.OnSessionStart{start})
    command : T.CommandHandler() <- C.create(~String,~T.CommandCall,~Result<&2,&2,String,Unit>,~commanded,tag)
    Loader.registerCommand(api,"reload-probe",T.CommandOptions{None{},None{},command})
def loaded(api: T.ExtensionAPI,result: Result<&2,&2,String,String>) -> IO(Result<&2,&2,String,Unit>):
  match result:
    case Fail{message}: IO.pure(Result<&2,&2,String,Unit>,Fail{message})
    case Done{tag}: registered(api,tag)
def extension(+api: T.ExtensionAPI) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    contents : Result<&2,&2,FS.Error,Result<&2,&2,Utf8.Error,String>> <- FS.readUtf8("reload-tag.txt")
    loaded(api,tagOf(contents))

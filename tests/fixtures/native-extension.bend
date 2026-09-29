import Base
import ../../packages/coding-agent/src/core/extensions/types.bend as Ext
import ../../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../../packages/runtime/src/callback.bend as Callback

def command(state: Unit, call: Ext.CommandCall) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    IO.print_err("native-extension-invoked")
    return Done{Unit{}}

def extension(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.CommandHandler() <- Callback.create(~Unit, ~Ext.CommandCall, ~Result<&2, &2, String, Unit>, ~command, Unit{})
    Loader.registerCommand(api, "native-check", Ext.CommandOptions{Some{"Native extension smoke check"}, None{}, handler})

import Base
import ./auth-storage.bend as Fixture
import ../packages/coding-agent/src/core/auth-storage.bend as Storage
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C

type Context is Data:
  Context{mode: String,controller: Abort.AbortController<Unit>}
def cancel(controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    won : Bool <- Abort.abort(Unit,controller,None{})
    return Unit{}
def later(controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(30)
    cancel(controller)
def update(context: Context,current: Maybe<&2,Auth.Credential>) -> IO(Auth.StoreResult(Maybe<&2,Auth.Credential>)):
  match context:
    case Context{+mode,+controller}:
      do IO<Auth.StoreResult(Maybe<&2,Auth.Credential>)>:
        IO.print("entered")
        IO.sleep(200)
        Bool.pick(Unit -> IO(Unit),String.eq(mode,"cancel") || String.eq(mode,"unchanged-cancel"),_ => cancel(controller),_ => IO.pure(Unit,Unit{}))(Unit{})
        return Done{Bool.pick(Maybe<&2,Auth.Credential>,String.eq(mode,"unchanged-cancel"),None{},Some{Auth.ApiKeyCredential{Some{"replacement"},None{}}})}
def modify(+mode: String,storage: Storage.AuthStorage,+controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    +callback : Auth.Modification() <- C.create(~Context,~Maybe<&2,Auth.Credential>,~(Auth.StoreResult(Maybe<&2,Auth.Credential>)),~update,Context{mode,controller})
    Bool.pick(Unit -> IO(Unit),String.eq(mode,"preabort"),_ => cancel(controller),_ => IO.pure(Unit,Unit{}))(Unit{})
    task : Chan(Unit) <- IO.fork(Unit,Bool.pick(Unit -> IO(Unit),String.eq(mode,"wait-cancel"),_ => later(controller),_ => IO.pure(Unit,Unit{}))(Unit{}))
    result : Auth.StoreResult(Maybe<&2,Auth.Credential>) <- Storage.modify(storage,"target",callback,Some{Abort.signal(Unit,controller)})
    IO.join(Unit,task)
    C.dispose(Maybe<&2,Auth.Credential>,Auth.StoreResult(Maybe<&2,Auth.Credential>),callback)
    IO.print(Fixture.outcome(Maybe<&2,Auth.Credential>,Fixture.credentialValue,result))
def opened(mode: String,pair: Storage.AuthStorageOwner & Storage.AuthStorage) -> IO(Unit):
  match pair:
    case (owner,storage):
      do IO<Unit>:
        +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
        modify(mode,storage,controller)
        Abort.dispose(Unit,controller)
        Storage.dispose(owner)
def run(args: List<String>) -> IO(Unit):
  match args:
    case mode <> path <> Nil{}:
      do IO<Unit>:
        owner : Storage.AuthStorageOwner <- Storage.create(path)
        opened(mode,Storage.borrow(owner))
    case _: IO.die(Unit,1,"expected mode path")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

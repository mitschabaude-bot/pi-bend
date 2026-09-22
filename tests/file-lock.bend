import Base
import ../packages/runtime/src/file-lock.bend as Lock
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/test/utf8-runner.bend as W

def error(cause: Lock.Error) -> String:
  match cause:
    case Lock.Locked{_}: "locked"
    case Lock.Cancelled{}: "cancelled"
    case Lock.InvalidOptions{}: "options"
    case Lock.System{operation,_,code,_}: operation ++ ":" ++ U32.show(code)
    case Lock.PathError{FS.System{code,_}}: "path:" ++ U32.show(code)
    case Lock.PathError{_}: "path-encoding"
    case Lock.Compromised{_,Lock.Missing{}}: "compromised:missing"
    case Lock.Compromised{_,Lock.Modified{}}: "compromised:modified"
    case Lock.Compromised{_,Lock.UpdateFailed{code,_}}: "compromised:update:" ++ U32.show(code)
    case Lock.CleanupFailed{cause,cleanup}: "cleanup:" ++ error(cause) ++ ":" ++ error(cleanup)
def result(value: Result<&2,&2,Lock.Error,Unit>) -> String:
  match value:
    case Done{_}: "ok"
    case Fail{cause}: error(cause)
def options() -> Lock.Options: Lock.Options{2000,1000,1n,20,False{}}
def ownerHeld(duration: U32, pair: Lock.Owner & Lock.Handle) -> IO(Unit):
  match pair:
    case (owner,handle):
      do IO<Unit>:
        IO.print("acquired")
        IO.sleep(duration)
        checked : Result<&2,&2,Lock.Error,Unit> <- Lock.check(handle)
        IO.print("check:" ++ result(checked))
        released : Result<&2,&2,Lock.Error,Unit> <- Lock.release(owner)
        IO.print("release:" ++ result(released))
def held(duration: U32, value: Result<&2,&1,Lock.Error,Lock.Owner>) -> IO(Unit):
  match value:
    case Fail{cause}: IO.print("acquire:" ++ error(cause))
    case Done{owner}: ownerHeld(duration,Lock.borrow(owner))
def hold(path: String, duration: U32, configured: Lock.Options) -> IO(Unit):
  do IO<Unit>:
    acquired : Result<&2,&1,Lock.Error,Lock.Owner> <- Lock.acquire(path,configured,None{})
    held(duration,acquired)
def requestAbort(controller: Abort.AbortController<Unit>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(30)
    won : Bool <- Abort.abort(Unit,controller,None{})
    return Unit{}
def cancel(path: String, pre: Bool, realpath: Bool) -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    initial : Bool <- Bool.pick(IO(Bool),pre,Abort.abort(Unit,controller,None{}),IO.pure(Bool,False{}))
    task : Chan(Unit) <- IO.fork(Unit,requestAbort(controller))
    acquired : Result<&2,&1,Lock.Error,Lock.Owner> <- Lock.acquire(path,Lock.Options{2000,1000,100n,5000,realpath},Some{Abort.signal(Unit,controller)})
    held(0,acquired)
    IO.join(Unit,task)
    Abort.dispose(Unit,controller)
def finished(owner: Lock.Owner) -> IO(Bool):
  do IO<Bool>:
    value : Result<&2,&2,Lock.Error,Unit> <- Lock.release(owner)
    return Result.is_done(&2,&2,Lock.Error,Unit,value)
def releaseBoolean(value: Result<&2,&1,Lock.Error,Lock.Owner>) -> IO(Bool):
  match value:
    case Fail{_}: IO.pure(Bool,False{})
    case Done{owner}: finished(owner)
def repeatStep(count: Nat, +path: String, state: Bool) -> IO(Bool):
  match count state:
    case _ False{}: IO.pure(Bool,False{})
    case 0n True{}: IO.pure(Bool,True{})
    case 1n+count True{}:
      do IO<Bool>:
        acquired : Result<&2,&1,Lock.Error,Lock.Owner> <- Lock.acquire(path,options(),None{})
        good : Bool <- releaseBoolean(acquired)
        repeatStep(count,path,good)
def descriptorCount(value: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>) -> Nat:
  match value:
    case Done{entries}: List.length(&2,FS.DirectoryEntry,entries)
    case _: 0n
def repeated(+path: String) -> IO(Unit):
  do IO<Unit>:
    warm : Bool <- repeatStep(1n,path,True{})
    before : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory("/proc/self/fd")
    good : Bool <- repeatStep(100n,path,warm)
    after : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory("/proc/self/fd")
    IO.print(Bool.pick(String,good && Nat.is_eq(descriptorCount(before),descriptorCount(after)),"repeat:ok","repeat:failed"))
def decodedText(value: Result<&2,&2,Utf8.Error,String>) -> String:
  match value:
    case Done{value}: value
    case _: ""
def incrementBytes(value: Result<&2,&2,FS.Error,List<&2,U32>>) -> String:
  match value:
    case Done{bytes}: U32.show((W.decimal(decodedText(Utf8.decodeWith(Utf8.Preserve{},bytes)),0) + 1 : U32))
    case _: "1"
def incrementOwner(+path: String, value: Result<&2,&1,Lock.Error,Lock.Owner>) -> IO(Unit):
  match value:
    case Fail{cause}: IO.print("acquire:" ++ error(cause))
    case Done{owner}:
      do IO<Unit>:
        bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
        IO.sleep(2)
        wrote : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(path,incrementBytes(bytes))
        released : Result<&2,&2,Lock.Error,Unit> <- Lock.release(owner)
        IO.print(Bool.pick(String,Result.is_done(&2,&2,FS.Error,Unit,wrote) && Result.is_done(&2,&2,Lock.Error,Unit,released),"increment:ok","increment:failed"))
def increment(+path: String) -> IO(Unit):
  do IO<Unit>:
    acquired : Result<&2,&1,Lock.Error,Lock.Owner> <- Lock.acquire(path,Lock.Options{2000,1000,1000n,5,False{}},None{})
    incrementOwner(path,acquired)
def rawTime(value: Result<&1,&1,U32 & String,U32 & U32 & U32>) -> String:
  match value:
    case Fail{(code,_)}: "stat:" ++ U32.show(code)
    case Done{(high,(low,nanos))}: U32.show(high) ++ ":" ++ U32.show(low) ++ ":" ++ U32.show(nanos)
def rawResult(value: Result<&1,&1,U32 & String,Unit>) -> String:
  match value:
    case Fail{(code,_)}: "error:" ++ U32.show(code)
    case Done{_}: "ok"
def metadata(+path: String, high: U32, low: U32) -> IO(Unit):
  do IO<Unit>:
    touched : Result<&1,&1,U32 & String,Unit> <- File.set_times_milliseconds(path,high,low)
    IO.print(rawResult(touched))
    value : Result<&1,&1,U32 & String,U32 & U32 & U32> <- File.modified_time(path)
    IO.print(rawTime(value))
def statOnly(path: String) -> IO(Unit):
  do IO<Unit>:
    value : Result<&1,&1,U32 & String,U32 & U32 & U32> <- File.modified_time(path)
    IO.print(rawTime(value))
def nulPath(+path: String) -> IO(Unit):
  do IO<Unit>:
    created : Result<&1,&1,U32 & String,Unit> <- Directory.create(path ++ SCon{Chr{0},SNil{}})
    removed : Result<&1,&1,U32 & String,Unit> <- Directory.remove(path ++ SCon{Chr{0},SNil{}})
    touched : Result<&1,&1,U32 & String,Unit> <- File.set_times_milliseconds(path ++ SCon{Chr{0},SNil{}},0,0)
    value : Result<&1,&1,U32 & String,U32 & U32 & U32> <- File.modified_time(path ++ SCon{Chr{0},SNil{}})
    IO.print(rawResult(created) ++ "|" ++ rawResult(removed) ++ "|" ++ rawResult(touched) ++ "|" ++ rawTime(value))
def run(args: List<String>) -> IO(Unit):
  match args:
    case "hold" <> path <> duration <> Nil{}: hold(path,W.decimal(duration,0),options())
    case "retry" <> path <> Nil{}: hold(path,0,Lock.Options{2000,1000,10n,20,False{}})
    case "defaults" <> path <> Nil{}: hold(path,0,Lock.defaults())
    case "invalid" <> path <> Nil{}: hold(path,0,Lock.Options{1999,1000,1n,20,False{}})
    case "cancel" <> path <> Nil{}: cancel(path,False{},False{})
    case "pre" <> path <> Nil{}: cancel(path,True{},False{})
    case "pre-realpath" <> path <> Nil{}: cancel(path,True{},True{})
    case "repeat" <> path <> Nil{}: repeated(path)
    case "increment" <> path <> Nil{}: increment(path)
    case "metadata" <> path <> high <> low <> Nil{}: metadata(path,W.decimal(high,0),W.decimal(low,0))
    case "nul" <> path <> Nil{}: nulPath(path)
    case "stat" <> path <> Nil{}: statOnly(path)
    case _: IO.die(Unit,1,"invalid fixture arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

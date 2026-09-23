import Base
import ../packages/coding-agent/src/core/tools/file-mutation-queue.bend as Q
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/posix-path.bend as Path

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)

def signal(channel: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Unit,channel,Unit{})
    R.requireSent(sent)

def append(log: R.Ref<String>, text: String) -> IO(Unit):
  R.modify(String,Unit,log,value => (value ++ text,Unit{}))

def operation(+log: R.Ref<String>, +name: String, entered: Chan(Unit), resume: Chan(Unit)) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    append(log,name ++ ":start;")
    signal(entered)
    IO.join(Unit,resume)
    append(log,name ++ ":end;")
    return Fail{"intentional operation failure"}

def outcome(value: Result<&2,&1,FS.Error,Result<&2,&2,String,Unit>>) -> IO(Unit):
  match value:
    case Done{Fail{"intentional operation failure"}}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"queue lost the operation result")

def pair(owner: Q.Owner & Q.Queue, firstPath: String, secondPath: String, +parallel: Bool) -> IO(Unit):
  match owner:
    case (owned,+queue):
      do IO<Unit>:
        +log : R.Ref<String> <- R.new(String,"")
        +entered1 : Chan(Unit) <- Chan.new(Unit,1)
        +entered2 : Chan(Unit) <- Chan.new(Unit,1)
        +resume1 : Chan(Unit) <- Chan.new(Unit,1)
        +resume2 : Chan(Unit) <- Chan.new(Unit,1)
        first : Result<&2,&1,FS.Error,Q.Reservation> <- Q.register(queue,firstPath)
        second : Result<&2,&1,FS.Error,Q.Reservation> <- Q.register(queue,secondPath)
        task1 : Chan(Result<&2,&1,FS.Error,Result<&2,&2,String,Unit>>) <- IO.fork(Result<&2,&1,FS.Error,Result<&2,&2,String,Unit>>,Q.execute(Result<&2,&2,String,Unit>,queue,_ => operation(log,"first",entered1,resume1),first))
        IO.join(Unit,entered1)
        task2 : Chan(Result<&2,&1,FS.Error,Result<&2,&2,String,Unit>>) <- IO.fork(Result<&2,&1,FS.Error,Result<&2,&2,String,Unit>>,Q.execute(Result<&2,&2,String,Unit>,queue,_ => operation(log,"second",entered2,resume2),second))
        Bool.pick(IO(Unit),parallel,IO.join(Unit,entered2),IO.pure(Unit,Unit{}))
        signal(resume1)
        result1 : Result<&2,&1,FS.Error,Result<&2,&2,String,Unit>> <- IO.join(Result<&2,&1,FS.Error,Result<&2,&2,String,Unit>>,task1)
        outcome(result1)
        Bool.pick(IO(Unit),parallel,IO.pure(Unit,Unit{}),IO.join(Unit,entered2))
        signal(resume2)
        result2 : Result<&2,&1,FS.Error,Result<&2,&2,String,Unit>> <- IO.join(Result<&2,&1,FS.Error,Result<&2,&2,String,Unit>>,task2)
        outcome(result2)
        value : String <- R.dispose(String,log)
        check(String.eq(value,Bool.pick(String,parallel,"first:start;second:start;first:end;second:end;","first:start;first:end;second:start;second:end;")),"file mutation ordering")
        Q.dispose(owned)
        IO.print("ok")

def failed(value: Result<&2,&1,FS.Error,Unit>) -> IO(Unit):
  match value:
    case Fail{FS.System{40,_}}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"expected realpath ELOOP")

def done(value: Result<&2,&1,FS.Error,Unit>) -> IO(Unit):
  match value:
    case Done{Unit{}}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"queue did not recover")

def recovery(pair: Q.Owner & Q.Queue, bad: String, +good: String) -> IO(Unit):
  match pair:
    case (owner,+queue):
      do IO<Unit>:
        failure : Result<&2,&1,FS.Error,Unit> <- Q.withFileMutationQueue(Unit,queue,bad,_ => IO.die(Unit,1,"failed registration called operation"))
        failed(failure)
        first : Result<&2,&1,FS.Error,Unit> <- Q.withFileMutationQueue(Unit,queue,good,_ => IO.pure(Unit,Unit{}))
        done(first)
        second : Result<&2,&1,FS.Error,Unit> <- Q.withFileMutationQueue(Unit,queue,good,_ => IO.pure(Unit,Unit{}))
        done(second)
        Q.dispose(owner)
        IO.print("ok")

def showPath(value: Maybe<&2,String>) -> String:
  match value:
    case Some{path}: path
    case None{}: "invalid base"

def run(args: List<String>) -> IO(Unit):
  match args:
    case "pair" <> mode <> first <> second <> Nil{}:
      do IO<Unit>:
        owner : Q.Owner <- Q.create()
        pair(Q.borrow(owner),first,second,String.eq(mode,"parallel"))
    case "recovery" <> bad <> good <> Nil{}:
      do IO<Unit>:
        owner : Q.Owner <- Q.create()
        recovery(Q.borrow(owner),bad,good)
    case "path" <> base <> path <> Nil{}: IO.print(showPath(Path.resolve(base,path)))
    case _: IO.die(Unit,1,"invalid queue fixture arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)

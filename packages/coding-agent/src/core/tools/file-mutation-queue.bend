import Base
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../runtime/src/record.bend as Record
import ../../../../runtime/src/serial-resource.bend as Serial
import ../../../../runtime/src/ref.bend as Ref

def Registry() -> Data: Record.Record<Chan(Unit)>

type Queue is Data:
  Queue{registration: Serial.Handle<Registry()>}

type Owner is Type:
  Owner{registration: Serial.Owner<Registry()>}

type Reservation is Type:
  Reservation{key: String, completion: Chan(Unit), previous: Maybe<&2,Chan(Unit)>}

def create() -> IO(Owner):
  do IO<Owner>:
    registration : Serial.Owner<Registry()> <- Serial.create(Registry(),Record.new(Chan(Unit)))
    return Owner{registration}

def borrowed(pair: Serial.Owner<Registry()> & Serial.Handle<Registry()>) -> Owner & Queue:
  match pair:
    case (owner,handle): (Owner{owner},Queue{handle})

def borrow(owner: Owner) -> Owner & Queue:
  match owner:
    case Owner{registration}: borrowed(Serial.borrow(Registry(),registration))

def resolved(value: Maybe<&2,String>) -> Result<&2,&2,FS.Error,String>:
  match value:
    case Some{path}: Done{path}
    case None{}: Fail{FS.System{22,"Expected an absolute working directory"}}

def absolutePath(+path: String) -> IO(Result<&2,&2,FS.Error,String>):
  match path:
    case SCon{'/',_}: IO.pure(Result<&2,&2,FS.Error,String>,resolved(Path.resolve("/",path)))
    case value:
      do IO<Result<&2,&2,FS.Error,String>>:
        cwd : Result<&2,&2,FS.Error,String> <- FS.cwd()
        return Result.bind(&2,&2,FS.Error,String,String,cwd,base => resolved(Path.resolve(base,value)))

def canonical(path: String, result: Result<&2,&2,FS.Error,String>) -> Result<&2,&2,FS.Error,String>:
  match result:
    case Done{value}: Done{value}
    case Fail{FS.System{2,_}}: Done{path}
    case Fail{FS.System{20,_}}: Done{path}
    case Fail{error}: Fail{error}

def keyForPath(result: Result<&2,&2,FS.Error,String>) -> IO(Result<&2,&2,FS.Error,String>):
  match result:
    case Fail{error}: IO.pure(Result<&2,&2,FS.Error,String>,Fail{error})
    case Done{+path}:
      do IO<Result<&2,&2,FS.Error,String>>:
        result : Result<&2,&2,FS.Error,String> <- FS.realpath(path)
        return canonical(path,result)

def insert(+registry: Registry(), result: Result<&2,&2,FS.Error,String>) -> IO(Registry() & Result<&2,&1,FS.Error,Reservation>):
  match result:
    case Fail{error}: IO.pure(Registry() & Result<&2,&1,FS.Error,Reservation>,(registry,Fail{error}))
    case Done{+key}:
      do IO<Registry() & Result<&2,&1,FS.Error,Reservation>>:
        +completion : Chan(Unit) <- Chan.new(Unit,1)
        return (Record.set(Chan(Unit),registry,key,completion),Done{Reservation{key,completion,Record.get(Chan(Unit),registry,key)}})

def registerPath(registry: Registry(), path: String) -> IO(Registry() & Result<&2,&1,FS.Error,Reservation>):
  do IO<Registry() & Result<&2,&1,FS.Error,Reservation>>:
    absolute : Result<&2,&2,FS.Error,String> <- absolutePath(path)
    key : Result<&2,&2,FS.Error,String> <- keyForPath(absolute)
    insert(registry,key)

# Registration includes canonicalization and is serialized globally within the
# tool bundle. Operations themselves only wait for their own file predecessor.
def register(queue: Queue, path: String) -> IO(Result<&2,&1,FS.Error,Reservation>):
  match queue:
    case Queue{registration}: Serial.run(Registry(),Result<&2,&1,FS.Error,Reservation>,registration,state => registerPath(state,path))

def wait(previous: Maybe<&2,Chan(Unit)>) -> IO(Unit):
  match previous:
    case None{}: IO.pure(Unit,Unit{})
    case Some{channel}: IO.join(Unit,channel)

def complete(last: Bool, registry: Registry(), key: String, completion: Chan(Unit)) -> IO(Registry() & Unit):
  match last:
    case True{}:
      do IO<Registry() & Unit>:
        Chan.close(Unit,completion)
        return (Record.remove(Chan(Unit),registry,key),Unit{})
    case False{}:
      do IO<Registry() & Unit>:
        sent : Bool <- Chan.send(Unit,completion,Unit{})
        Ref.requireSent(sent)
        return (registry,Unit{})

def releaseState(registry: Registry(), key: String, +completion: Chan(Unit), latest: Maybe<&2,Chan(Unit)>) -> IO(Registry() & Unit):
  match latest:
    case None{}: IO.die(Registry() & Unit,1,"Missing file mutation registration")
    case Some{channel}: complete(Chan.same(Unit,channel,completion),registry,key,completion)

def release(queue: Queue, +key: String, completion: Chan(Unit)) -> IO(Unit):
  match queue:
    case Queue{registration}: Serial.run(Registry(),Unit,registration,+registry => releaseState(registry,key,completion,Record.get(Chan(Unit),registry,key)))

def execute(-A: Type, queue: Queue, operation: Unit -> IO(A), reservation: Result<&2,&1,FS.Error,Reservation>) -> IO(Result<&2,&1,FS.Error,A>):
  match reservation:
    case Fail{error}: IO.pure(Result<&2,&1,FS.Error,A>,Fail{error})
    case Done{Reservation{key,completion,previous}}:
      do IO<Result<&2,&1,FS.Error,A>>:
        wait(previous)
        result : A <- operation(Unit{})
        release(queue,key,completion)
        return Done{result}

# Typed operation failures are ordinary results: release happens after they
# settle too. Cancellation must never detach an in-flight filesystem operation.
def withFileMutationQueue(-A: Type, +queue: Queue, path: String, operation: Unit -> IO(A)) -> IO(Result<&2,&1,FS.Error,A>):
  do IO<Result<&2,&1,FS.Error,A>>:
    reservation : Result<&2,&1,FS.Error,Reservation> <- register(queue,path)
    execute(A,queue,operation,reservation)

def retired(entries: List<&2,Record.Property<Chan(Unit)>>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit,Unit{})
    case _ <> _: IO.die(Unit,1,"File mutation queue retired while operations remain")

# Drain callers and retire borrowed tool callbacks before disposing the owner.
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{registration}:
      do IO<Unit>:
        registry : Registry() <- Serial.retire(Registry(),registration)
        retired(Record.entries(Chan(Unit),registry))

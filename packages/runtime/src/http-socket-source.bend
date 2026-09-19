import Base
import ./abort.bend as A
import ./abortable-socket.bend as S
import ./socket-interrupt.bend as I
import ./serial-resource.bend as Resource
import ./callback.bend as C
import ./http-response-reader.bend as Reader

# A dedicated connected socket lease. Release closes the connection; pooling
# and reuse of response remainder belong to a different source implementation.
type Error<-Reason: Data> is Data:
  SocketFailure{error: S.Error<Reason>}
  CleanupFailure{error: I.Error}
  Released{}
  InvalidReadSize{}

type Environment<-Reason: Data> is Data:
  Environment{resource: Resource.Handle<Maybe<&1, S.Owner<Reason>>>, maximum: U32}

type Owner<-Reason: Data> is Type:
  Owner{resource: Resource.Owner<Maybe<&1, S.Owner<Reason>>>, source: Reader.Source<Error<Reason>>}

def bytes(-Reason: Data, value: Result<&2, &2, S.Error<Reason>, List<&2, U32>>) -> Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>:
  match value:
    case Fail{error}: Fail{SocketFailure{error}}
    case Done{Nil{}}: Done{None{}}
    case Done{head <> rest}: Done{Some{head <> rest}}

def received(-Reason: Data, pair: S.Owner<Reason> & Result<&2, &2, S.Error<Reason>, List<&2, U32>>) -> Maybe<&1, S.Owner<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>:
  match pair:
    case (owner, value): (Some{owner}, bytes(Reason, value))

def readOwned(-Reason: Data, maximum: U32, value: Maybe<&1, S.Owner<Reason>>) -> IO(Maybe<&1, S.Owner<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>):
  match value:
    case None{}: IO.pure(Maybe<&1, S.Owner<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>, (None{}, Fail{Released{}}))
    case Some{owner}:
      do IO<Maybe<&1, S.Owner<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>>:
        result : S.Owner<Reason> & Result<&2, &2, S.Error<Reason>, List<&2, U32>> <- S.recv(Reason, owner, maximum)
        return received(Reason, result)

def readCallback(-Reason: Data, environment: Environment<Reason>, unused: Unit) -> IO(Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>):
  match environment:
    case Environment{resource, maximum}: Resource.run(Maybe<&1, S.Owner<Reason>>, Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>, resource, value => readOwned(Reason, maximum, value))

def cleanup(-Reason: Data, value: Result<&2, &2, I.Error, Unit>) -> Result<&2, &2, Error<Reason>, Unit>:
  match value:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{CleanupFailure{error}}

def closeOwned(-Reason: Data, value: Maybe<&1, S.Owner<Reason>>) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  match value:
    case None{}: IO.pure(Result<&2, &2, Error<Reason>, Unit>, Done{Unit{}})
    case Some{owner}:
      do IO<Result<&2, &2, Error<Reason>, Unit>>:
        result : Result<&2, &2, I.Error, Unit> <- S.close(Reason, owner)
        return cleanup(Reason, result)

def releaseOwned(-Reason: Data, value: Maybe<&1, S.Owner<Reason>>) -> IO(Maybe<&1, S.Owner<Reason>> & Result<&2, &2, Error<Reason>, Unit>):
  do IO<Maybe<&1, S.Owner<Reason>> & Result<&2, &2, Error<Reason>, Unit>>:
    result : Result<&2, &2, Error<Reason>, Unit> <- closeOwned(Reason, value)
    return (None{}, result)

def releaseCallback(-Reason: Data, environment: Environment<Reason>, unused: Reader.Release) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  match environment:
    case Environment{resource, _}: Resource.run(Maybe<&1, S.Owner<Reason>>, Result<&2, &2, Error<Reason>, Unit>, resource, value => releaseOwned(Reason, value))

def callbacks(~Reason: Data, +maximum: U32, pair: Resource.Owner<Maybe<&1, S.Owner<Reason>>> & Resource.Handle<Maybe<&1, S.Owner<Reason>>>) -> IO(Owner<Reason>):
  match pair:
    case (resource, +handle):
      do IO<Owner<Reason>>:
        reader : C.Callback<Unit, Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>> <- C.create(~Environment<Reason>, ~Unit, ~Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>, ~readCallback(Reason), Environment{handle, maximum})
        release : C.Callback<Reader.Release, Result<&2, &2, Error<Reason>, Unit>> <- C.create(~Environment<Reason>, ~Reader.Release, ~Result<&2, &2, Error<Reason>, Unit>, ~releaseCallback(Reason), Environment{handle, maximum})
        return Owner{resource, Reader.Source{reader, release}}

def adopted(~Reason: Data, maximum: U32, result: Result<&2, &1, S.Error<Reason>, S.Owner<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Owner<Reason>>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &1, Error<Reason>, Owner<Reason>>, Fail{SocketFailure{error}})
    case Done{owner}:
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        resource : Resource.Owner<Maybe<&1, S.Owner<Reason>>> <- Resource.create(Maybe<&1, S.Owner<Reason>>, Some{owner})
        result : Owner<Reason> <- callbacks(~Reason, maximum, Resource.borrow(Maybe<&1, S.Owner<Reason>>, resource))
        return Done{result}

# Transfers the connected socket on every path. A zero-size read would look
# like EOF to the decoder, so reject it before constructing the byte source.
def create(~Reason: Data, socket: Socket, signal: A.AbortSignal<Reason>, maximum: U32) -> IO(Result<&2, &1, Error<Reason>, Owner<Reason>>):
  match maximum:
    case 0:
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        Socket.close(socket)
        return Fail{InvalidReadSize{}}
    case size:
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        result : Result<&2, &1, S.Error<Reason>, S.Owner<Reason>> <- S.create(Reason, socket, signal)
        adopted(~Reason, size, result)

# Grant this borrowed lease to one response cursor only.
def borrow(-Reason: Data, owner: Owner<Reason>) -> Owner<Reason> & Reader.Source<Error<Reason>>:
  match owner:
    case Owner{resource, +source}: (Owner{resource, source}, source)

def disposeCallbacks(-Reason: Data, source: Reader.Source<Error<Reason>>) -> IO(Unit):
  match source:
    case Reader.Source{reader, release}:
      do IO<Unit>:
        C.dispose(Unit, Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>, reader)
        C.dispose(Reader.Release, Result<&2, &2, Error<Reason>, Unit>, release)

# Retire the cursor and finish all callback users first. Disposal also closes
# an unused lease, then frees the callback factories and serial resource.
def dispose(-Reason: Data, owner: Owner<Reason>) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  match owner:
    case Owner{resource, source}:
      do IO<Result<&2, &2, Error<Reason>, Unit>>:
        value : Maybe<&1, S.Owner<Reason>> <- Resource.retire(Maybe<&1, S.Owner<Reason>>, resource)
        result : Result<&2, &2, Error<Reason>, Unit> <- closeOwned(Reason, value)
        disposeCallbacks(Reason, source)
        return result

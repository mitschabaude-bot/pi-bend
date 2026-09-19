import Base
import ./abort.bend as A
import ./abortable-socket.bend as S
import ./socket-interrupt.bend as I
import ./socket-upload.bend as U
import ./serial-resource.bend as Resource
import ./callback.bend as C
import ./http-response-reader.bend as Reader

# A dedicated connected socket lease. Release closes the connection; pooling
# and reuse of response remainder belong to a different source implementation.
type Error<-Reason: Data> is Data:
  SocketFailure{error: S.Error<Reason>}
  CleanupFailure{error: I.Error}
  UploadFailure{error: U.Error<Reason>}
  UploadWithCleanup{error: U.Error<Reason>, cleanup: I.Error}
  Released{}
  InvalidReadSize{}

# The source owns both directions. Its upload must finish before the shared
# connection's watcher and interrupt descriptor can be retired.
type Lease<-Reason: Data> is Type:
  Lease{connection: S.Owner<Reason>, upload: Maybe<&1, U.Owner<Reason>>}

type Environment<-Reason: Data> is Data:
  Environment{resource: Resource.Handle<Maybe<&1, Lease<Reason>>>, maximum: U32}

type Owner<-Reason: Data> is Type:
  Owner{resource: Resource.Owner<Maybe<&1, Lease<Reason>>>, source: Reader.Source<Error<Reason>>}

def bytes(-Reason: Data, value: Result<&2, &2, S.Error<Reason>, List<&2, U32>>) -> Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>:
  match value:
    case Fail{error}: Fail{SocketFailure{error}}
    case Done{Nil{}}: Done{None{}}
    case Done{head <> rest}: Done{Some{head <> rest}}

def checkedUpload(-Reason: Data, pair: U.Owner<Reason> & Maybe<&2, S.Error<Reason>>) -> Maybe<&1, U.Owner<Reason>> & Maybe<&2, S.Error<Reason>>:
  match pair:
    case (owner, error): (Some{owner}, error)

def checkUpload(-Reason: Data, upload: Maybe<&1, U.Owner<Reason>>) -> IO(Maybe<&1, U.Owner<Reason>> & Maybe<&2, S.Error<Reason>>):
  match upload:
    case None{}: IO.pure(Maybe<&1, U.Owner<Reason>> & Maybe<&2, S.Error<Reason>>, (None{}, None{}))
    case Some{owner}:
      do IO<Maybe<&1, U.Owner<Reason>> & Maybe<&2, S.Error<Reason>>>:
        result : U.Owner<Reason> & Maybe<&2, S.Error<Reason>> <- U.check(Reason, owner)
        return checkedUpload(Reason, result)

def observed(-Reason: Data, connection: S.Owner<Reason>, result: Result<&2, &2, S.Error<Reason>, List<&2, U32>>, pair: Maybe<&1, U.Owner<Reason>> & Maybe<&2, S.Error<Reason>>) -> Maybe<&1, Lease<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>:
  match pair:
    case (upload, Some{error}): (Some{Lease{connection, upload}}, Fail{SocketFailure{error}})
    case (upload, None{}): (Some{Lease{connection, upload}}, bytes(Reason, result))

def received(-Reason: Data, upload: Maybe<&1, U.Owner<Reason>>, pair: S.Owner<Reason> & Result<&2, &2, S.Error<Reason>, List<&2, U32>>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>):
  match pair:
    case (connection, result):
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>>:
        checked : Maybe<&1, U.Owner<Reason>> & Maybe<&2, S.Error<Reason>> <- checkUpload(Reason, upload)
        return observed(Reason, connection, result, checked)

def readChecked(-Reason: Data, maximum: U32, connection: S.Owner<Reason>, pair: Maybe<&1, U.Owner<Reason>> & Maybe<&2, S.Error<Reason>>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>):
  match pair:
    case (upload, Some{error}): IO.pure(Maybe<&1, Lease<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>, (Some{Lease{connection, upload}}, Fail{SocketFailure{error}}))
    case (upload, None{}):
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>>:
        result : S.Owner<Reason> & Result<&2, &2, S.Error<Reason>, List<&2, U32>> <- S.recv(Reason, connection, maximum)
        received(Reason, upload, result)

def readOwned(-Reason: Data, maximum: U32, value: Maybe<&1, Lease<Reason>>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>):
  match value:
    case None{}: IO.pure(Maybe<&1, Lease<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>, (None{}, Fail{Released{}}))
    case Some{Lease{connection, upload}}:
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>>:
        checked : Maybe<&1, U.Owner<Reason>> & Maybe<&2, S.Error<Reason>> <- checkUpload(Reason, upload)
        readChecked(Reason, maximum, connection, checked)

def classified(-Reason: Data, isReset: Bool, error: Error<Reason>) -> Reader.ReadResult<Error<Reason>>:
  match isReset:
    case True{}: Reader.Reset{error}
    case False{}: Reader.Failed{error}

def classify(-Reason: Data, result: Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>) -> IO(Reader.ReadResult<Error<Reason>>):
  match result:
    case Fail{SocketFailure{S.SocketError{+code, message}}}:
      do IO<Reader.ReadResult<Error<Reason>>>:
        isReset : Bool <- Socket.isConnectionReset(code)
        return classified(Reason, isReset, SocketFailure{S.SocketError{code, message}})
    case value: IO.pure(Reader.ReadResult<Error<Reason>>, Reader.fromResult(Error<Reason>, value))

def readCallback(-Reason: Data, environment: Environment<Reason>, unused: Unit) -> IO(Reader.ReadResult<Error<Reason>>):
  match environment:
    case Environment{resource, maximum}:
      do IO<Reader.ReadResult<Error<Reason>>>:
        result : Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>> <- Resource.run(Maybe<&1, Lease<Reason>>, Result<&2, &2, Error<Reason>, Maybe<&2, List<&2, U32>>>, resource, value => readOwned(Reason, maximum, value))
        classify(Reason, result)

def cleanup(-Reason: Data, value: Result<&2, &2, I.Error, Unit>) -> Result<&2, &2, Error<Reason>, Unit>:
  match value:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{CleanupFailure{error}}

def stopUpload(-Reason: Data, upload: Maybe<&1, U.Owner<Reason>>) -> IO(Result<&2, &2, U.Error<Reason>, Unit>):
  match upload:
    case None{}: IO.pure(Result<&2, &2, U.Error<Reason>, Unit>, Done{Unit{}})
    case Some{owner}: U.stop(Reason, owner)

def closed(-Reason: Data, upload: Result<&2, &2, U.Error<Reason>, Unit>, connection: Result<&2, &2, I.Error, Unit>) -> Result<&2, &2, Error<Reason>, Unit>:
  match upload connection:
    case Done{_} result: cleanup(Reason, result)
    case Fail{error} Done{_}: Fail{UploadFailure{error}}
    case Fail{error} Fail{secondary}: Fail{UploadWithCleanup{error, secondary}}

def closeOwned(-Reason: Data, value: Maybe<&1, Lease<Reason>>) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  match value:
    case None{}: IO.pure(Result<&2, &2, Error<Reason>, Unit>, Done{Unit{}})
    case Some{Lease{connection, upload}}:
      do IO<Result<&2, &2, Error<Reason>, Unit>>:
        stopped : Result<&2, &2, U.Error<Reason>, Unit> <- stopUpload(Reason, upload)
        result : Result<&2, &2, I.Error, Unit> <- S.close(Reason, connection)
        return closed(Reason, stopped, result)

def releaseOwned(-Reason: Data, value: Maybe<&1, Lease<Reason>>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, Error<Reason>, Unit>):
  do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, Error<Reason>, Unit>>:
    result : Result<&2, &2, Error<Reason>, Unit> <- closeOwned(Reason, value)
    return (None{}, result)

def releaseCallback(-Reason: Data, environment: Environment<Reason>, unused: Reader.Release) -> IO(Result<&2, &2, Error<Reason>, Unit>):
  match environment:
    case Environment{resource, _}: Resource.run(Maybe<&1, Lease<Reason>>, Result<&2, &2, Error<Reason>, Unit>, resource, value => releaseOwned(Reason, value))

def callbacks(~Reason: Data, +maximum: U32, pair: Resource.Owner<Maybe<&1, Lease<Reason>>> & Resource.Handle<Maybe<&1, Lease<Reason>>>) -> IO(Owner<Reason>):
  match pair:
    case (resource, +handle):
      do IO<Owner<Reason>>:
        reader : C.Callback<Unit, Reader.ReadResult<Error<Reason>>> <- C.create(~Environment<Reason>, ~Unit, ~Reader.ReadResult<Error<Reason>>, ~readCallback(Reason), Environment{handle, maximum})
        release : C.Callback<Reader.Release, Result<&2, &2, Error<Reason>, Unit>> <- C.create(~Environment<Reason>, ~Reader.Release, ~Result<&2, &2, Error<Reason>, Unit>, ~releaseCallback(Reason), Environment{handle, maximum})
        return Owner{resource, Reader.TransportSource{reader, release}}

def adoptLease(~Reason: Data, maximum: U32, lease: Lease<Reason>) -> IO(Owner<Reason>):
  do IO<Owner<Reason>>:
    resource : Resource.Owner<Maybe<&1, Lease<Reason>>> <- Resource.create(Maybe<&1, Lease<Reason>>, Some{lease})
    callbacks(~Reason, maximum, Resource.borrow(Maybe<&1, Lease<Reason>>, resource))

def adopted(~Reason: Data, maximum: U32, result: Result<&2, &1, S.Error<Reason>, S.Owner<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Owner<Reason>>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &1, Error<Reason>, Owner<Reason>>, Fail{SocketFailure{error}})
    case Done{owner}:
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        result : Owner<Reason> <- adoptLease(~Reason, maximum, Lease{owner, None{}})
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
    case Reader.TransportSource{reader, release}:
      do IO<Unit>:
        C.dispose(Unit, Reader.ReadResult<Error<Reason>>, reader)
        C.dispose(Reader.Release, Result<&2, &2, Error<Reason>, Unit>, release)
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
        value : Maybe<&1, Lease<Reason>> <- Resource.retire(Maybe<&1, Lease<Reason>>, resource)
        result : Result<&2, &2, Error<Reason>, Unit> <- closeOwned(Reason, value)
        disposeCallbacks(Reason, source)
        return result

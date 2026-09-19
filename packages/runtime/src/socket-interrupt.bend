import Base
import ./serial-resource.bend as Resource

# A separate owned descriptor lets cancellation run while the original socket
# is held by pending IO. It pins the same connection, never a reused fd number.
type Error is Data:
  Error{code: U32, message: String}

type Owner is Type:
  Owner{resource: Resource.Owner<Maybe<&1, Socket>>}

type Handle is Data:
  Handle{resource: Resource.Handle<Maybe<&1, Socket>>}

def acquired(pair: Socket & Result<&1, &1, U32 & String, Socket>) -> IO(Socket & Result<&2, &1, Error, Owner>):
  match pair:
    case (socket, Fail{(code, message)}): IO.pure(Socket & Result<&2, &1, Error, Owner>, (socket, Fail{Error{code, message}}))
    case (socket, Done{copy}):
      do IO<Socket & Result<&2, &1, Error, Owner>>:
        resource : Resource.Owner<Maybe<&1, Socket>> <- Resource.create(Maybe<&1, Socket>, Some{copy})
        return (socket, Done{Owner{resource}})

# The caller retains the original socket even when duplication fails.
def create(socket: Socket) -> IO(Socket & Result<&2, &1, Error, Owner>):
  do IO<Socket & Result<&2, &1, Error, Owner>>:
    pair : Socket & Result<&1, &1, U32 & String, Socket> <- Socket.duplicate(socket)
    acquired(pair)

def borrowed(pair: Resource.Owner<Maybe<&1, Socket>> & Resource.Handle<Maybe<&1, Socket>>) -> Owner & Handle:
  match pair:
    case (owner, handle): (Owner{owner}, Handle{handle})

def borrow(owner: Owner) -> Owner & Handle:
  match owner:
    case Owner{resource}: borrowed(Resource.borrow(Maybe<&1, Socket>, resource))

def result(value: Result<&1, &1, U32 & String, Unit>) -> Result<&2, &2, Error, Bool>:
  match value:
    case Done{_}: Done{True{}}
    case Fail{(code, message)}: Fail{Error{code, message}}

def shutdown(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Maybe<&1, Socket> & Result<&2, &2, Error, Bool>):
  match pair:
    case (socket, outcome):
      do IO<Maybe<&1, Socket> & Result<&2, &2, Error, Bool>>:
        Socket.close(socket)
        return (None{}, result(outcome))

def cancelOwned(value: Maybe<&1, Socket>) -> IO(Maybe<&1, Socket> & Result<&2, &2, Error, Bool>):
  match value:
    case None{}: IO.pure(Maybe<&1, Socket> & Result<&2, &2, Error, Bool>, (None{}, Done{False{}}))
    case Some{socket}:
      do IO<Maybe<&1, Socket> & Result<&2, &2, Error, Bool>>:
        pair : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.shutdown(socket)
        shutdown(pair)

# Concurrent cancellation attempts serialize on the separate descriptor, not
# on the socket held by IO. Only the first attempt invokes shutdown; even an
# error retires the interrupt descriptor. Shutdown is destructive, not reusable
# per-operation cancellation. Buffered data may still be returned by pending IO.
def cancel(handle: Handle) -> IO(Result<&2, &2, Error, Bool>):
  match handle:
    case Handle{resource}: Resource.run(Maybe<&1, Socket>, Result<&2, &2, Error, Bool>, resource, cancelOwned)

def closeCopy(value: Maybe<&1, Socket>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{socket}: Socket.close(socket)

# Join all users of the handle before disposal. This closes only our descriptor:
# normal completion must not shut down another live owner of the connection.
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{resource}:
      do IO<Unit>:
        value : Maybe<&1, Socket> <- Resource.retire(Maybe<&1, Socket>, resource)
        closeCopy(value)

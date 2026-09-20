import Base
import ./socket-endpoint.bend as Endpoint
import ./url-ipv4.bend as IPv4
import ./url-ipv6.bend as IPv6

type Route is Data:
  Route{local: Endpoint.Endpoint, remote: Endpoint.Endpoint}

type Owner is Type:
  Owner{socket: Socket, route: Route}

type Error is Data:
  Binding{code: U32, message: String}
  Association{code: U32, message: String}
  Inspection{error: Endpoint.Error}

def family(destination: Endpoint.Endpoint) -> U32:
  match destination:
    case Endpoint.V4{_, _}: 4
    case Endpoint.V6{_, _, _}: 6

def associate(socket: Socket, destination: Endpoint.Endpoint) -> IO(Socket & Result<&1, &1, U32 & String, Unit>):
  match destination:
    case Endpoint.V4{IPv4.Address{address}, port}: UDP.connect_peer(socket, 4, address, 0, 0, 0, port, 0)
    case Endpoint.V6{IPv6.Address{a,b,c,d}, port, scope}: UDP.connect_peer(socket, 6, a, b, c, d, port, scope)

def remote(local: Endpoint.Endpoint, pair: Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint>) -> IO(Result<&2, &1, Error, Owner>):
  match pair:
    case (socket, Fail{error}):
      do IO<Result<&2, &1, Error, Owner>>:
        Socket.close(socket)
        return Fail{Inspection{error}}
    case (socket, Done{peer}): IO.pure(Result<&2, &1, Error, Owner>, Done{Owner{socket, Route{local, peer}}})

def local(pair: Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint>) -> IO(Result<&2, &1, Error, Owner>):
  match pair:
    case (socket, Fail{error}):
      do IO<Result<&2, &1, Error, Owner>>:
        Socket.close(socket)
        return Fail{Inspection{error}}
    case (socket, Done{address}):
      do IO<Result<&2, &1, Error, Owner>>:
        peer : Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Peer{})
        remote(address, peer)

def associated(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Result<&2, &1, Error, Owner>):
  match pair:
    case (socket, Fail{(code, message)}):
      do IO<Result<&2, &1, Error, Owner>>:
        Socket.close(socket)
        return Fail{Association{code, message}}
    case (socket, Done{_}):
      do IO<Result<&2, &1, Error, Owner>>:
        address : Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
        local(address)

def bound(destination: Endpoint.Endpoint, result: Result<&1, &1, U32 & String, Socket>) -> IO(Result<&2, &1, Error, Owner>):
  match result:
    case Fail{(code, message)}: IO.pure(Result<&2, &1, Error, Owner>, Fail{Binding{code, message}})
    case Done{socket}:
      do IO<Result<&2, &1, Error, Owner>>:
        result : Socket & Result<&1, &1, U32 & String, Unit> <- associate(socket, destination)
        associated(result)

# Numeric peer association selects the local route without sending a packet.
# Every setup failure closes the socket; success transfers its affine owner.
def create(+destination: Endpoint.Endpoint) -> IO(Result<&2, &1, Error, Owner>):
  do IO<Result<&2, &1, Error, Owner>>:
    result : Result<&1, &1, U32 & String, Socket> <- UDP.bind_family(family(destination), 0)
    bound(destination, result)

def close(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{socket, _}: Socket.close(socket)

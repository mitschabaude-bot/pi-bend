import Base
import ./url-ipv4.bend as IPv4
import ./url-ipv6.bend as IPv6

type Side is Data:
  Local{}
  Peer{}

type Endpoint is Data:
  V4{address: IPv4.Address, port: U32}
  V6{address: IPv6.Address, port: U32, scope: U32}

type Error is Data:
  SocketError{code: U32, message: String}
  InvalidFamily{family: U32}

def selector(side: Side) -> U32:
  match side:
    case Local{}: 0
    case Peer{}: 1

def endpoint(family: U32, a: U32, b: U32, c: U32, d: U32, port: U32, scope: U32) -> Result<&2, &2, Error, Endpoint>:
  match family:
    case 4: Done{V4{IPv4.Address{a}, port}}
    case 6: Done{V6{IPv6.Address{a, b, c, d}, port, scope}}
    case value: Fail{InvalidFamily{value}}

def value(result: Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32>) -> Result<&2, &2, Error, Endpoint>:
  match result:
    case Fail{(code, message)}: Fail{SocketError{code, message}}
    case Done{(family, a, b, c, d, port, scope)}: endpoint(family, a, b, c, d, port, scope)

def converted(pair: Socket & Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32>) -> Socket & Result<&2, &2, Error, Endpoint>:
  match pair:
    case (socket, result): (socket, value(result))

# Observe numeric endpoint metadata without consuming, duplicating or changing
# the connection. The same affine socket is returned on success and failure.
def get(socket: Socket, side: Side) -> IO(Socket & Result<&2, &2, Error, Endpoint>):
  do IO<Socket & Result<&2, &2, Error, Endpoint>>:
    result : Socket & Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32> <- Socket.endpoint(socket, selector(side))
    return converted(result)

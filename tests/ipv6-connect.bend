import Base
import ../packages/runtime/src/ipv6-connect.bend as Connect
import ../packages/runtime/src/url.bend as IPv6
import ../packages/runtime/test/utf8-runner.bend as Scalar

def received(result: Socket & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match result:
    case (socket, Done{value}):
      do IO<Unit>:
        Socket.close(socket)
        IO.print("ok:" ++ value)
    case (socket, Fail{(code, _) }):
      do IO<Unit>:
        Socket.close(socket)
        IO.print("read-error:" ++ U32.show(code))

def sent(result: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case (socket, Done{_}):
      do IO<Unit>:
        result : Socket & Result<&1, &1, U32 & String, String> <- TCP.recv(socket, 1)
        received(result)
    case (socket, Fail{(code, _) }):
      do IO<Unit>:
        Socket.close(socket)
        IO.print("send-error:" ++ U32.show(code))

def connected(result: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match result:
    case Fail{(code, _)}: IO.print("error:" ++ U32.show(code))
    case Done{socket}:
      do IO<Unit>:
        result : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(socket, "ping")
        sent(result)

def repeat(count: Nat, +address: IPv6.Ipv6Address, +port: U32, +scope: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, Socket> <- Connect.connect(address, port, scope)
        connected(result)
        repeat(rest, address, port, scope)

def parsed(result: Result<&2, &2, IPv6.Ipv6AddressError, IPv6.Ipv6Address>, port: U32, scope: U32) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "invalid test address")
    case Done{address}: repeat(64n, address, port, scope)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case address <> port <> scope <> Nil{}: parsed(IPv6.parseIpv6(address), Scalar.decimal(port, 0), Scalar.decimal(scope, 0))
    case _: IO.die(Unit, 1, "expected IPv6 address, port and scope")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

import Base
import ../packages/runtime/src/socket-interrupt.bend as Interrupt
import ./tcp-bytes-probe.bend as Probe
import ./tcp-bytes-contract.bend as Contract
import ./tcp-bytes-backpressure.bend as Payload

# Fixtures use a loopback peer which holds its connection open until shutdown.
def owner(pair: Socket & Result<&2, &1, Interrupt.Error, Interrupt.Owner>) -> IO(Socket & Interrupt.Owner):
  match pair:
    case (socket, Done{owner}): IO.pure(Socket & Interrupt.Owner, (socket, owner))
    case (socket, Fail{_}):
      do IO<Socket & Interrupt.Owner>:
        Socket.close(socket)
        IO.die(Socket & Interrupt.Owner, 1, "interrupt creation failed")

def winner(value: Result<&2, &2, Interrupt.Error, Bool>) -> IO(Bool):
  match value:
    case Done{won}: IO.pure(Bool, won)
    case Fail{_}: IO.die(Bool, 1, "shutdown failed")

def require(value: Bool, text: String) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, text)

def cancelLater(+handle: Interrupt.Handle) -> IO(Bool):
  do IO<Bool>:
    IO.sleep(100)
    value : Result<&2, &2, Interrupt.Error, Bool> <- Interrupt.cancel(handle)
    winner(value)

def eof(pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match pair:
    case (socket, Done{Nil{}}): Socket.close(socket)
    case (socket, _):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "shutdown did not end read")

def writeFailed(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (socket, Fail{(0, _)}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "zero error code")
    case (socket, Fail{_}): Socket.close(socket)
    case (socket, Done{_}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "send completed without backpressure")

def blocked(socket: Socket, write: Bool) -> IO(Unit):
  match write:
    case False{}:
      do IO<Unit>:
        read : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 1)
        eof(read)
    case True{}:
      do IO<Unit>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, Payload.payload(256n, Nil{}))
        writeFailed(sent)

def cancelled(socket: Socket, write: Bool, pair: Interrupt.Owner & Interrupt.Handle) -> IO(Unit):
  match pair:
    case (owner, +handle):
      do IO<Unit>:
        first : Chan(Bool) <- IO.fork(Bool, cancelLater(handle))
        second : Chan(Bool) <- IO.fork(Bool, cancelLater(handle))
        blocked(socket, write)
        +a : Bool <- IO.join(Bool, first)
        +b : Bool <- IO.join(Bool, second)
        require((a || b) && Bool.not(a && b), "expected one cancellation winner")
        again : Result<&2, &2, Interrupt.Error, Bool> <- Interrupt.cancel(handle)
        won : Bool <- winner(again)
        require(Bool.not(won), "repeated cancellation won")
        Interrupt.dispose(owner)

def run(write: Bool, pair: Socket & Interrupt.Owner) -> IO(Unit):
  match pair:
    case (socket, owner): cancelled(socket, write, Interrupt.borrow(owner))

def loop(count: Nat, +port: U32, +write: Bool) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        acquired : Socket & Result<&2, &1, Interrupt.Error, Interrupt.Owner> <- Interrupt.create(socket)
        pair : Socket & Interrupt.Owner <- owner(acquired)
        run(write, pair)
        loop(rest, port, write)

def echo(pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match pair:
    case (socket, Done{78 <> Nil{}}): Socket.close(socket)
    case (socket, _):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "normal disposal shut down the connection")

def normal(pair: Socket & Interrupt.Owner) -> IO(Unit):
  match pair:
    case (socket, owner):
      do IO<Unit>:
        Interrupt.dispose(owner)
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, 78 <> Nil{})
        socket : Socket <- Contract.sent(sent)
        read : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 1)
        echo(read)

# Keep the interrupt owner after closing the original fd, then open a new
# connection. Interrupting the old connection must not touch the new one.
def retainedHandle(port: U32, socket: Socket, pair: Interrupt.Owner & Interrupt.Handle) -> IO(Unit):
  match pair:
    case (owner, handle):
      do IO<Unit>:
        Socket.close(socket)
        fresh : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        cancelled : Result<&2, &2, Interrupt.Error, Bool> <- Interrupt.cancel(handle)
        won : Bool <- winner(cancelled)
        require(won, "retained interrupt did not run")
        Interrupt.dispose(owner)
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(fresh, 78 <> Nil{})
        fresh : Socket <- Contract.sent(sent)
        read : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(fresh, 1)
        echo(read)

def retained(port: U32, pair: Socket & Interrupt.Owner) -> IO(Unit):
  match pair:
    case (socket, owner): retainedHandle(port, socket, Interrupt.borrow(owner))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +port : U32 <- IO.pure(U32, Probe.port(args))
    socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
    acquired : Socket & Result<&2, &1, Interrupt.Error, Interrupt.Owner> <- Interrupt.create(socket)
    pair : Socket & Interrupt.Owner <- owner(acquired)
    normal(pair)
    loop(12n, port, False{})
    loop(12n, port, True{})
    socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
    acquired : Socket & Result<&2, &1, Interrupt.Error, Interrupt.Owner> <- Interrupt.create(socket)
    pair : Socket & Interrupt.Owner <- owner(acquired)
    retained(port, pair)
    IO.print("PASS socket interruption")

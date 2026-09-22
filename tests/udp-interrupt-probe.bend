import Base
import ../packages/runtime/src/socket.bend as Interrupt
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./udp-bytes.bend as Datagram

def cancellation(result: Result<&2, &2, Interrupt.InterruptError, Bool>) -> IO(Unit):
  match result:
    case Done{_}: IO.print("shutdown:ok")
    case Fail{Interrupt.InterruptError{code, _}}: IO.print("shutdown:" ++ U32.show(code))

def cancelLater(handle: Interrupt.Handle) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(20)
    result : Result<&2, &2, Interrupt.InterruptError, Bool> <- Interrupt.cancelInterrupt(handle)
    cancellation(result)

def borrowed(socket: Socket, pair: Interrupt.InterruptOwner & Interrupt.Handle) -> IO(Unit):
  match pair:
    case (owner, handle):
      do IO<Unit>:
        task : Chan(Unit) <- IO.fork(Unit, cancelLater(handle))
        value : Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>> <- UDP.recv_bytes(socket, 1024)
        socket : Socket <- Datagram.received(value)
        Socket.close(socket)
        IO.join(Unit, task)
        Interrupt.dispose(owner)

def acquired(pair: Socket & Result<&2, &1, Interrupt.InterruptError, Interrupt.InterruptOwner>) -> IO(Unit):
  match pair:
    case (socket, Done{owner}): borrowed(socket, Interrupt.borrow(owner))
    case (socket, Fail{_}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "duplicate failed")

def loop(count: Nat, +family: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.print("done")
    case Succ{rest}:
      do IO<Unit>:
        socket : Socket <- IO.try(Socket, UDP.bind_family(family, 0))
        pair : Socket & Result<&2, &1, Interrupt.InterruptError, Interrupt.InterruptOwner> <- Interrupt.createInterrupt(socket)
        acquired(pair)
        loop(rest, family)

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> count <> Nil{}: loop(U32.to_nat(Scalar.decimal(count, 0)), Scalar.decimal(family, 0))
    case _: IO.die(Unit, 1, "expected family count")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)

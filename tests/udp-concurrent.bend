import Base
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./udp-cancel.bend as Read
import ./udp-write.bend as Write

type Pending is Type:
  Pending{reader: Chan(Socket), readCancel: UDPReadCancel, writer: UDPWrite, writeCancel: UDPWriteCancel}

type Retired is Data:
  Retired{readCancel: UDPReadCancel, writeCancel: UDPWriteCancel}

def readWait(read: UDPRead) -> IO(Socket):
  do IO<Socket>:
    result : Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>> <- UDPRead.wait(read)
    Read.cancelled(result)

def pending(read: UDPRead & UDPReadCancel, write: UDPWrite & UDPWriteCancel) -> IO(Pending):
  match read, write:
    case (reader, readCancel), (writer, writeCancel):
      do IO<Pending>:
        task : Chan(Socket) <- IO.fork(Socket, readWait(reader))
        return Pending{task, readCancel, writer, writeCancel}

def create(count: Nat, +family: U32, +bytes: List<&2, U32>, owned: List<&1, Pending>) -> IO(List<&1, Pending>):
  match count:
    case Zero{}: IO.pure(List<&1, Pending>, owned)
    case Succ{rest}:
      do IO<List<&1, Pending>>:
        readSocket : Socket <- IO.try(Socket, UDP.bind_family(family, 0))
        writeSocket : Socket <- IO.try(Socket, UDP.bind_family(family, 0))
        reader : UDPRead & UDPReadCancel <- UDPRead.new(readSocket, 65535)
        writer : UDPWrite & UDPWriteCancel <- UDPWrite.new(writeSocket, family, Bool.pick(U32, U32.is_eq(family, 4), 2130706433, 0), 0, 0, Bool.pick(U32, U32.is_eq(family, 6), 1, 0), 53, 0, bytes)
        item : Pending <- pending(reader, writer)
        create(rest, family, bytes, item <> owned)

def stale(handles: List<&2, Retired>) -> IO(Unit):
  match handles:
    case Nil{}: IO.pure(Unit, Unit{})
    case Retired{readCancel, writeCancel} <> rest:
      do IO<Unit>:
        readWon : Bool <- UDPRead.cancel(readCancel)
        writeWon : Bool <- UDPWrite.cancel(writeCancel)
        Read.require(Bool.not(readWon || writeWon))
        stale(rest)

def writeCancelled(pair: Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>>) -> IO(Socket):
  match pair:
    case (socket, None{}): IO.pure(Socket, socket)
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "cancelled write completed")

def finishWrite(release: Bool, writer: UDPWrite, +handle: UDPWriteCancel) -> IO(Socket):
  match release:
    case True{}: UDPWrite.release(writer)
    case False{}:
      do IO<Socket>:
        won : Bool <- UDPWrite.cancel(handle)
        Read.require(won)
        again : Bool <- UDPWrite.cancel(handle)
        Read.require(Bool.not(again))
        result : Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>> <- UDPWrite.wait(writer)
        writeCancelled(result)

def retire(owned: List<&1, Pending>, +release: Bool, saved: List<&2, Retired>) -> IO(List<&2, Retired>):
  match owned:
    case Nil{}: IO.pure(List<&2, Retired>, saved)
    case Pending{reader, +readCancel, writer, +writeCancel} <> rest:
      do IO<List<&2, Retired>>:
        won : Bool <- UDPRead.cancel(readCancel)
        Read.require(won)
        again : Bool <- UDPRead.cancel(readCancel)
        Read.require(Bool.not(again))
        readSocket : Socket <- IO.join(Socket, reader)
        writeSocket : Socket <- finishWrite(release, writer, writeCancel)
        Socket.close(readSocket)
        Socket.close(writeSocket)
        retire(rest, Bool.not(release), Retired{readCancel, writeCancel} <> saved)

def waves(count: Nat, +width: Nat, +family: U32, +bytes: List<&2, U32>, old: List<&2, Retired>) -> IO(Unit):
  match count:
    case Zero{}: stale(old)
    case Succ{rest}:
      do IO<Unit>:
        owned : List<&1, Pending> <- create(width, family, bytes, Nil{})
        stale(old)
        IO.sleep(20)
        +handles : List<&2, Retired> <- retire(owned, False{}, Nil{})
        stale(handles)
        waves(rest, width, family, bytes, handles)

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> width <> count <> size <> Nil{}:
      do IO<Unit>:
        waves(U32.to_nat(Scalar.decimal(count, 0)), U32.to_nat(Scalar.decimal(width, 0)), Scalar.decimal(family, 0), Write.payload(U32.to_nat(Scalar.decimal(size, 0)), 0, False{}, Nil{}), Nil{})
        IO.print("ok")
    case _: IO.die(Unit, 1, "expected family width waves payload-size")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)

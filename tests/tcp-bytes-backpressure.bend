import Base
import ./tcp-bytes-probe.bend as Probe
import ./tcp-bytes-contract.bend as Contract
import ./tcp-bytes-errors.bend as Errors

def block(remaining: Nat, +byte: U32, bytes: List<&2, U32>) -> List<&2, U32>:
  match remaining:
    case 0n: bytes
    case 1n+rest: block(rest, (byte - 1 : U32), byte <> bytes)

def payload(blocks: Nat, bytes: List<&2, U32>) -> List<&2, U32>:
  match blocks:
    case 0n: bytes
    case 1n+rest: payload(rest, block(256n, 255, bytes))

def acknowledged(result: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match result:
    case (socket, Done{42 <> Nil{}}):
      do IO<Unit>:
        eof : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 1)
        socket : Socket <- Contract.emptyRead(eof)
        Socket.close(socket)
        IO.print("PASS")
    case (socket, _):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "missing transfer acknowledgment")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", Probe.port(arguments)))
    gate : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 1)
    socket : Socket <- Errors.ready(gate)
    sent : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, payload(256n, Nil{}))
    socket : Socket <- Contract.sent(sent)
    ack : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 1)
    acknowledged(ack)

import Base
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./socket-endpoint.bend as Metadata
import ./udp-bytes.bend as Bytes
import ./udp-write.bend as Write

def connect(socket: Socket, +family: U32, port: U32, +mode: String) -> IO(Socket):
  do IO<Socket>:
    result : Socket & Result<&1, &1, U32 & String, Unit> <- UDP.connect_peer(socket, Bool.pick(U32, String.eq(mode, "family"), 7, family), Bool.pick(U32, U32.is_eq(family, 4), 2130706433, 0), Bool.pick(U32, String.eq(mode, "word"), 1, 0), 0, Bool.pick(U32, U32.is_eq(family, 6), 1, 0), Bool.pick(U32, String.eq(mode, "zero"), 0, Bool.pick(U32, String.eq(mode, "large"), 65536, port)), Bool.pick(U32, String.eq(mode, "scope"), 1, 0))
    Write.sent(result)

def invalid(mode: String, family: U32, port: U32, socket: Socket) -> IO(Socket):
  match mode:
    case "ok": IO.pure(Socket, socket)
    case other: connect(socket, family, port, other)

def exchange(socket: Socket, +family: U32, +port: U32) -> IO(Socket):
  do IO<Socket>:
    socket : Socket <- connect(socket, family, port, "ok")
    local : Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
    socket : Socket <- Metadata.observed(local)
    remote : Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Peer{})
    socket : Socket <- Metadata.observed(remote)
    sent : Socket & Result<&1, &1, U32 & String, Unit> <- UDP.send_bytes(socket, family, Bool.pick(U32, U32.is_eq(family, 4), 2130706433, 0), 0, 0, Bool.pick(U32, U32.is_eq(family, 6), 1, 0), port, 0, 0 <> 255 <> Nil{})
    socket : Socket <- Write.sent(sent)
    packet : Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>> <- UDP.recv_bytes(socket, 16)
    Bytes.received(packet)

def run(+family: U32, +first: U32, second: U32, mode: String) -> IO(Unit):
  do IO<Unit>:
    socket : Socket <- IO.try(Socket, UDP.bind_family(family, 0))
    socket : Socket <- invalid(mode, family, first, socket)
    socket : Socket <- exchange(socket, family, first)
    socket : Socket <- exchange(socket, family, second)
    Socket.close(socket)

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> first <> second <> mode <> Nil{}: run(Scalar.decimal(family, 0), Scalar.decimal(first, 0), Scalar.decimal(second, 0), mode)
    case _: IO.die(Unit, 1, "expected family first-port second-port mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)

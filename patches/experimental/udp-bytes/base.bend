
# Consume one datagram. max is 0..65535; larger limits fail with EINVAL
# without consuming a packet. Return numeric peer, truncation, and raw bytes.
# Empty datagrams are successful empty lists, never EOF. Socket stays owned.
def UDP.recv_bytes(socket: Socket, max: U32) ->
  IO(Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>):
  import "./effs/udp_recv_bytes.c"
  import "./effs/udp_recv_bytes.js"

# Bind a wildcard datagram socket for exactly family 4 or 6. IPv6 is v6-only.
# port=0 requests an ephemeral port; ports above 65535 fail with EINVAL.
def UDP.bind_family(family: U32, port: U32) -> IO(Result<&1, &1, U32 & String, Socket>):
  import "./effs/udp_bind_family.c"
  import "./effs/udp_bind_family.js"

# Send one raw datagram to a numeric endpoint. Destination port is 1..65535.
# IPv4 requires b/c/d/scope=0. Validate all bytes before calling sendto.
def UDP.send_bytes(socket: Socket, family: U32, a: U32, b: U32, c: U32, d: U32, port: U32, scope: U32, bytes: List<&2, U32>) ->
  IO(Socket & Result<&1, &1, U32 & String, Unit>):
  import "./effs/udp_send_bytes.c"
  import "./effs/udp_send_bytes.js"

# One-shot owned receive and independently copyable cancellation capability.
# wait consumes the operation, returning its socket and None on cancellation.
# Some contains the ordinary packet/error result. release returns an unstarted
# operation's socket. Completion retires the capability; stale cancels are false.
law UDPRead:
  Type
law UDPReadCancel:
  Data

def UDPRead.new(socket: Socket, max: U32) -> IO(UDPRead & UDPReadCancel):
  import "./effs/udp_recv_bytes.c"
  import "./effs/udp_recv_bytes.js"
def UDPRead.wait(read: UDPRead) -> IO(Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>>):
  import "./effs/udp_recv_bytes.c"
  import "./effs/udp_recv_bytes.js"
def UDPRead.cancel(handle: UDPReadCancel) -> IO(Bool):
  import "./effs/udp_recv_bytes.c"
  import "./effs/udp_recv_bytes.js"
def UDPRead.release(read: UDPRead) -> IO(Socket):
  import "./effs/udp_recv_bytes.c"
  import "./effs/udp_recv_bytes.js"

# Owned one-shot send. new validates/buffers without transmitting. wait consumes
# the operation and returns the socket with None for cancellation or Some result.
# release discards an unstarted send. Retired cancellation handles return False.
law UDPWrite:
  Type
law UDPWriteCancel:
  Data

def UDPWrite.new(socket: Socket, family: U32, a: U32, b: U32, c: U32, d: U32, port: U32, scope: U32, bytes: List<&2, U32>) -> IO(UDPWrite & UDPWriteCancel):
  import "./effs/udp_send_bytes.c"
  import "./effs/udp_send_bytes.js"
def UDPWrite.wait(write: UDPWrite) -> IO(Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>>):
  import "./effs/udp_send_bytes.c"
  import "./effs/udp_send_bytes.js"
def UDPWrite.cancel(handle: UDPWriteCancel) -> IO(Bool):
  import "./effs/udp_send_bytes.c"
  import "./effs/udp_send_bytes.js"
def UDPWrite.release(write: UDPWrite) -> IO(Socket):
  import "./effs/udp_send_bytes.c"
  import "./effs/udp_send_bytes.js"

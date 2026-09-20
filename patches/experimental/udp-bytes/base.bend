
# Consume one datagram. max is 0..65535; larger limits fail with EINVAL
# without consuming a packet. Return numeric peer, truncation, and raw bytes.
# Empty datagrams are successful empty lists, never EOF. Socket stays owned.
def UDP.recv_bytes(socket: Socket, max: U32) ->
  IO(Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>):
  import "./effs/udp_recv_bytes.c"
  import "./effs/udp_recv_bytes.js"

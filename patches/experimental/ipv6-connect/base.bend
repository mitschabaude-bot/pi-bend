
# Four address words in network order, plus a checked 16-bit port and native
# interface scope ID. Address parsing and interface-name lookup are separate.
def TCP.connect_ipv6(a: U32, b: U32, c: U32, d: U32, port: U32, scope: U32) ->
  IO(Result<&1, &1, U32 & String, Socket>):
  import "./effs/tcp_connect_ipv6.c"
  import "./effs/tcp_connect_ipv6.js"

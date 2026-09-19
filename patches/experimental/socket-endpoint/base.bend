
# Numeric getsockname/getpeername. side=0 selects local, side=1 selects peer;
# other selectors fail with EINVAL. The affine socket is returned on all paths.
# Value: family (4/6), four address words, port, scope. IPv4 uses the first word
# and zeroes the rest. Address words/port are host integers in network order;
# scope is the native interface index. No address parsing or DNS occurs here.
def Socket.endpoint(socket: Socket, side: U32) ->
  IO(Socket & Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32>):
  import "./effs/socket_endpoint.c"
  import "./effs/socket_endpoint.js"

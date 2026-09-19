
# Duplicate the descriptor, retaining shared socket state. Both affine owners
# must be closed. The new descriptor is close-on-exec.
def Socket.duplicate(socket: Socket) ->
  IO(Socket & Result<&1, &1, U32 & String, Socket>):
  import "./effs/socket_duplicate.c"
  import "./effs/socket_duplicate.js"

# Shut down both directions, waking pending socket IO without closing either
# descriptor. Callers retain ownership and must close after IO has settled.
def TCP.shutdown(socket: Socket) ->
  IO(Socket & Result<&1, &1, U32 & String, Unit>):
  import "./effs/tcp_shutdown.c"
  import "./effs/tcp_shutdown.js"

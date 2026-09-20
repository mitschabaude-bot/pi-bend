
# Keep the platform errno representation outside pure Bend network policy.
def Socket.isConnectionRefused(code: U32) -> IO(Bool):
  import "./effs/socket_is_connection_refused.c"
  import "./effs/socket_is_connection_refused.js"

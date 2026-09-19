
# Owned connection attempt and independent cancellation capability.
# wait consumes the attempt, transferring a socket only on success. close
# consumes an unawaited attempt. Cancellation handles become harmless on retirement.
law Connect:
  Type

law ConnectCancel:
  Data

def Connect.ipv4(address: U32, port: U32) -> IO(Result<&1, &1, U32 & String, Connect & ConnectCancel>):
  import "./effs/connect.c"
  import "./effs/connect.js"

def Connect.ipv6(a: U32, b: U32, c: U32, d: U32, port: U32, scope: U32) -> IO(Result<&1, &1, U32 & String, Connect & ConnectCancel>):
  import "./effs/connect.c"
  import "./effs/connect.js"

def Connect.wait(owner: Connect) -> IO(Result<&1, &1, U32 & String, Socket>):
  import "./effs/connect.c"
  import "./effs/connect.js"

def Connect.cancel(handle: ConnectCancel) -> IO(Bool):
  import "./effs/connect.c"
  import "./effs/connect.js"

def Connect.close(owner: Connect) -> IO(Unit):
  import "./effs/connect.c"
  import "./effs/connect.js"

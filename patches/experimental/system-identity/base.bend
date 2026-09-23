
# Node-compatible operating-system identity for provider User-Agent headers.
def IO.system_identity() -> IO(Result<&1, &1, U32 & String, String & String & String>):
  import "./effs/system_identity.c"
  import "./effs/system_identity.js"

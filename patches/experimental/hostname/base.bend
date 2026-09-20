
# Operating-system hostname, independent of shell environment variables.
def IO.get_hostname() -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/get_hostname.c"
  import "./effs/get_hostname.js"

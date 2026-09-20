
# Resolve an OS interface name; zero is returned as a typed failure.
def IO.interface_index(name: String) -> IO(Result<&1, &1, U32 & String, U32>):
  import "./effs/interface_index.c"
  import "./effs/interface_index.js"

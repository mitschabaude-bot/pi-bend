
# OS entropy, at most 256 bytes per request. Zero returns an empty list.
# No fallback generator: unavailable entropy and OS failures remain errors.
def Entropy.bytes(count: U32) -> IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./effs/entropy_bytes.c"
  import "./effs/entropy_bytes.js"

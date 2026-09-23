import Base

# Matches pi-mono's Node User-Agent: pi (<os.platform> <os.release>; <os.arch>).
def format(identity: String & String & String) -> String:
  match identity:
    case (platform, release, arch): "pi (" ++ platform ++ " " ++ release ++ "; " ++ arch ++ ")"

def normalized(identity: Result<&1, &1, U32 & String, String & String & String>) -> Result<&1, &1, U32 & String, String>:
  match identity:
    case Fail{cause}: Fail{cause}
    case Done{value}: Done{format(value)}

def get() -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    identity : Result<&1, &1, U32 & String, String & String & String> <- IO.system_identity()
    return normalized(identity)

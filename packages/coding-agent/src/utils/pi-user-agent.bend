import Base

# upstream utils/pi-user-agent.ts: `pi/<version> (<platform>; <runtime>; <arch>)`
# for pi.dev requests. Platform and architecture are Node's names from the
# system identity (linux, x64). The runtime is this native Bend build rather
# than upstream's bun/<version> or node/<version>.
def runtime() -> String: "bend/2.0.7"

def formatted(+version: String, identity: Result<&1, &1, U32 & String, String & String & String>) -> String:
  match identity:
    case Done{(platform, _, arch)}: "pi/" ++ version ++ " (" ++ platform ++ "; " ++ runtime() ++ "; " ++ arch ++ ")"
    case Fail{_}: "pi/" ++ version ++ " (unknown; " ++ runtime() ++ "; unknown)"

def getPiUserAgent(+version: String) -> IO(String):
  do IO<String>:
    identity : Result<&1, &1, U32 & String, String & String & String> <- IO.system_identity()
    return formatted(version, identity)

import Base

# upstream utils/pi-user-agent.ts: `pi/<version> (<platform>; <runtime>; <arch>)`
# for pi.dev requests. Platform and architecture are Node's names from the
# system identity (linux, x64). The runtime is this native Bend build rather
# than upstream's bun/<version> or node/<version>.
def runtime() -> String: "bend/2.0.7"

def productFormatted(+product: String, +version: String, identity: Result<&1, &1, U32 & String, String & String & String>) -> String:
  match identity:
    case Done{(platform, _, arch)}: product ++ "/" ++ version ++ " (" ++ platform ++ "; " ++ runtime() ++ "; " ++ arch ++ ")"
    case Fail{_}: product ++ "/" ++ version ++ " (unknown; " ++ runtime() ++ "; unknown)"

def formatted(+version: String, identity: Result<&1, &1, U32 & String, String & String & String>) -> String: productFormatted("pi", version, identity)

def productUserAgent(+product: String, +version: String) -> IO(String):
  do IO<String>:
    identity : Result<&1, &1, U32 & String, String & String & String> <- IO.system_identity()
    return productFormatted(product, version, identity)

def getPiUserAgent(+version: String) -> IO(String): productUserAgent("pi", version)

# The same shape naming this port, for the pi.dev requests that identify the
# fork rather than pi (the remote model catalog; docs/scope-decisions.md).
def getPiBendUserAgent(+version: String) -> IO(String): productUserAgent("pi-bend", version)

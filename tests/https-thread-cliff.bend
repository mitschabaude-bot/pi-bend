import Base
import ../packages/coding-agent/src/utils/tools-manager.bend as Tools
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime

def shown(value: Tools.Outcome(String)) -> String:
  match value:
    case Done{v}: "ok " ++ v
    case Fail{m}: "error " ++ m

def ms(t: U32 & U32) -> String:
  match t:
    case Tuple{h,l}: U32.show(h) ++ " " ++ U32.show(l)

def stamp(label: String) -> IO(Unit):
  do IO<Unit>:
    t : U32 & U32 <- IO.monotonicNanoseconds()
    IO.print(label ++ " " ++ ms(t))

def go(transport: Runtime.Outcome(Runtime.Transport)) -> IO(Unit):
  match transport:
    case Fail{m}: IO.print(m)
    case Done{Runtime.Transport{a,r,+fetch}}:
      do IO<Unit>:
        stamp("transport")
        v : Tools.Outcome(String) <- Tools.getLatestVersion(fetch,Runtime.urlContext(),"BurntSushi/ripgrep")
        stamp("latest")
        IO.print(shown(v))
        v2 : Tools.Outcome(String) <- Tools.getLatestVersion(fetch,Runtime.urlContext(),"sharkdp/fd")
        stamp("latest2")
        IO.print(shown(v2))
        Runtime.disposeTransport(Runtime.Transport{a,r,fetch})

def main() -> IO(Unit):
  do IO<Unit>:
    stamp("start")
    t : Runtime.Outcome(Runtime.Transport) <- Runtime.createTransport("/etc/ssl/certs/ca-certificates.crt")
    go(t)

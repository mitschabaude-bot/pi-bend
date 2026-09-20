import Base
import ../packages/runtime/src/resolver-servers.bend as Servers
import ../packages/runtime/src/resolver-interface.bend as System
import ../packages/runtime/src/resolver-settings.bend as Settings
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/resolver-address.bend as Address
import ../packages/runtime/src/network-interface.bend as Interface
import ../packages/runtime/src/ipv6-scope.bend as Scope
import ../packages/runtime/src/dns-tcp-servers.bend as TCP
import ../packages/runtime/src/abortable-connect.bend as Connect
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ./resolver-settings.bend as SettingsTest

# A trace exposes order and exact call count, including duplicate interfaces.
def lookup(unused: Unit, +name: String) -> IO(Result<&2, &2, Interface.Error, U32>):
  do IO<Result<&2, &2, Interface.Error, U32>>:
    IO.print("lookup:" ++ name)
    return Bool.pick(Result<&2, &2, Interface.Error, U32>, String.eq(name, "known"), Done{7}, Fail{Interface.Error{19, "missing"}})

def source(unused: Unit, name: String) -> IO(Result<&2, &2, Interface.Error, U32>):
  lookup(unused, name)

def servers(values: List<&2, TCP.Server>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case TCP.Server{Connect.V4{IPv4.Address{value}}, port} <> rest:
      do IO<Unit>:
        IO.print("server:4:" ++ U32.show(value) ++ ":" ++ U32.show(port))
        servers(rest)
    case TCP.Server{Connect.V6{IPv6.Address{a,b,c,d}, scope}, port} <> rest:
      do IO<Unit>:
        IO.print("server:6:" ++ U32.show(a) ++ ":" ++ U32.show(b) ++ ":" ++ U32.show(c) ++ ":" ++ U32.show(d) ++ ":" ++ U32.show(scope) ++ ":" ++ U32.show(port))
        servers(rest)

def sourceError(value: Maybe<&2, Interface.Error>) -> String:
  match value:
    case None{}: "none"
    case Some{Interface.Error{code, _}}: U32.show(code)

def issues(values: List<&2, Servers.Issue<Interface.Error>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case Servers.Issue{position, Scope.InvalidScope{text, failure}} <> rest:
      do IO<Unit>:
        IO.print("issue:" ++ Nat.show(position) ++ ":" ++ text ++ ":" ++ sourceError(failure))
        issues(rest)

def report(value: Servers.Report<Interface.Error>) -> IO(Unit):
  match value:
    case Servers.Report{values, failures}:
      do IO<Unit>:
        servers(values)
        issues(failures)

def configured(value: Servers.Configuration<Interface.Error>) -> IO(Unit):
  match value:
    case Servers.Configuration{settings, endpoints}:
      do IO<Unit>:
        SettingsTest.report(settings)
        report(endpoints)

def prepare(real: Bool, settings: Settings.Settings) -> IO(Servers.Configuration<Interface.Error>):
  match real:
    case True{}: System.prepare(settings)
    case False{}: Servers.prepareWith(~Interface.Error, ~Unit, ~source, Unit{}, settings)

def run(empty: Bool, real: Bool, text: String) -> IO(Unit):
  match empty:
    case True{}:
      do IO<Unit>:
        result : Servers.Report<Interface.Error> <- Servers.resolveWith(~Interface.Error, ~Unit, ~source, Unit{}, Nil{})
        report(result)
    case False{}:
      do IO<Unit>:
        result : Servers.Configuration<Interface.Error> <- prepare(real, Settings.configure(Config.parse(text), Settings.Overrides{Some{"host.example"}, None{}, Nil{}}))
        configured(result)

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> text <> Nil{}: run(String.eq(mode, "empty"), String.eq(mode, "system"), text)
    case _: IO.die(Unit, 1, "expected mode configuration")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)

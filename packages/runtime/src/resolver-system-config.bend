import Base
import ./dns-tcp-servers.bend as TCP
import ./resolver-system-servers.bend as System
import ./resolver-servers.bend as Servers
import ./resolver-search.bend as Search
import ./resolver-options.bend as Options
import ./resolver-load.bend as Load
import ./resolver-configuration.bend as Resolver
import ./socket-endpoint.bend as Endpoint
import ./abortable-connect.bend as Connect
import ./dns-udp-plan.bend as Plan

# Retain the complete source report, including scope, hostname and file
# diagnostics, for the caller's configuration acceptance and reload policy.
type Prepared is Data:
  Prepared{source: System.Report, search: Search.Configuration, resolver: Resolver.Config<Endpoint.Endpoint>}

type Error<-DecodeError: Data> is Data:
  InvalidTransport{source: System.Report, error: Plan.Error}
  Loading{error: Load.Error<DecodeError>}
  InvalidOptions{source: System.Report, diagnostics: List<&2, Options.Diagnostic>}

# Preserve numeric IPv6 scope IDs and configured occurrence order.
def endpoint(server: TCP.Server) -> Endpoint.Endpoint:
  match server:
    case TCP.Server{Connect.V4{ip}, port}: Endpoint.V4{ip, port}
    case TCP.Server{Connect.V6{ip, scope}, port}: Endpoint.V6{ip, port, scope}

def endpoints(servers: List<&2, TCP.Server>) -> List<&2, Endpoint.Endpoint>:
  match servers:
    case Nil{}: Nil{}
    case first <> rest: endpoint(first) <> endpoints(rest)

def configured(-DecodeError: Data, source: System.Report, search: Search.Configuration, result: Result<&2, &2, Plan.Error, Resolver.Config<Endpoint.Endpoint>>) -> Result<&2, &2, Error<DecodeError>, Prepared>:
  match result:
    case Fail{error}: Fail{InvalidTransport{source, error}}
    case Done{resolver}: Done{Prepared{source, search, resolver}}

def checked(-DecodeError: Data, source: System.Report, servers: List<&2, TCP.Server>, milliseconds: U32, maximum: U32, result: Result<&2, &2, List<&2, Options.Diagnostic>, Search.Configuration>) -> Result<&2, &2, Error<DecodeError>, Prepared>:
  match result:
    case Fail{diagnostics}: Fail{InvalidOptions{source, diagnostics}}
    case Done{+search}: configured(DecodeError, source, search, Resolver.prepare(Endpoint.Endpoint, endpoints(servers), milliseconds, maximum, search))

# Strict option and transport-plan acceptance precede owner creation. Other
# diagnostics remain explicit in the complete source report on either outcome.
def prepare(-DecodeError: Data, milliseconds: U32, maximum: U32, source: System.Report) -> Result<&2, &2, Error<DecodeError>, Prepared>:
  match source:
    case System.Report{Servers.Configuration{+settings, Servers.Report{+servers, issues}}, hostname, unavailable}:
      checked(DecodeError, System.Report{Servers.Configuration{settings, Servers.Report{servers, issues}}, hostname, unavailable}, servers, milliseconds, maximum, Search.fromSettingsStrict(settings))

def loaded(-DecodeError: Data, milliseconds: U32, maximum: U32, result: Result<&2, &2, Load.Error<DecodeError>, System.Report>) -> Result<&2, &2, Error<DecodeError>, Prepared>:
  match result:
    case Fail{error}: Fail{Loading{error}}
    case Done{source}: prepare(DecodeError, milliseconds, maximum, source)

def loadWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat, milliseconds: U32, maximum: U32) -> IO(Result<&2, &2, Error<DecodeError>, Prepared>):
  do IO<Result<&2, &2, Error<DecodeError>, Prepared>>:
    source : Result<&2, &2, Load.Error<DecodeError>, System.Report> <- System.loadWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
    return loaded(DecodeError, milliseconds, maximum, source)

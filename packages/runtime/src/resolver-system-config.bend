import Base
import ./dns-tcp-servers.bend as TCP
import ./resolver-system-servers.bend as System
import ./resolver-servers.bend as Servers
import ./resolver-search.bend as Search
import ./resolver-options.bend as Options
import ./resolver-load.bend as Load
import ./dns-tcp-resolver.bend as Resolver

# Retain the complete source report, including scope, hostname and file
# diagnostics, for the caller's configuration acceptance and reload policy.
type Prepared is Data:
  Prepared{source: System.Report, search: Search.Configuration, resolver: Resolver.Config}

type Error<-DecodeError: Data> is Data:
  Loading{error: Load.Error<DecodeError>}
  InvalidOptions{source: System.Report, diagnostics: List<&2, Options.Diagnostic>}

def checked(-DecodeError: Data, source: System.Report, servers: List<&2, TCP.Server>, milliseconds: U32, maximum: U32, result: Result<&2, &2, List<&2, Options.Diagnostic>, Search.Configuration>) -> Result<&2, &2, Error<DecodeError>, Prepared>:
  match result:
    case Fail{diagnostics}: Fail{InvalidOptions{source, diagnostics}}
    case Done{+search}: Done{Prepared{source, search, Resolver.fromSearch(servers, milliseconds, maximum, search)}}

# Only option acceptance is decided here. Other diagnostics remain explicit in
# Prepared.source; loading a configuration does not allocate a resolver owner.
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

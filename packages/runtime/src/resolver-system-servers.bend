import Base
import ./resolver-system-linux.bend as Linux
import ./resolver-system.bend as System
import ./resolver-load.bend as Load
import ./resolver-hostname.bend as Hostname
import ./resolver-servers.bend as Servers
import ./resolver-interface.bend as Interface
import ./network-interface.bend as Network

type Report is Data:
  Report{configuration: Servers.Configuration<Network.Error>, hostnameFailure: Maybe<&2, Hostname.Failure>, unavailable: Maybe<&2, Linux.Unavailable>}

def loaded(-DecodeError: Data, result: Result<&2, &2, Load.Error<DecodeError>, Linux.Report>) -> IO(Result<&2, &2, Load.Error<DecodeError>, Report>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, Load.Error<DecodeError>, Report>, Fail{error})
    case Done{Linux.Report{System.Report{settings, hostnameFailure}, unavailable}}:
      do IO<Result<&2, &2, Load.Error<DecodeError>, Report>>:
        configuration : Servers.Configuration<Network.Error> <- Interface.prepare(settings)
        return Done{Report{configuration, hostnameFailure, unavailable}}

# Linux file policy, environment/hostname defaults and all interface lookups.
# Search/option interpretation is still a distinct configuration phase.
def loadWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, Load.Error<DecodeError>, Report>):
  do IO<Result<&2, &2, Load.Error<DecodeError>, Report>>:
    settings : Result<&2, &2, Load.Error<DecodeError>, Linux.Report> <- Linux.loadWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
    loaded(DecodeError, settings)

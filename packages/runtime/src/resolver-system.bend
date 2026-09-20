import Base
import ./resolver-environment.bend as Environment
import ./resolver-file.bend as File
import ./resolver-load.bend as Load
import ./resolver-hostname.bend as Hostname
import ./resolver-config.bend as Config
import ./resolver-settings.bend as Settings

type Report is Data:
  Report{settings: Settings.Settings, hostnameFailure: Maybe<&2, Hostname.Failure>}

def configured(entries: List<&2, Config.Entry>, values: Environment.Values, hostname: Hostname.Report) -> Report:
  match hostname:
    case Hostname.Report{name, failure}: Report{Settings.configure(entries, Environment.overrides(name, values)), failure}

def parsed(~DecodeError: Data, ~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, +values: Environment.Values, result: Result<&2, &2, File.Error<DecodeError>, List<&2, Config.Entry>>) -> IO(Result<&2, &2, Load.Error<DecodeError>, Report>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, Load.Error<DecodeError>, Report>, Fail{Load.File{error}})
    case Done{+entries}:
      do IO<Result<&2, &2, Load.Error<DecodeError>, Report>>:
        hostname : Hostname.Report <- Hostname.resolveWith(~Context, ~lookup, context, entries, values)
        return Done{configured(entries, values, hostname)}

# Hostname fallback is lazy: capture errors and file errors return first, and
# an environment/file search list suppresses the hostname call entirely.
def capturedWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, ~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, path: String, chunkSize: U32, byteLimit: Nat, capture: Result<&2, &2, Environment.Error, Environment.Values>) -> IO(Result<&2, &2, Load.Error<DecodeError>, Report>):
  match capture:
    case Fail{error}: IO.pure(Result<&2, &2, Load.Error<DecodeError>, Report>, Fail{Load.Environment{error}})
    case Done{values}:
      do IO<Result<&2, &2, Load.Error<DecodeError>, Report>>:
        entries : Result<&2, &2, File.Error<DecodeError>, List<&2, Config.Entry>> <- File.readWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
        parsed(~DecodeError, ~Context, ~lookup, context, values, entries)

def hostname(unused: Unit) -> IO(Result<&1, &1, U32 & String, String>):
  IO.get_hostname()

def loadWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, Load.Error<DecodeError>, Report>):
  do IO<Result<&2, &2, Load.Error<DecodeError>, Report>>:
    capture : Result<&2, &2, Environment.Error, Environment.Values> <- Environment.capture()
    capturedWith(~DecodeError, ~decode, ~Unit, ~hostname, Unit{}, path, chunkSize, byteLimit, capture)

import Base
import ./resolver-environment.bend as Environment
import ./resolver-file.bend as File
import ./resolver-settings.bend as Settings

type Error<-DecodeError: Data> is Data:
  Environment{error: Environment.Error}
  File{error: File.Error<DecodeError>}

def loaded(-DecodeError: Data, result: Result<&2, &2, File.Error<DecodeError>, Settings.Settings>) -> Result<&2, &2, Error<DecodeError>, Settings.Settings>:
  match result:
    case Fail{error}: Fail{File{error}}
    case Done{settings}: Done{settings}

# An injected environment capture can use the same file-loading path. A failed
# capture never opens the file or substitutes missing-variable defaults.
def captured(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, hostname: Maybe<&2, String>, path: String, chunkSize: U32, byteLimit: Nat, capture: Result<&2, &2, Environment.Error, Environment.Values>) -> IO(Result<&2, &2, Error<DecodeError>, Settings.Settings>):
  match capture:
    case Fail{error}: IO.pure(Result<&2, &2, Error<DecodeError>, Settings.Settings>, Fail{Environment{error}})
    case Done{values}:
      do IO<Result<&2, &2, Error<DecodeError>, Settings.Settings>>:
        result : Result<&2, &2, File.Error<DecodeError>, Settings.Settings> <- File.loadWith(~DecodeError, ~decode, path, chunkSize, byteLimit, Environment.overrides(hostname, values))
        return loaded(DecodeError, result)

# Capture environment before reading the file. Hostname discovery and decoding
# policy remain explicit inputs; errors do not become an incomplete config.
def loadWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, hostname: Maybe<&2, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, Error<DecodeError>, Settings.Settings>):
  do IO<Result<&2, &2, Error<DecodeError>, Settings.Settings>>:
    capture : Result<&2, &2, Environment.Error, Environment.Values> <- Environment.capture()
    captured(~DecodeError, ~decode, hostname, path, chunkSize, byteLimit, capture)

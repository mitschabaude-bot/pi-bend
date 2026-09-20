import Base
import ./file-fold.bend as FileFold
import ./bounded-file.bend as Bounded
import ./resolver-config.bend as Config
import ./resolver-settings.bend as Settings

# Decoding policy is supplied explicitly. This layer never substitutes missing
# files, decodes a partial read, or applies an incomplete configuration.
type Error<-DecodeError: Data> is Data:
  File{error: FileFold.Error}
  TooLarge{}
  Decode{error: DecodeError}

def decoded(-DecodeError: Data, result: Result<&2, &2, DecodeError, String>) -> Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>>:
  match result:
    case Fail{error}: Fail{Decode{error}}
    case Done{text}: Done{Config.parse(text)}

def parsed(-DecodeError: Data, result: Result<&2, &2, Bounded.Error<DecodeError>, String>) -> Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>>:
  match result:
    case Fail{Bounded.File{error}}: Fail{File{error}}
    case Fail{Bounded.TooLarge{}}: Fail{TooLarge{}}
    case Fail{Bounded.Decode{error}}: Fail{Decode{error}}
    case Done{text}: Done{Config.parse(text)}

def readWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>>):
  do IO<Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>>>:
    text : Result<&2, &2, Bounded.Error<DecodeError>, String> <- Bounded.readWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
    return parsed(DecodeError, text)

def configured(-DecodeError: Data, overrides: Settings.Overrides, result: Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>>) -> Result<&2, &2, Error<DecodeError>, Settings.Settings>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entries}: Done{Settings.configure(entries, overrides)}

def loadWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat, overrides: Settings.Overrides) -> IO(Result<&2, &2, Error<DecodeError>, Settings.Settings>):
  do IO<Result<&2, &2, Error<DecodeError>, Settings.Settings>>:
    entries : Result<&2, &2, Error<DecodeError>, List<&2, Config.Entry>> <- readWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
    return configured(DecodeError, overrides, entries)

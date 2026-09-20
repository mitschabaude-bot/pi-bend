import Base
import ./resolver-system.bend as System
import ./resolver-environment.bend as Environment
import ./resolver-file.bend as File
import ./file-fold.bend as Fold
import ./resolver-load.bend as Load
import ./resolver-config.bend as Config

# Linux errno values are confined to this platform policy. Only persistent
# open failures permit defaults; read/resource/decoder failures stay fatal.
type Unavailable is Data:
  Unavailable{code: U32, message: String}

type Selected is Data:
  Selected{entries: List<&2, Config.Entry>, unavailable: Maybe<&2, Unavailable>}

type Report is Data:
  Report{configuration: System.Report, unavailable: Maybe<&2, Unavailable>}

def permitsDefaults(+code: U32) -> Bool:
  U32.is_eq(code, 1) || U32.is_eq(code, 2) || U32.is_eq(code, 13) || U32.is_eq(code, 20) || U32.is_eq(code, 21) || U32.is_eq(code, 40)

def opened(-DecodeError: Data, allowed: Bool, code: U32, message: String) -> Result<&2, &2, File.Error<DecodeError>, Selected>:
  match allowed:
    case False{}: Fail{File.File{Fold.Open{code, message}}}
    case True{}: Done{Selected{Nil{}, Some{Unavailable{code, message}}}}

def select(-DecodeError: Data, result: Result<&2, &2, File.Error<DecodeError>, List<&2, Config.Entry>>) -> Result<&2, &2, File.Error<DecodeError>, Selected>:
  match result:
    case Done{entries}: Done{Selected{entries, None{}}}
    case Fail{File.File{Fold.Open{+code, message}}}: opened(DecodeError, permitsDefaults(code), code, message)
    case Fail{error}: Fail{error}

def reported(-DecodeError: Data, unavailable: Maybe<&2, Unavailable>, result: Result<&2, &2, Load.Error<DecodeError>, System.Report>) -> Result<&2, &2, Load.Error<DecodeError>, Report>:
  match result:
    case Fail{error}: Fail{error}
    case Done{configuration}: Done{Report{configuration, unavailable}}

def selectedWith(~DecodeError: Data, ~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, values: Environment.Values, result: Result<&2, &2, File.Error<DecodeError>, Selected>) -> IO(Result<&2, &2, Load.Error<DecodeError>, Report>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, Load.Error<DecodeError>, Report>, Fail{Load.File{error}})
    case Done{Selected{entries, unavailable}}:
      do IO<Result<&2, &2, Load.Error<DecodeError>, Report>>:
        configuration : Result<&2, &2, Load.Error<DecodeError>, System.Report> <- System.parsed(~DecodeError, ~Context, ~lookup, context, values, Done{entries})
        return reported(DecodeError, unavailable, configuration)

def parsedWith(~DecodeError: Data, ~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, values: Environment.Values, result: Result<&2, &2, File.Error<DecodeError>, List<&2, Config.Entry>>) -> IO(Result<&2, &2, Load.Error<DecodeError>, Report>):
  selectedWith(~DecodeError, ~Context, ~lookup, context, values, select(DecodeError, result))

# Environment capture precedes file access, including the fallback path.
# An unavailable file still allows LOCALDOMAIN/RES_OPTIONS and lazy hostname.
def capturedWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, ~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, path: String, chunkSize: U32, byteLimit: Nat, capture: Result<&2, &2, Environment.Error, Environment.Values>) -> IO(Result<&2, &2, Load.Error<DecodeError>, Report>):
  match capture:
    case Fail{error}: IO.pure(Result<&2, &2, Load.Error<DecodeError>, Report>, Fail{Load.Environment{error}})
    case Done{values}:
      do IO<Result<&2, &2, Load.Error<DecodeError>, Report>>:
        entries : Result<&2, &2, File.Error<DecodeError>, List<&2, Config.Entry>> <- File.readWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
        parsedWith(~DecodeError, ~Context, ~lookup, context, values, entries)

def loadWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, Load.Error<DecodeError>, Report>):
  do IO<Result<&2, &2, Load.Error<DecodeError>, Report>>:
    capture : Result<&2, &2, Environment.Error, Environment.Values> <- Environment.capture()
    capturedWith(~DecodeError, ~decode, ~Unit, ~System.hostname, Unit{}, path, chunkSize, byteLimit, capture)

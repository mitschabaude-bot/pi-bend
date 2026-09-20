import Base
import ./utf8-strict.bend as UTF8
import ./bounded-file.bend as File
import ./hosts-file.bend as Parser
import ./hosts.bend as Hosts

type Error<-DecodeError: Data> is Data:
  Loading{error: File.Error<DecodeError>}
  Parsing{error: Parser.Failure}

def parsed(-DecodeError: Data, result: Result<&2, &2, Parser.Failure, List<&2, Hosts.Entry<Parser.Address>>>) -> Result<&2, &2, Error<DecodeError>, List<&2, Hosts.Entry<Parser.Address>>>:
  match result:
    case Fail{error}: Fail{Parsing{error}}
    case Done{entries}: Done{entries}

def loaded(-DecodeError: Data, result: Result<&2, &2, File.Error<DecodeError>, String>) -> Result<&2, &2, Error<DecodeError>, List<&2, Hosts.Entry<Parser.Address>>>:
  match result:
    case Fail{error}: Fail{Loading{error}}
    case Done{text}: parsed(DecodeError, Parser.parse(text))

# Keep missing-file, IO, decoding, bounds and syntax failures distinct. The
# caller chooses source-order/fallback policy; none implies an empty database.
def readWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, Error<DecodeError>, List<&2, Hosts.Entry<Parser.Address>>>):
  do IO<Result<&2, &2, Error<DecodeError>, List<&2, Hosts.Entry<Parser.Address>>>>:
    text : Result<&2, &2, File.Error<DecodeError>, String> <- File.readWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
    return loaded(DecodeError, text)

# The standard entry point rejects malformed UTF-8 and strips one leading BOM.
# readWith remains available for an explicitly selected decoding policy.
def read(path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, Error<UTF8.Error>, List<&2, Hosts.Entry<Parser.Address>>>):
  readWith(~UTF8.Error, ~UTF8.decode, path, chunkSize, byteLimit)

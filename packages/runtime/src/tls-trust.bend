import Base
import ./x509.bend as X509
import ./pem.bend as PEM
import ./bounded-file.bend as File
import ./utf8-strict.bend as UTF8

# Configured certificates are distinct from peer evidence. This layer parses
# explicit configuration; certificate policy and path validity are checked at
# connection time. It does not silently choose an OS or bundled trust store.
type Error is Data:
  Read{cause: File.Error<UTF8.Error>}
  Text{cause: PEM.Error}
  Certificate{cause: X509.Error}
  UnsupportedLabel{label: String}
  EmptyBundle{}

def certificate(result: Result<&2,&2,X509.Error,X509.Certificate>) -> Result<&2,&2,Error,X509.Certificate>:
  match result:
    case Fail{cause}: Fail{Certificate{cause}}
    case Done{value}: Done{value}

def labelled(allowed: Bool, label: String, bytes: List<&2,U32>) -> Result<&2,&2,Error,X509.Certificate>:
  match allowed:
    case False{}: Fail{UnsupportedLabel{label}}
    case True{}: certificate(X509.parse(bytes))

def blocks(values: List<&2,PEM.Block>, reversed: List<&2,X509.Certificate>) -> Result<&2,&2,Error,List<&2,X509.Certificate>>:
  match values reversed:
    case Nil{} Nil{}: Fail{EmptyBundle{}}
    case Nil{} values: Done{List.reverse(&2,X509.Certificate,values)}
    case PEM.Block{+label,bytes} <> rest previous:
      Result.bind(&2,&2,Error,X509.Certificate,List<&2,X509.Certificate>,labelled(String.eq(label,"CERTIFICATE"),label,bytes), value => blocks(rest,value <> previous))

def parsed(result: Result<&2,&2,PEM.Error,List<&2,PEM.Block>>) -> Result<&2,&2,Error,List<&2,X509.Certificate>>:
  match result:
    case Fail{cause}: Fail{Text{cause}}
    case Done{values}: blocks(values,Nil{})

def parse(text: String) -> Result<&2,&2,Error,List<&2,X509.Certificate>>:
  parsed(PEM.decode(text))

def loaded(result: Result<&2,&2,File.Error<UTF8.Error>,String>) -> Result<&2,&2,Error,List<&2,X509.Certificate>>:
  match result:
    case Fail{cause}: Fail{Read{cause}}
    case Done{text}: parse(text)

# Read limits apply to the entire source file, including comments and newlines.
# bounded-file closes the descriptor before invoking any certificate decoder.
def load(path: String, byteLimit: Nat) -> IO(Result<&2,&2,Error,List<&2,X509.Certificate>>):
  do IO<Result<&2,&2,Error,List<&2,X509.Certificate>>>:
    result : Result<&2,&2,File.Error<UTF8.Error>,String> <- File.readWith(~UTF8.Error,~UTF8.decode,path,4096,byteLimit)
    return loaded(result)

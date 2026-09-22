import Base
import ../packages/runtime/src/tls-trust.bend as Trust
import ../packages/runtime/src/bounded.bend as File
import ../packages/runtime/src/x509.bend as X509
import ../packages/runtime/src/der.bend as DER
import ../packages/runtime/src/sha256.bend as SHA
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Decimal
import ./aes128-gcm.bend as Bytes

def error(cause: Trust.Error) -> String:
  match cause:
    case Trust.Read{File.File{_}}: "read"
    case Trust.Read{File.TooLarge{}}: "size"
    case Trust.Read{File.Decode{_}}: "utf8"
    case Trust.Text{_}: "pem"
    case Trust.Certificate{_}: "certificate"
    case Trust.UnsupportedLabel{label}: "label:" ++ label
    case Trust.EmptyBundle{}: "empty"

def hashResult(count: U32, result: Result<&2,&2,SHA.Error,SHA.Digest>) -> String:
  match result:
    case Fail{_}: "hash"
    case Done{value}: U32.show(count) ++ "|" ++ Bytes.show(SHA.toBytes(value))

def summarize(values: List<&2,X509.Certificate>, count: U32, result: Result<&2,&2,SHA.Error,SHA.State>) -> String:
  match values result:
    case _ Fail{_}: "hash"
    case Nil{} Done{state}: hashResult(count,SHA.finish(state))
    case X509.Certificate{tbs,_,_} <> rest Done{state}: summarize(rest,(count + 1 : U32),SHA.update(DER.encoded(tbs),state))

def show(result: Result<&2,&2,Trust.Error,List<&2,X509.Certificate>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{values}: summarize(values,0,Done{SHA.create()})

def file(parts: List<&2,String>) -> IO(String):
  match parts:
    case limit <> path <> Nil{}:
      do IO<String>:
        result : Result<&2,&2,Trust.Error,List<&2,X509.Certificate>> <- Trust.load(path,U32.to_nat(Decimal.decimal(limit,0)))
        return show(result)
    case _: IO.pure(String,"invalid")

def run(+text: String) -> IO(String):
  Bool.pick(Unit -> IO(String),String.starts_with(text,"file:"),
    unit => file(Split.split(String.drop(text,5n),':')),
    unit => IO.pure(String,show(Trust.parse(text))))(Unit{})

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        value : String <- run(head)
        IO.print(value)
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

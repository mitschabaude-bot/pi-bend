import Base
import ../packages/runtime/src/x509.bend as X
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/src/u64.bend as W
import ../packages/runtime/test/utf8-runner.bend as Decimal
import ./aes128-gcm.bend as Bytes

# DER parsing is outside the body timer. Policy preparation and all signature
# verification stay inside. Each command starts with fresh certificate values.
def certificates(values: List<&2,String>, reversed: List<&2,X.Certificate>) -> Result<&2,&2,X.Error,List<&2,X.Certificate>>:
  match values:
    case Nil{}: Done{List.reverse(&2,X.Certificate,reversed)}
    case "" <> rest: certificates(rest,reversed)
    case head <> rest:
      Result.bind(&2,&2,X.Error,X.Certificate,List<&2,X.Certificate>,X.parse(Bytes.bytes(head)), certificate => certificates(rest,certificate <> reversed))

def report(result: Result<&2,&2,X.Error,Unit>) -> String:
  match result:
    case Done{Unit{}}: "ok"
    case Fail{_}: "failed"

def printElapsed(value: W.U64) -> IO(Unit):
  match value:
    case W.U64{high,low}: IO.print(U32.show(high) ++ ":" ++ U32.show(low))

def elapsed(start: U32 & U32, finish: U32 & U32) -> IO(Unit):
  match start finish:
    case Tuple{sh,sl} Tuple{fh,fl}: printElapsed(W.subtract(W.U64{fh,fl},W.U64{sh,sl}))

def chain(steps: Nat, now: W.U64, leaf: Result<&2,&2,X.Error,X.Certificate>, peers: Result<&2,&2,X.Error,List<&2,X.Certificate>>, anchors: Result<&2,&2,X.Error,List<&2,X.Certificate>>) -> IO(Unit):
  match leaf peers anchors:
    case Done{leaf} Done{peers} Done{anchors}:
      do IO<Unit>:
        start : U32 & U32 <- IO.monotonicNanoseconds()
        IO.print(report(Result.bind(&2,&2,X.Error,X.PublicKey,Unit,X.verifyChain(steps,now,leaf,peers,anchors), key => Done{Unit{}})))
        finish : U32 & U32 <- IO.monotonicNanoseconds()
        elapsed(start,finish)
    case _ _ _: IO.print("parse-failed")

def signature(issuer: Result<&2,&2,X.Error,X.Certificate>, subject: Result<&2,&2,X.Error,X.Certificate>) -> IO(Unit):
  match issuer subject:
    case Done{issuer} Done{subject}:
      do IO<Unit>:
        start : U32 & U32 <- IO.monotonicNanoseconds()
        IO.print(report(Result.bind(&2,&2,X.Error,X.PublicKey,Unit,X.publicKey(issuer), key => X.verifySignature(key,subject))))
        finish : U32 & U32 <- IO.monotonicNanoseconds()
        elapsed(start,finish)
    case _ _: IO.print("parse-failed")

def run(parts: List<&2,String>) -> IO(Unit):
  match parts:
    case "limited" <> steps <> high <> low <> leaf <> peers <> anchors <> Nil{}:
      chain(U32.to_nat(Decimal.decimal(steps,0)),W.U64{Decimal.decimal(high,0),Decimal.decimal(low,0)},X.parse(Bytes.bytes(leaf)),certificates(Strings.split(peers,'|'),Nil{}),certificates(Strings.split(anchors,'|'),Nil{}))
    case "v" <> issuer <> subject <> Nil{}: signature(X.parse(Bytes.bytes(issuer)),X.parse(Bytes.bytes(subject)))
    case _: IO.print("invalid")

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        run(Strings.split(head,':'))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

import Base
import ../packages/runtime/src/p256.bend as P
import ../packages/runtime/src/big-nat.bend as Big
import ../packages/runtime/src/string-split.bend as Split
import ./aes128-gcm.bend as Bytes
import ../packages/runtime/src/der.bend as DER

def error(cause: P.Error) -> String:
  match cause:
    case P.InvalidKey{}: "key"
    case P.InvalidSignature{}: "signature"
    case P.Encoding{_}: "encoding"
    case P.HashFailure{_}: "hash"

def show(point: P.Point) -> String:
  match point:
    case P.Point{x,y}: Bytes.show(4 <> DER.append(Big.toBigEndian(32n,x),Big.toBigEndian(32n,y)))

def key(result: Result<&2,&2,P.Error,P.Point>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{point}: show(point)

def point(result: Maybe<&2,P.Point>) -> String:
  match result:
    case None{}: "infinity"
    case Some{value}: show(value)

def multiplied(scalar: List<&2,U32>, result: Result<&2,&2,P.Error,P.Point>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{value}: point(P.normalize(P.multiply(scalar,value,P.infinity())))

def verified(result: Result<&2,&2,P.Error,Unit>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{Unit{}}: "ok"

def added(left: P.Point, right: P.Point) -> Maybe<&2,P.Point>:
  match left:
    case P.Point{x,y}: P.normalize(P.addPoint(P.Jacobian{x,y,Big.one()},right))

def addition(result: Result<&2,&2,P.Error,Maybe<&2,P.Point>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{value}: point(value)

def run(parts: List<&2,String>) -> String:
  match parts:
    case "a" <> left <> right <> Nil{}:
      addition(Result.bind(&2,&2,P.Error,P.Point,Maybe<&2,P.Point>,P.publicKey(Bytes.bytes(left)), l =>
        Result.bind(&2,&2,P.Error,P.Point,Maybe<&2,P.Point>,P.publicKey(Bytes.bytes(right)), r => Done{added(l,r)})))
    case "k" <> bytes <> Nil{}: key(P.publicKey(Bytes.bytes(bytes)))
    case "m" <> bytes <> scalar <> Nil{}: multiplied(Bytes.bytes(scalar),P.publicKey(Bytes.bytes(bytes)))
    case "v" <> bytes <> message <> signature <> Nil{}:
      verified(Result.bind(&2,&2,P.Error,P.Point,Unit,P.publicKey(Bytes.bytes(bytes)), public => P.verify(public,Bytes.bytes(message),Bytes.bytes(signature))))
    case _: "invalid"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head,':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

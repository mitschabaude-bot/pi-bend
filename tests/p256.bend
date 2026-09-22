import Base
import ../packages/runtime/src/ecdsa.bend as P
import ../packages/runtime/src/big-nat.bend as Big
import ../packages/runtime/src/prime-field.bend as Field
import ../packages/runtime/src/string.bend as Split
import ./aes128-gcm.bend as Bytes
import ../packages/runtime/src/der.bend as DER

def error(cause: P.Error) -> String:
  match cause:
    case P.InvalidKey{}: "key"
    case P.InvalidSignature{}: "signature"
    case P.Encoding{_}: "encoding"
    case P.HashFailure{_}: "hash"
    case P.WideHashFailure{_}: "hash"

def show(+selected: P.Curve,point: P.Point) -> String:
  match point:
    case P.Point{x,y}: Bytes.show(4 <> DER.append(Big.toBigEndian(P.width(selected),Field.toBig(x)),Big.toBigEndian(P.width(selected),Field.toBig(y))))

def key(+selected: P.Curve,result: Result<&2,&2,P.Error,P.Point>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{point}: show(selected,point)

def point(+selected: P.Curve,result: Maybe<&2,P.Point>) -> String:
  match result:
    case None{}: "infinity"
    case Some{value}: show(selected,value)

def multiplied(+selected: P.Curve,scalar: List<&2,U32>, result: Result<&2,&2,P.Error,P.Point>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{value}: point(selected,P.normalize(selected,P.multiply(selected,scalar,value,P.infinity())))

def jointlyMultiplied(+selected: P.Curve, a: List<&2,U32>, b: List<&2,U32>, result: Result<&2,&2,P.Error,P.Point>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{value}: point(selected,P.normalize(selected,P.joint(selected,a,b,value)))

def verified(result: Result<&2,&2,P.Error,Unit>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{Unit{}}: "ok"

def added(+selected: P.Curve,left: P.Point, right: P.Point) -> Maybe<&2,P.Point>:
  match left:
    case P.Point{x,y}: P.normalize(selected,P.addPoint(selected,P.Jacobian{x,y,Field.one()},right))

def addition(+selected: P.Curve,result: Result<&2,&2,P.Error,Maybe<&2,P.Point>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{value}: point(selected,value)

def hashAlgorithm(selected: P.Curve) -> P.HashAlgorithm:
  match selected:
    case P.P256{}: P.Sha256{}
    case P.P384{}: P.Sha384{}

def run(+selected: P.Curve,parts: List<&2,String>) -> String:
  match parts:
    case "a" <> left <> right <> Nil{}:
      addition(selected,Result.bind(&2,&2,P.Error,P.Point,Maybe<&2,P.Point>,P.publicKey(selected,Bytes.bytes(left)), l =>
        Result.bind(&2,&2,P.Error,P.Point,Maybe<&2,P.Point>,P.publicKey(selected,Bytes.bytes(right)), r => Done{added(selected,l,r)})))
    case "k" <> bytes <> Nil{}: key(selected,P.publicKey(selected,Bytes.bytes(bytes)))
    case "m" <> bytes <> scalar <> Nil{}: multiplied(selected,Bytes.bytes(scalar),P.publicKey(selected,Bytes.bytes(bytes)))
    case "j" <> bytes <> a <> b <> Nil{}: jointlyMultiplied(selected,Bytes.bytes(a),Bytes.bytes(b),P.publicKey(selected,Bytes.bytes(bytes)))
    case "v" <> bytes <> message <> signature <> Nil{}:
      verified(Result.bind(&2,&2,P.Error,P.Point,Unit,P.publicKey(selected,Bytes.bytes(bytes)), public => P.verify(selected,hashAlgorithm(selected),public,Bytes.bytes(message),Bytes.bytes(signature))))
    case _: "invalid"

def arguments(+selected: P.Curve,values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(selected,Split.split(head,':')))
        arguments(selected,rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(P.P256{},values)

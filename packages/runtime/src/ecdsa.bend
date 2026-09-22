import Base
import ./big-nat.bend as Big
import ./prime-field.bend as Field
import ./modular.bend as Modular
import ./der.bend as DER
import ./sha256.bend as SHA
import ./sha512.bend as WideSHA

# NIST P-256/P-384 public-point arithmetic and ECDSA verification. Jacobian
# coordinates avoid inversion during multiplication. This variable-time code
# handles public values only; it is not a private-key signing/ECDH primitive.
# Domain parameters: Standards for Efficient Cryptography 2, sections 2.4.2/2.5.1.
# https://www.secg.org/sec2-v2.pdf
type Curve is Data:
  P256{}
  P384{}

type HashAlgorithm is Data:
  Sha256{}
  Sha384{}

type Error is Data:
  InvalidKey{}
  InvalidSignature{}
  Encoding{cause: DER.Error}
  HashFailure{cause: SHA.Error}
  WideHashFailure{cause: WideSHA.Error}

type Point is Data:
  Point{x: Field.Field, y: Field.Field}

type Jacobian is Data:
  Jacobian{x: Field.Field, y: Field.Field, z: Field.Field}

# P-256: FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
def prime(+selected: Curve) -> Big.BigNat:
  match selected:
    case P256{}: Big.BigNat{65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 1 <> 0 <> 65535 <> 65535 <> Nil{}}
    case P384{}: Big.BigNat{65535 <> 65535 <> 0 <> 0 <> 0 <> 0 <> 65535 <> 65535 <> 65534 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> Nil{}}

def scalarContext(selected: Curve) -> Modular.Context:
  match selected:
    case P256{}: Modular.p256()
    case P384{}: Modular.p384()

def scalarModulus(context: Modular.Context) -> Big.BigNat:
  match context:
    case Modular.Context{modulus,_,_,_}: modulus

def order(selected: Curve) -> Big.BigNat: scalarModulus(scalarContext(selected))

# P-256: 5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
def coefficient(+selected: Curve) -> Big.BigNat:
  match selected:
    case P256{}: Big.BigNat{24651 <> 10194 <> 15422 <> 15310 <> 45302 <> 52307 <> 1712 <> 25885 <> 34492 <> 30360 <> 48469 <> 46059 <> 37863 <> 43578 <> 13784 <> 23238 <> Nil{}}
    case P384{}: Big.BigNat{10991 <> 54252 <> 51437 <> 10885 <> 53661 <> 35374 <> 14733 <> 50774 <> 34650 <> 20499 <> 2191 <> 788 <> 16658 <> 65153 <> 40046 <> 6173 <> 11545 <> 58360 <> 1387 <> 39054 <> 59364 <> 57918 <> 12199 <> 45873 <> Nil{}}

# P-256: 6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296
def generatorX(+selected: Curve) -> Big.BigNat:
  match selected:
    case P256{}: Big.BigNat{49814 <> 55448 <> 14661 <> 62625 <> 13216 <> 11755 <> 32129 <> 30467 <> 16626 <> 25508 <> 59109 <> 63676 <> 16967 <> 57644 <> 53746 <> 27415 <> Nil{}}
    case P384{}: Big.BigNat{2743 <> 29302 <> 24120 <> 14932 <> 10604 <> 48981 <> 62045 <> 21762 <> 10808 <> 33364 <> 16864 <> 23031 <> 39832 <> 35751 <> 15202 <> 28189 <> 44404 <> 62240 <> 50974 <> 36529 <> 1335 <> 48779 <> 51746 <> 43655 <> Nil{}}

# P-256: 4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5
def generatorY(+selected: Curve) -> Big.BigNat:
  match selected:
    case P256{}: Big.BigNat{20981 <> 14271 <> 16488 <> 52150 <> 24270 <> 27441 <> 13143 <> 11214 <> 40470 <> 31759 <> 60234 <> 36583 <> 32667 <> 65050 <> 17122 <> 20451 <> Nil{}}
    case P384{}: Big.BigNat{3679 <> 37098 <> 7548 <> 31299 <> 33181 <> 7550 <> 45518 <> 2656 <> 47296 <> 46576 <> 12563 <> 59866 <> 5244 <> 10394 <> 7613 <> 63732 <> 56361 <> 37522 <> 39103 <> 23966 <> 11375 <> 38438 <> 56906 <> 13847 <> Nil{}}

def width(+selected: Curve) -> Nat:
  match selected:
    case P256{}: 32n
    case P384{}: 48n

def fieldPrime(selected: Curve) -> Field.Prime:
  match selected:
    case P256{}: Field.P256{}
    case P384{}: Field.P384{}

def generator(+selected: Curve) -> Point:
  Point{Field.fromBig(fieldPrime(selected),generatorX(selected)),Field.fromBig(fieldPrime(selected),generatorY(selected))}

def infinity() -> Jacobian: Jacobian{Field.zero(),Field.one(),Field.zero()}

def add(selected: Curve, a: Field.Field, b: Field.Field) -> Field.Field: Field.add(fieldPrime(selected),a,b)
def mul(selected: Curve, a: Field.Field, b: Field.Field) -> Field.Field: Field.mul(fieldPrime(selected),a,b)
def square(selected: Curve, a: Field.Field) -> Field.Field: Field.square(fieldPrime(selected),a)
def scale(selected: Curve, a: Field.Field, k: U32) -> Field.Field: Field.scale(fieldPrime(selected),a,k)
def sub(selected: Curve, a: Field.Field, b: Field.Field) -> Field.Field: Field.sub(fieldPrime(selected),a,b)

def difference(a: Big.BigNat, b: Big.BigNat) -> Big.BigNat:
  match a b:
    case Big.BigNat{xs} Big.BigNat{ys}: Big.BigNat{Big.trim(Big.subtractLimbs(xs,ys,0))}

def doubleFormula(+selected: Curve, point: Jacobian) -> Jacobian:
  match point:
    case Jacobian{+x,+y,+z}:
      +delta = square(selected,z)
      +gamma = square(selected,y)
      +beta = mul(selected,x,gamma)
      +alpha = scale(selected,mul(selected,sub(selected,x,delta),add(selected,x,delta)),3)
      +nx = sub(selected,square(selected,alpha),scale(selected,beta,8))
      ny = sub(selected,mul(selected,alpha,sub(selected,scale(selected,beta,4),nx)),scale(selected,square(selected,gamma),8))
      nz = sub(selected,sub(selected,square(selected,add(selected,y,z)),gamma),delta)
      Jacobian{nx,ny,nz}

def double(+selected: Curve, point: Jacobian) -> Jacobian:
  match point:
    case Jacobian{x,y,+z}:
      Bool.pick(Unit -> Jacobian,Field.isZero(z),unused => infinity(),unused => doubleFormula(selected,Jacobian{x,y,z}))(Unit{})

def addDistinct(+selected: Curve, point: Jacobian, +h: Field.Field, +r: Field.Field) -> Jacobian:
  match point:
    case Jacobian{+x,y,+z}:
      +hh = square(selected,h)
      +i = scale(selected,hh,4)
      +j = mul(selected,h,i)
      +v = mul(selected,x,i)
      +nx = sub(selected,sub(selected,square(selected,r),j),scale(selected,v,2))
      ny = sub(selected,mul(selected,r,sub(selected,v,nx)),scale(selected,mul(selected,y,j),2))
      nz = sub(selected,sub(selected,square(selected,add(selected,z,h)),square(selected,z)),hh)
      Jacobian{nx,ny,nz}

def addCases(+selected: Curve, zero: Bool, sameX: Bool, sameY: Bool, point: Jacobian, other: Point, h: Field.Field, r: Field.Field) -> Jacobian:
  match zero sameX sameY other:
    case True{} _ _ Point{x,y}: Jacobian{x,y,Field.one()}
    case False{} True{} True{} _: double(selected,point)
    case False{} True{} False{} _: infinity()
    case False{} False{} _ _: addDistinct(selected,point,h,r)

def addPoint(+selected: Curve, point: Jacobian, +other: Point) -> Jacobian:
  match point other:
    case Jacobian{+x,+y,+z} Point{ox,oy}:
      +zz = square(selected,z)
      +u = mul(selected,ox,zz)
      +s = mul(selected,oy,mul(selected,z,zz))
      addCases(selected,Field.isZero(z),Field.equal(u,x),Field.equal(s,y),Jacobian{x,y,z},other,sub(selected,u,x),scale(selected,sub(selected,s,y),2))

def addBit(+selected: Curve, set: Bool, point: Jacobian, base: Point) -> Jacobian:
  match set:
    case False{}: point
    case True{}: addPoint(selected,point,base)

def multiplyByte(+selected: Curve, fuel: Nat, +byte: U32, +base: Point, point: Jacobian) -> Jacobian:
  match fuel:
    case 0n: point
    case 1n+fuel: multiplyByte(selected,fuel,U32.and(U32.shl(byte),255),base,addBit(selected,U32.is_eq(U32.and(byte,128),128),double(selected,point),base))

def multiply(+selected: Curve, bytes: List<&2,U32>, +base: Point, point: Jacobian) -> Jacobian:
  match bytes:
    case Nil{}: point
    case byte <> rest: multiply(selected,rest,base,multiplyByte(selected,8n,byte,base,point))

def less(order: Cmp) -> Bool:
  match order:
    case LT{}: True{}
    case _: False{}

def powerBit(+selected: Curve, set: Bool, value: Field.Field, base: Field.Field) -> Field.Field:
  match set:
    case False{}: value
    case True{}: mul(selected,value,base)

def powerByte(+selected: Curve, fuel: Nat, +byte: U32, +base: Field.Field, value: Field.Field) -> Field.Field:
  match fuel:
    case 0n: value
    case 1n+fuel:
      next = powerBit(selected,U32.is_eq(U32.and(byte,128),128),square(selected,value),base)
      powerByte(selected,fuel,U32.and(U32.shl(byte),255),base,next)

def fieldPower(+selected: Curve, bytes: List<&2,U32>, +base: Field.Field, value: Field.Field) -> Field.Field:
  match bytes:
    case Nil{}: value
    case byte <> rest: fieldPower(selected,rest,base,powerByte(selected,8n,byte,base,value))

def normalizedInverse(+selected: Curve, x: Field.Field, y: Field.Field, inverse: Maybe<&2,Big.BigNat>) -> Maybe<&2,Point>:
  match inverse:
    case None{}: None{}
    case Some{value}:
      +zi = Field.fromBig(fieldPrime(selected),value)
      +zz = square(selected,zi)
      Some{Point{mul(selected,x,zz),mul(selected,y,mul(selected,zz,zi))}}

def normalize(+selected: Curve, point: Jacobian) -> Maybe<&2,Point>:
  match point:
    case Jacobian{x,y,z}: normalizedInverse(selected,x,y,Modular.inverse(Field.toBig(z),prime(selected)))

def curve(+selected: Curve, +x: Field.Field) -> Field.Field: add(selected,sub(selected,mul(selected,square(selected,x),x),scale(selected,x,3)),Field.fromBig(fieldPrime(selected),coefficient(selected)))

def checkedPoint(allowed: Bool, x: Field.Field, y: Field.Field) -> Result<&2,&2,Error,Point>:
  match allowed:
    case False{}: Fail{InvalidKey{}}
    case True{}: Done{Point{x,y}}

def pointWithinField(+selected: Curve, allowed: Bool, x: Big.BigNat, y: Big.BigNat) -> Result<&2,&2,Error,Point>:
  match allowed:
    case False{}: Fail{InvalidKey{}}
    case True{}:
      +fx = Field.fromBig(fieldPrime(selected),x)
      +fy = Field.fromBig(fieldPrime(selected),y)
      checkedPoint(Field.equal(square(selected,fy),curve(selected,fx)),fx,fy)

def point(+selected: Curve, +x: Big.BigNat, +y: Big.BigNat) -> Result<&2,&2,Error,Point>:
  pointWithinField(selected,less(Big.compare(x,prime(selected))) && less(Big.compare(y,prime(selected))),x,y)

def octets(bytes: List<&2,U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case byte <> rest: U32.is_le(byte,255) && octets(rest)

def parity(value: Big.BigNat) -> Bool:
  match value:
    case Big.BigNat{head <> _}: U32.is_eq(U32.and(head,1),1)
    case Big.BigNat{Nil{}}: False{}

def rootExponent(+selected: Curve, divided: Big.SmallDivision) -> List<&2,U32>:
  match divided:
    case Big.SmallDivision{quotient,_}: Big.toBigEndian(width(selected),quotient)

def compressedWithinField(+selected: Curve, allowed: Bool, odd: Bool, +x: Big.BigNat) -> Result<&2,&2,Error,Point>:
  match allowed:
    case False{}: Fail{InvalidKey{}}
    case True{}:
      +y = Field.toBig(fieldPower(selected,rootExponent(selected,Big.divideSmallRaw(Big.add(prime(selected),Big.one()),4)),curve(selected,Field.fromBig(fieldPrime(selected),x)),Field.one()))
      point(selected,x,Bool.pick(Big.BigNat,Bool.not(Bool.xor(odd,parity(y))),y,difference(prime(selected),y)))

def compressed(+selected: Curve, odd: Bool, +x: Big.BigNat) -> Result<&2,&2,Error,Point>:
  compressedWithinField(selected,less(Big.compare(x,prime(selected))),odd,x)

def keyFormat(+selected: Curve, bytes: List<&2,U32>) -> Result<&2,&2,Error,Point>:
  match bytes:
    case 4 <> +rest:
      checked = Bool.pick(Result<&2,&2,Error,Unit>, Nat.is_eq(DER.length(rest,0n),Nat.add(width(selected),width(selected))), Done{Unit{}}, Fail{InvalidKey{}})
      Result.bind(&2,&2,Error,Unit,Point,checked,unused => point(selected,Big.fromBigEndian(List.take(&2,U32,rest,width(selected))),Big.fromBigEndian(List.drop(&2,U32,rest,width(selected)))))
    case 2 <> +rest:
      checked = Bool.pick(Result<&2,&2,Error,Unit>, Nat.is_eq(DER.length(rest,0n),width(selected)), Done{Unit{}}, Fail{InvalidKey{}})
      Result.bind(&2,&2,Error,Unit,Point,checked,unused => compressed(selected,False{},Big.fromBigEndian(rest)))
    case 3 <> +rest:
      checked = Bool.pick(Result<&2,&2,Error,Unit>, Nat.is_eq(DER.length(rest,0n),width(selected)), Done{Unit{}}, Fail{InvalidKey{}})
      Result.bind(&2,&2,Error,Unit,Point,checked,unused => compressed(selected,True{},Big.fromBigEndian(rest)))
    case _: Fail{InvalidKey{}}

def publicKey(+selected: Curve, +bytes: List<&2,U32>) -> Result<&2,&2,Error,Point>:
  checked = Bool.pick(Result<&2,&2,Error,Unit>, octets(bytes), Done{Unit{}}, Fail{InvalidKey{}})
  Result.bind(&2,&2,Error,Unit,Point,checked,unused => keyFormat(selected,bytes))

# Joint public multiplication computes u*G + v*Q with one doubling per bit.
# Scalars are fixed-width byte strings supplied by verification below.
def jointByte(+selected: Curve, fuel: Nat, +a: U32, +b: U32, +g: Point, +base: Point, acc: Jacobian) -> Jacobian:
  match fuel:
    case 0n: acc
    case 1n+fuel:
      next = addBit(selected,U32.is_eq(U32.and(b,128),128),addBit(selected,U32.is_eq(U32.and(a,128),128),double(selected,acc),g),base)
      jointByte(selected,fuel,U32.and(U32.shl(a),255),U32.and(U32.shl(b),255),g,base,next)

def jointWithGenerator(+selected: Curve, a: List<&2,U32>, b: List<&2,U32>, +g: Point, +base: Point, acc: Jacobian) -> Jacobian:
  match a b:
    case Nil{} Nil{}: acc
    case x <> xs y <> ys: jointWithGenerator(selected,xs,ys,g,base,jointByte(selected,8n,x,y,g,base,acc))
    case _ _: infinity()

def joint(+selected: Curve, a: List<&2,U32>, b: List<&2,U32>, base: Point, acc: Jacobian) -> Jacobian:
  jointWithGenerator(selected,a,b,generator(selected),base,acc)

def matchesAlternate(+selected: Curve, allowed: Bool, x: Field.Field, zz: Field.Field, rn: Big.BigNat) -> Bool:
  match allowed:
    case False{}: False{}
    case True{}: Field.equal(x,mul(selected,Field.fromBig(fieldPrime(selected),rn),zz))

def matches(+selected: Curve, result: Jacobian, +r: Big.BigNat) -> Bool:
  match result:
    case Jacobian{+x,_,+z}:
      +zz = square(selected,z)
      +rn = Big.add(r,order(selected))
      Bool.not(Field.isZero(z)) && (Field.equal(x,mul(selected,Field.fromBig(fieldPrime(selected),r),zz)) || matchesAlternate(selected,less(Big.compare(rn,prime(selected))),x,zz,rn))

def verification(valid: Bool) -> Result<&2,&2,Error,Unit>:
  match valid:
    case False{}: Fail{InvalidSignature{}}
    case True{}: Done{Unit{}}

def verifyInverse(+selected: Curve, public: Point, hash: List<&2,U32>, +r: Big.BigNat, inverse: Maybe<&2,Big.BigNat>) -> Result<&2,&2,Error,Unit>:
  match inverse:
    case None{}: Fail{InvalidSignature{}}
    case Some{+w}:
      +context = scalarContext(selected)
      u = Big.toBigEndian(width(selected),Modular.multiply(context,Big.fromBigEndian(List.take(&2,U32,hash,width(selected))),w))
      v = Big.toBigEndian(width(selected),Modular.multiply(context,r,w))
      verification(matches(selected,joint(selected,u,v,public,infinity()),r))

def verifyNumbers(+selected: Curve, public: Point, hash: List<&2,U32>, +r: Big.BigNat, +s: Big.BigNat) -> Result<&2,&2,Error,Unit>:
  checked = verification(Bool.not(Big.isZero(r)) && Bool.not(Big.isZero(s)) && less(Big.compare(r,order(selected))) && less(Big.compare(s,order(selected))))
  Result.bind(&2,&2,Error,Unit,Unit,checked,unused =>
    verifyInverse(selected,public,hash,r,Modular.inverse(s,order(selected))))

def decoded(-A: Data, result: Result<&2,&2,DER.Error,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Fail{cause}: Fail{Encoding{cause}}
    case Done{value}: Done{value}

def signature(+selected: Curve, public: Point, hash: List<&2,U32>, nodes: List<&2,DER.Node>) -> Result<&2,&2,Error,Unit>:
  match nodes:
    case r <> s <> Nil{}:
      Result.bind(&2,&2,Error,List<&2,U32>,Unit,decoded(List<&2,U32>,DER.unsigned(r)), rb =>
        Result.bind(&2,&2,Error,List<&2,U32>,Unit,decoded(List<&2,U32>,DER.unsigned(s)), sb => verifyNumbers(selected,public,hash,Big.fromBigEndian(rb),Big.fromBigEndian(sb))))
    case _: Fail{InvalidSignature{}}

def digest(result: Result<&2,&2,SHA.Error,SHA.Digest>) -> Result<&2,&2,Error,List<&2,U32>>:
  match result:
    case Fail{cause}: Fail{HashFailure{cause}}
    case Done{value}: Done{SHA.toBytes(value)}

def wideDigest(result: Result<&2,&2,WideSHA.Error,List<&2,U32>>) -> Result<&2,&2,Error,List<&2,U32>>:
  match result:
    case Fail{cause}: Fail{WideHashFailure{cause}}
    case Done{value}: Done{value}

def messageHash(algorithm: HashAlgorithm, message: List<&2,U32>) -> Result<&2,&2,Error,List<&2,U32>>:
  match algorithm:
    case Sha256{}: digest(SHA.digest(message))
    case Sha384{}: wideDigest(WideSHA.digest(WideSHA.Sha384{},message))

def verifyDigest(+selected: Curve, public: Point, hash: List<&2,U32>, encodedSignature: List<&2,U32>) -> Result<&2,&2,Error,Unit>:
  Result.bind(&2,&2,Error,DER.Node,Unit,decoded(DER.Node,DER.one(encodedSignature)), node =>
    Result.bind(&2,&2,Error,List<&2,DER.Node>,Unit,decoded(List<&2,DER.Node>,DER.sequence(node)), nodes => signature(selected,public,hash,nodes)))

def verify(+selected: Curve, algorithm: HashAlgorithm, public: Point, message: List<&2,U32>, encodedSignature: List<&2,U32>) -> Result<&2,&2,Error,Unit>:
  Result.bind(&2,&2,Error,List<&2,U32>,Unit,messageHash(algorithm,message), hash => verifyDigest(selected,public,hash,encodedSignature))

import Base
import ./big-nat.bend as Big
import ./der.bend as DER
import ./sha256.bend as SHA

# P-256 public-point arithmetic and ECDSA/SHA-256 verification. Jacobian
# coordinates avoid inversion during multiplication. This variable-time code
# handles public values only; it is not a private-key signing/ECDH primitive.
type Error is Data:
  InvalidKey{}
  InvalidSignature{}
  Encoding{cause: DER.Error}
  HashFailure{cause: SHA.Error}

type Point is Data:
  Point{x: Big.BigNat, y: Big.BigNat}

type Jacobian is Data:
  Jacobian{x: Big.BigNat, y: Big.BigNat, z: Big.BigNat}

# FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
def prime() -> Big.BigNat:
  Big.BigNat{65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 1 <> 0 <> 65535 <> 65535 <> Nil{}}

# FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
def order() -> Big.BigNat:
  Big.BigNat{9553 <> 64611 <> 51906 <> 62393 <> 40580 <> 42775 <> 64173 <> 48358 <> 65535 <> 65535 <> 65535 <> 65535 <> 0 <> 0 <> 65535 <> 65535 <> Nil{}}

# 5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
def coefficient() -> Big.BigNat:
  Big.BigNat{24651 <> 10194 <> 15422 <> 15310 <> 45302 <> 52307 <> 1712 <> 25885 <> 34492 <> 30360 <> 48469 <> 46059 <> 37863 <> 43578 <> 13784 <> 23238 <> Nil{}}

# 6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296
def generatorX() -> Big.BigNat:
  Big.BigNat{49814 <> 55448 <> 14661 <> 62625 <> 13216 <> 11755 <> 32129 <> 30467 <> 16626 <> 25508 <> 59109 <> 63676 <> 16967 <> 57644 <> 53746 <> 27415 <> Nil{}}

# 4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5
def generatorY() -> Big.BigNat:
  Big.BigNat{20981 <> 14271 <> 16488 <> 52150 <> 24270 <> 27441 <> 13143 <> 11214 <> 40470 <> 31759 <> 60234 <> 36583 <> 32667 <> 65050 <> 17122 <> 20451 <> Nil{}}

def generator() -> Point: Point{generatorX(),generatorY()}
def infinity() -> Jacobian: Jacobian{Big.zero(),Big.one(),Big.zero()}

def add(a: Big.BigNat, b: Big.BigNat) -> Big.BigNat: Big.reduce(Big.add(a,b),prime())
def mul(a: Big.BigNat, b: Big.BigNat) -> Big.BigNat: Big.reduce(Big.multiply(a,b),prime())
def square(+a: Big.BigNat) -> Big.BigNat: mul(a,a)
def scale(a: Big.BigNat, k: U32) -> Big.BigNat: Big.reduce(Big.multiplyU32(a,k),prime())

def difference(a: Big.BigNat, b: Big.BigNat) -> Big.BigNat:
  match a b:
    case Big.BigNat{xs} Big.BigNat{ys}: Big.BigNat{Big.trim(Big.subtractLimbs(xs,ys,0))}

# Operands are canonical field elements, so a+p >= b and the subtraction is
# nonnegative. Every field operation returns a canonical value below p.
def sub(a: Big.BigNat, b: Big.BigNat) -> Big.BigNat: Big.reduce(difference(Big.add(a,prime()),b),prime())

def doubleFormula(point: Jacobian) -> Jacobian:
  match point:
    case Jacobian{+x,+y,+z}:
      +delta = square(z)
      +gamma = square(y)
      +beta = mul(x,gamma)
      +alpha = scale(mul(sub(x,delta),add(x,delta)),3)
      +nx = sub(square(alpha),scale(beta,8))
      ny = sub(mul(alpha,sub(scale(beta,4),nx)),scale(square(gamma),8))
      nz = sub(sub(square(add(y,z)),gamma),delta)
      Jacobian{nx,ny,nz}

def double(point: Jacobian) -> Jacobian:
  match point:
    case Jacobian{x,y,+z}:
      Bool.pick(Unit -> Jacobian,Big.isZero(z),unused => infinity(),unused => doubleFormula(Jacobian{x,y,z}))(Unit{})

def addDistinct(point: Jacobian, +h: Big.BigNat, +r: Big.BigNat) -> Jacobian:
  match point:
    case Jacobian{+x,y,+z}:
      +hh = square(h)
      +i = scale(hh,4)
      +j = mul(h,i)
      +v = mul(x,i)
      +nx = sub(sub(square(r),j),scale(v,2))
      ny = sub(mul(r,sub(v,nx)),scale(mul(y,j),2))
      nz = sub(sub(square(add(z,h)),square(z)),hh)
      Jacobian{nx,ny,nz}

def addCases(zero: Bool, sameX: Bool, sameY: Bool, point: Jacobian, other: Point, h: Big.BigNat, r: Big.BigNat) -> Jacobian:
  match zero sameX sameY other:
    case True{} _ _ Point{x,y}: Jacobian{x,y,Big.one()}
    case False{} True{} True{} _: double(point)
    case False{} True{} False{} _: infinity()
    case False{} False{} _ _: addDistinct(point,h,r)

def addPoint(point: Jacobian, +other: Point) -> Jacobian:
  match point other:
    case Jacobian{+x,+y,+z} Point{ox,oy}:
      +zz = square(z)
      +u = mul(ox,zz)
      +s = mul(oy,mul(z,zz))
      addCases(Big.isZero(z),Big.equal(u,x),Big.equal(s,y),Jacobian{x,y,z},other,sub(u,x),scale(sub(s,y),2))

def addBit(set: Bool, point: Jacobian, base: Point) -> Jacobian:
  match set:
    case False{}: point
    case True{}: addPoint(point,base)

def multiplyByte(fuel: Nat, +byte: U32, +base: Point, point: Jacobian) -> Jacobian:
  match fuel:
    case 0n: point
    case 1n+fuel: multiplyByte(fuel,U32.and(U32.shl(byte),255),base,addBit(U32.is_eq(U32.and(byte,128),128),double(point),base))

def multiply(bytes: List<&2,U32>, +base: Point, point: Jacobian) -> Jacobian:
  match bytes:
    case Nil{}: point
    case byte <> rest: multiply(rest,base,multiplyByte(8n,byte,base,point))

def less(order: Cmp) -> Bool:
  match order:
    case LT{}: True{}
    case _: False{}

def inverse(value: Big.BigNat, +modulus: Big.BigNat) -> Big.BigNat:
  Big.powerMod(Big.toBigEndian(32n,difference(modulus,Big.fromU32(2))),value,modulus)

def normalized(zero: Bool, point: Jacobian) -> Maybe<&2,Point>:
  match zero point:
    case True{} _: None{}
    case False{} Jacobian{x,y,z}:
      +zi = inverse(z,prime())
      +zz = square(zi)
      Some{Point{mul(x,zz),mul(y,mul(zz,zi))}}

def normalize(point: Jacobian) -> Maybe<&2,Point>:
  match point:
    case Jacobian{x,y,+z}: normalized(Big.isZero(z),Jacobian{x,y,z})

def curve(+x: Big.BigNat) -> Big.BigNat: add(sub(mul(square(x),x),scale(x,3)),coefficient())

def checkedPoint(allowed: Bool, x: Big.BigNat, y: Big.BigNat) -> Result<&2,&2,Error,Point>:
  match allowed:
    case False{}: Fail{InvalidKey{}}
    case True{}: Done{Point{x,y}}

def point(+x: Big.BigNat, +y: Big.BigNat) -> Result<&2,&2,Error,Point>:
  checkedPoint(less(Big.compare(x,prime())) && less(Big.compare(y,prime())) && Big.equal(square(y),curve(x)),x,y)

def octets(bytes: List<&2,U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case byte <> rest: U32.is_le(byte,255) && octets(rest)

def parity(value: Big.BigNat) -> Bool:
  match value:
    case Big.BigNat{head <> _}: U32.is_eq(U32.and(head,1),1)
    case Big.BigNat{Nil{}}: False{}

def rootExponent(divided: Big.SmallDivision) -> List<&2,U32>:
  match divided:
    case Big.SmallDivision{quotient,_}: Big.toBigEndian(32n,quotient)

def compressed(odd: Bool, +x: Big.BigNat) -> Result<&2,&2,Error,Point>:
  +y = Big.powerMod(rootExponent(Big.divideSmallRaw(Big.add(prime(),Big.one()),4)),curve(x),prime())
  point(x,Bool.pick(Big.BigNat,Bool.not(Bool.xor(odd,parity(y))),y,difference(prime(),y)))

def keyFormat(bytes: List<&2,U32>) -> Result<&2,&2,Error,Point>:
  match bytes:
    case 4 <> +rest:
      checked = Bool.pick(Result<&2,&2,Error,Unit>, Nat.is_eq(DER.length(rest,0n),64n), Done{Unit{}}, Fail{InvalidKey{}})
      Result.bind(&2,&2,Error,Unit,Point,checked,unused => point(Big.fromBigEndian(List.take(&2,U32,rest,32n)),Big.fromBigEndian(List.drop(&2,U32,rest,32n))))
    case 2 <> +rest:
      checked = Bool.pick(Result<&2,&2,Error,Unit>, Nat.is_eq(DER.length(rest,0n),32n), Done{Unit{}}, Fail{InvalidKey{}})
      Result.bind(&2,&2,Error,Unit,Point,checked,unused => compressed(False{},Big.fromBigEndian(rest)))
    case 3 <> +rest:
      checked = Bool.pick(Result<&2,&2,Error,Unit>, Nat.is_eq(DER.length(rest,0n),32n), Done{Unit{}}, Fail{InvalidKey{}})
      Result.bind(&2,&2,Error,Unit,Point,checked,unused => compressed(True{},Big.fromBigEndian(rest)))
    case _: Fail{InvalidKey{}}

def publicKey(+bytes: List<&2,U32>) -> Result<&2,&2,Error,Point>:
  checked = Bool.pick(Result<&2,&2,Error,Unit>, octets(bytes), Done{Unit{}}, Fail{InvalidKey{}})
  Result.bind(&2,&2,Error,Unit,Point,checked,unused => keyFormat(bytes))

# Joint public multiplication computes u*G + v*Q with one doubling per bit.
# Scalars are fixed-width byte strings supplied by verification below.
def jointByte(fuel: Nat, +a: U32, +b: U32, +base: Point, acc: Jacobian) -> Jacobian:
  match fuel:
    case 0n: acc
    case 1n+fuel:
      next = addBit(U32.is_eq(U32.and(b,128),128),addBit(U32.is_eq(U32.and(a,128),128),double(acc),generator()),base)
      jointByte(fuel,U32.and(U32.shl(a),255),U32.and(U32.shl(b),255),base,next)

def joint(a: List<&2,U32>, b: List<&2,U32>, +base: Point, acc: Jacobian) -> Jacobian:
  match a b:
    case Nil{} Nil{}: acc
    case x <> xs y <> ys: joint(xs,ys,base,jointByte(8n,x,y,base,acc))
    case _ _: infinity()

def matches(result: Jacobian, +r: Big.BigNat) -> Bool:
  match result:
    case Jacobian{+x,_,+z}:
      +zz = square(z)
      +rn = Big.add(r,order())
      Bool.not(Big.isZero(z)) && (Big.equal(x,mul(r,zz)) || (less(Big.compare(rn,prime())) && Big.equal(x,mul(rn,zz))))

def verification(valid: Bool) -> Result<&2,&2,Error,Unit>:
  match valid:
    case False{}: Fail{InvalidSignature{}}
    case True{}: Done{Unit{}}

def verifyNumbers(public: Point, hash: SHA.Digest, +r: Big.BigNat, +s: Big.BigNat) -> Result<&2,&2,Error,Unit>:
  checked = verification(Bool.not(Big.isZero(r)) && Bool.not(Big.isZero(s)) && less(Big.compare(r,order())) && less(Big.compare(s,order())))
  Result.bind(&2,&2,Error,Unit,Unit,checked,unused =>
    +w = inverse(s,order())
    u = Big.toBigEndian(32n,Big.reduce(Big.multiply(Big.fromBigEndian(SHA.toBytes(hash)),w),order()))
    v = Big.toBigEndian(32n,Big.reduce(Big.multiply(r,w),order()))
    verification(matches(joint(u,v,public,infinity()),r)))

def decoded(-A: Data, result: Result<&2,&2,DER.Error,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Fail{cause}: Fail{Encoding{cause}}
    case Done{value}: Done{value}

def signature(public: Point, hash: SHA.Digest, nodes: List<&2,DER.Node>) -> Result<&2,&2,Error,Unit>:
  match nodes:
    case r <> s <> Nil{}:
      Result.bind(&2,&2,Error,List<&2,U32>,Unit,decoded(List<&2,U32>,DER.unsigned(r)), rb =>
        Result.bind(&2,&2,Error,List<&2,U32>,Unit,decoded(List<&2,U32>,DER.unsigned(s)), sb => verifyNumbers(public,hash,Big.fromBigEndian(rb),Big.fromBigEndian(sb))))
    case _: Fail{InvalidSignature{}}

def digest(result: Result<&2,&2,SHA.Error,SHA.Digest>) -> Result<&2,&2,Error,SHA.Digest>:
  match result:
    case Fail{cause}: Fail{HashFailure{cause}}
    case Done{value}: Done{value}

def verify(public: Point, message: List<&2,U32>, encodedSignature: List<&2,U32>) -> Result<&2,&2,Error,Unit>:
  Result.bind(&2,&2,Error,SHA.Digest,Unit,digest(SHA.digest(message)), hash =>
    Result.bind(&2,&2,Error,DER.Node,Unit,decoded(DER.Node,DER.one(encodedSignature)), node =>
      Result.bind(&2,&2,Error,List<&2,DER.Node>,Unit,decoded(List<&2,DER.Node>,DER.sequence(node)), nodes => signature(public,hash,nodes))))

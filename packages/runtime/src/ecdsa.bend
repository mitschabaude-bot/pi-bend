import Base
import ./big-nat.bend as Big
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
  Point{x: Big.BigNat, y: Big.BigNat}

type Jacobian is Data:
  Jacobian{x: Big.BigNat, y: Big.BigNat, z: Big.BigNat}

# P-256: FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
def prime(+selected: Curve) -> Big.BigNat:
  match selected:
    case P256{}: Big.BigNat{4294967295 <> 4294967295 <> 4294967295 <> 0 <> 0 <> 0 <> 1 <> 4294967295 <> Nil{}}
    case P384{}: Big.BigNat{4294967295 <> 0 <> 0 <> 4294967295 <> 4294967294 <> 4294967295 <> 4294967295 <> 4294967295 <> 4294967295 <> 4294967295 <> 4294967295 <> 4294967295 <> Nil{}}

# P-256: FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
def order(+selected: Curve) -> Big.BigNat:
  match selected:
    case P256{}: Big.BigNat{4234356049 <> 4089039554 <> 2803342980 <> 3169254061 <> 4294967295 <> 4294967295 <> 0 <> 4294967295 <> Nil{}}
    case P384{}: Big.BigNat{3435473267 <> 3974895978 <> 1219536762 <> 1478102450 <> 4097256927 <> 3345173889 <> 4294967295 <> 4294967295 <> 4294967295 <> 4294967295 <> 4294967295 <> 4294967295 <> Nil{}}

# P-256: 5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
def coefficient(+selected: Curve) -> Big.BigNat:
  match selected:
    case P256{}: Big.BigNat{668098635 <> 1003371582 <> 3428036854 <> 1696401072 <> 1989707452 <> 3018571093 <> 2855965671 <> 1522939352 <> Nil{}}
    case P384{}: Big.BigNat{3555470063 <> 713410797 <> 2318324125 <> 3327539597 <> 1343457114 <> 51644559 <> 4269883666 <> 404593774 <> 3824692505 <> 2559444331 <> 3795773412 <> 3006345127 <> Nil{}}

# P-256: 6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296
def generatorX(+selected: Curve) -> Big.BigNat:
  match selected:
    case P256{}: Big.BigNat{3633889942 <> 4104206661 <> 770388896 <> 1996717441 <> 1671708914 <> 4173129445 <> 3777774151 <> 1796723186 <> Nil{}}
    case P384{}: Big.BigNat{1920338615 <> 978607672 <> 3210029420 <> 1426256477 <> 2186553912 <> 1509376480 <> 2343017368 <> 1847409506 <> 4079005044 <> 2394015518 <> 3196781879 <> 2861025826 <> Nil{}}

# P-256: 4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5
def generatorY(+selected: Curve) -> Big.BigNat:
  match selected:
    case P256{}: Big.BigNat{935285237 <> 3417718888 <> 1798397646 <> 734933847 <> 2081398294 <> 2397563722 <> 4263149467 <> 1340293858 <> Nil{}}
    case P384{}: Big.BigNat{2431258207 <> 2051218812 <> 494829981 <> 174109134 <> 3052452032 <> 3923390739 <> 681186428 <> 4176747965 <> 2459098153 <> 1570674879 <> 2519084143 <> 907533898 <> Nil{}}

def width(+selected: Curve) -> Nat:
  match selected:
    case P256{}: 32n
    case P384{}: 48n

def generator(+selected: Curve) -> Point: Point{generatorX(selected),generatorY(selected)}
def infinity() -> Jacobian: Jacobian{Big.zero(),Big.one(),Big.zero()}

def add(+selected: Curve, a: Big.BigNat, b: Big.BigNat) -> Big.BigNat: Big.reduce(Big.add(a,b),prime(selected))
def mul(+selected: Curve, a: Big.BigNat, b: Big.BigNat) -> Big.BigNat: Big.reduce(Big.multiply(a,b),prime(selected))
def square(+selected: Curve, +a: Big.BigNat) -> Big.BigNat: mul(selected,a,a)
def scale(+selected: Curve, a: Big.BigNat, k: U32) -> Big.BigNat: Big.reduce(Big.multiplyU32(a,k),prime(selected))

def difference(a: Big.BigNat, b: Big.BigNat) -> Big.BigNat:
  match a b:
    case Big.BigNat{xs} Big.BigNat{ys}: Big.BigNat{Big.trim(Big.subtractLimbs(xs,ys,0))}

# Operands are canonical field elements, so a+p >= b and the subtraction is
# nonnegative. Every field operation returns a canonical value below p.
def sub(+selected: Curve, a: Big.BigNat, b: Big.BigNat) -> Big.BigNat: Big.reduce(difference(Big.add(a,prime(selected)),b),prime(selected))

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
      Bool.pick(Unit -> Jacobian,Big.isZero(z),unused => infinity(),unused => doubleFormula(selected,Jacobian{x,y,z}))(Unit{})

def addDistinct(+selected: Curve, point: Jacobian, +h: Big.BigNat, +r: Big.BigNat) -> Jacobian:
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

def addCases(+selected: Curve, zero: Bool, sameX: Bool, sameY: Bool, point: Jacobian, other: Point, h: Big.BigNat, r: Big.BigNat) -> Jacobian:
  match zero sameX sameY other:
    case True{} _ _ Point{x,y}: Jacobian{x,y,Big.one()}
    case False{} True{} True{} _: double(selected,point)
    case False{} True{} False{} _: infinity()
    case False{} False{} _ _: addDistinct(selected,point,h,r)

def addPoint(+selected: Curve, point: Jacobian, +other: Point) -> Jacobian:
  match point other:
    case Jacobian{+x,+y,+z} Point{ox,oy}:
      +zz = square(selected,z)
      +u = mul(selected,ox,zz)
      +s = mul(selected,oy,mul(selected,z,zz))
      addCases(selected,Big.isZero(z),Big.equal(u,x),Big.equal(s,y),Jacobian{x,y,z},other,sub(selected,u,x),scale(selected,sub(selected,s,y),2))

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

def inverse(+selected: Curve, value: Big.BigNat, +modulus: Big.BigNat) -> Big.BigNat:
  Big.powerMod(Big.toBigEndian(width(selected),difference(modulus,Big.fromU32(2))),value,modulus)

def normalized(+selected: Curve, zero: Bool, point: Jacobian) -> Maybe<&2,Point>:
  match zero point:
    case True{} _: None{}
    case False{} Jacobian{x,y,z}:
      +zi = inverse(selected,z,prime(selected))
      +zz = square(selected,zi)
      Some{Point{mul(selected,x,zz),mul(selected,y,mul(selected,zz,zi))}}

def normalize(+selected: Curve, point: Jacobian) -> Maybe<&2,Point>:
  match point:
    case Jacobian{x,y,+z}: normalized(selected,Big.isZero(z),Jacobian{x,y,z})

def curve(+selected: Curve, +x: Big.BigNat) -> Big.BigNat: add(selected,sub(selected,mul(selected,square(selected,x),x),scale(selected,x,3)),coefficient(selected))

def checkedPoint(allowed: Bool, x: Big.BigNat, y: Big.BigNat) -> Result<&2,&2,Error,Point>:
  match allowed:
    case False{}: Fail{InvalidKey{}}
    case True{}: Done{Point{x,y}}

def point(+selected: Curve, +x: Big.BigNat, +y: Big.BigNat) -> Result<&2,&2,Error,Point>:
  checkedPoint(less(Big.compare(x,prime(selected))) && less(Big.compare(y,prime(selected))) && Big.equal(square(selected,y),curve(selected,x)),x,y)

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

def compressed(+selected: Curve, odd: Bool, +x: Big.BigNat) -> Result<&2,&2,Error,Point>:
  +y = Big.powerMod(rootExponent(selected,Big.divideSmallRaw(Big.add(prime(selected),Big.one()),4)),curve(selected,x),prime(selected))
  point(selected,x,Bool.pick(Big.BigNat,Bool.not(Bool.xor(odd,parity(y))),y,difference(prime(selected),y)))

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
def jointByte(+selected: Curve, fuel: Nat, +a: U32, +b: U32, +base: Point, acc: Jacobian) -> Jacobian:
  match fuel:
    case 0n: acc
    case 1n+fuel:
      next = addBit(selected,U32.is_eq(U32.and(b,128),128),addBit(selected,U32.is_eq(U32.and(a,128),128),double(selected,acc),generator(selected)),base)
      jointByte(selected,fuel,U32.and(U32.shl(a),255),U32.and(U32.shl(b),255),base,next)

def joint(+selected: Curve, a: List<&2,U32>, b: List<&2,U32>, +base: Point, acc: Jacobian) -> Jacobian:
  match a b:
    case Nil{} Nil{}: acc
    case x <> xs y <> ys: joint(selected,xs,ys,base,jointByte(selected,8n,x,y,base,acc))
    case _ _: infinity()

def matches(+selected: Curve, result: Jacobian, +r: Big.BigNat) -> Bool:
  match result:
    case Jacobian{+x,_,+z}:
      +zz = square(selected,z)
      +rn = Big.add(r,order(selected))
      Bool.not(Big.isZero(z)) && (Big.equal(x,mul(selected,r,zz)) || (less(Big.compare(rn,prime(selected))) && Big.equal(x,mul(selected,rn,zz))))

def verification(valid: Bool) -> Result<&2,&2,Error,Unit>:
  match valid:
    case False{}: Fail{InvalidSignature{}}
    case True{}: Done{Unit{}}

def verifyNumbers(+selected: Curve, public: Point, hash: List<&2,U32>, +r: Big.BigNat, +s: Big.BigNat) -> Result<&2,&2,Error,Unit>:
  checked = verification(Bool.not(Big.isZero(r)) && Bool.not(Big.isZero(s)) && less(Big.compare(r,order(selected))) && less(Big.compare(s,order(selected))))
  Result.bind(&2,&2,Error,Unit,Unit,checked,unused =>
    +w = inverse(selected,s,order(selected))
    u = Big.toBigEndian(width(selected),Big.reduce(Big.multiply(Big.fromBigEndian(List.take(&2,U32,hash,width(selected))),w),order(selected)))
    v = Big.toBigEndian(width(selected),Big.reduce(Big.multiply(r,w),order(selected)))
    verification(matches(selected,joint(selected,u,v,public,infinity()),r)))

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

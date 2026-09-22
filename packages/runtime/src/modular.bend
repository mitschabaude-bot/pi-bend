import Base
import ./big-nat.bend as Big

# Variable-time arithmetic for public ECDSA values. The binary inverse keeps
# coefficients reduced modulo an odd modulus; Montgomery products eliminate
# bitwise long division. This module is not a private-key arithmetic primitive.
type Context is Data:
  Context{modulus: Big.BigNat, factor: U32, limbs: Nat, squaredRadix: Big.BigNat}

def difference(a: Big.BigNat, b: Big.BigNat) -> Big.BigNat:
  match a b:
    case Big.BigNat{xs} Big.BigNat{ys}: Big.BigNat{Big.trim(Big.subtractLimbs(xs,ys,0))}

def subtractOrdered(order: Cmp, +modulus: Big.BigNat, a: Big.BigNat, b: Big.BigNat) -> Big.BigNat:
  match order:
    case LT{}: difference(Big.add(a,modulus),b)
    case _: difference(a,b)

def subtract(+modulus: Big.BigNat, +a: Big.BigNat, +b: Big.BigNat) -> Big.BigNat:
  subtractOrdered(Big.compare(a,b),modulus,a,b)

def odd(value: Big.BigNat) -> Bool:
  match value:
    case Big.BigNat{Nil{}}: False{}
    case Big.BigNat{head <> _}: U32.is_eq(U32.and(head,1),1)

def halfLimbs(limbs: List<&2,U32>) -> List<&2,U32>:
  match limbs:
    case Nil{}: Nil{}
    case head <> Nil{}: Big.trimHead(U32.shr(head),Nil{})
    case head <> +next <> rest:
      U32.or(U32.shr(head),U32.shln(U32.and(next,1),15n)) <> halfLimbs(next <> rest)

def half(value: Big.BigNat) -> Big.BigNat:
  match value:
    case Big.BigNat{limbs}: Big.BigNat{halfLimbs(limbs)}

def halfCoefficient(isOdd: Bool, modulus: Big.BigNat, value: Big.BigNat) -> Big.BigNat:
  match isOdd:
    case False{}: half(value)
    case True{}: half(Big.add(value,modulus))

# Invariant: u = input*x (mod modulus), v = input*y (mod modulus),
# with x,y reduced. Halving an odd coefficient first adds the odd modulus.
type Inversion is Data:
  Inversion{u: Big.BigNat, v: Big.BigNat, x: Big.BigNat, y: Big.BigNat}

def inverseStepOrder(order: Cmp, +modulus: Big.BigNat, +u: Big.BigNat, +v: Big.BigNat, +x: Big.BigNat, +y: Big.BigNat) -> Inversion:
  match order:
    case GT{}:
      +coefficient = subtract(modulus,x,y)
      Inversion{half(difference(u,v)),v,halfCoefficient(odd(coefficient),modulus,coefficient),y}
    case _:
      +coefficient = subtract(modulus,y,x)
      Inversion{u,half(difference(v,u)),x,halfCoefficient(odd(coefficient),modulus,coefficient)}

def inverseStepFlags(evenU: Bool, evenV: Bool, +modulus: Big.BigNat, +u: Big.BigNat, +v: Big.BigNat, +x: Big.BigNat, +y: Big.BigNat) -> Inversion:
  match evenU evenV:
    case True{} _: Inversion{half(u),v,halfCoefficient(odd(x),modulus,x),y}
    case False{} True{}: Inversion{u,half(v),x,halfCoefficient(odd(y),modulus,y)}
    case False{} False{}: inverseStepOrder(Big.compare(u,v),modulus,u,v,x,y)

def inverseStep(+modulus: Big.BigNat, state: Inversion) -> Inversion:
  match state:
    case Inversion{+u,+v,x,y}: inverseStepFlags(Bool.not(odd(u)),Bool.not(odd(v)),modulus,u,v,x,y)

def finished(state: Inversion) -> Bool:
  match state:
    case Inversion{+u,+v,_,_}: Big.equal(u,Big.one()) || Big.equal(v,Big.one()) || Big.isZero(u) || Big.isZero(v)

def inverseResult(state: Inversion) -> Maybe<&2,Big.BigNat>:
  match state:
    case Inversion{u,+v,x,y}:
      Bool.pick(Maybe<&2,Big.BigNat>,Big.equal(u,Big.one()),Some{x},Bool.pick(Maybe<&2,Big.BigNat>,Big.equal(v,Big.one()),Some{y},None{}))

def inverseLoop(fuel: Nat, done: Bool, +modulus: Big.BigNat, state: Inversion) -> Maybe<&2,Big.BigNat>:
  match fuel done:
    case _ True{}: inverseResult(state)
    case 0n False{}: None{}
    case 1n+n False{}:
      +next = inverseStep(modulus,state)
      inverseLoop(n,finished(next),modulus,next)

# Input must be reduced. Every step decreases total operand bit length: an
# odd-operand subtraction is immediately halved. Fuel bounds the input size.
def inverseOdd(valid: Bool, value: Big.BigNat, modulus: Big.BigNat) -> Maybe<&2,Big.BigNat>:
  match valid modulus:
    case False{} _: None{}
    case True{} Big.BigNat{+limbs}:
      +state = {Inversion{value,Big.BigNat{limbs},Big.one(),Big.zero()} : Inversion}
      inverseLoop(List.length(&2,U32,limbs) * 64n + 1n,finished(state),Big.BigNat{limbs},state)

def inverseGeneric(+value: Big.BigNat, +modulus: Big.BigNat) -> Maybe<&2,Big.BigNat>:
  inverseOdd(odd(modulus) && Bool.not(Big.equal(modulus,Big.one())),value,modulus)

# Each row computes accumulator + factor*value in base 2^16. The largest
# intermediate is (2^16-1)^2 + 2*(2^16-1), exactly representable by U32.
def row(value: List<&2,U32>, accumulator: List<&2,U32>, +factor: U32, carry: U32) -> List<&2,U32>:
  match value accumulator:
    case Nil{} Nil{}: Big.trimHead(carry,Nil{})
    case Nil{} a <> rest:
      +sum = (a + carry : U32)
      U32.and(sum,65535) <> row(Nil{},rest,factor,U32.shrn(sum,16n))
    case a <> rest Nil{}:
      +sum = (a * factor + carry : U32)
      U32.and(sum,65535) <> row(rest,Nil{},factor,U32.shrn(sum,16n))
    case a <> xs b <> ys:
      +sum = (a * factor + b + carry : U32)
      U32.and(sum,65535) <> row(xs,ys,factor,U32.shrn(sum,16n))

def low(limbs: List<&2,U32>) -> U32:
  match limbs:
    case Nil{}: 0
    case head <> _: head

def drop(limbs: List<&2,U32>) -> List<&2,U32>:
  match limbs:
    case Nil{}: Nil{}
    case _ <> rest: rest

# The chosen low word makes accumulator + multiplier*modulus divisible
# by the radix. Dropping that zero word performs an exact division by 2^16.
def cancel(+modulus: List<&2,U32>, +factor: U32, +accumulator: List<&2,U32>) -> List<&2,U32>:
  drop(row(modulus,accumulator,U32.and((low(accumulator) * factor : U32),65535),0))

def productLoop(count: Nat, +modulus: List<&2,U32>, +factor: U32, +a: List<&2,U32>, +b: List<&2,U32>, accumulator: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: accumulator
    case 1n+n: productLoop(n,modulus,factor,a,drop(b),cancel(modulus,factor,row(a,accumulator,low(b),0)))

def normalized(order: Cmp, value: Big.BigNat, modulus: Big.BigNat) -> Big.BigNat:
  match order:
    case LT{}: value
    case _: difference(value,modulus)

def montgomery(context: Context, a: Big.BigNat, b: Big.BigNat) -> Big.BigNat:
  match context a b:
    case Context{Big.BigNat{+modulus},factor,count,_} Big.BigNat{xs} Big.BigNat{ys}:
      +value = {Big.BigNat{Big.trim(productLoop(count,modulus,factor,xs,ys,Nil{}))} : Big.BigNat}
      normalized(Big.compare(value,Big.BigNat{modulus}),value,Big.BigNat{modulus})

# The first operand may be any value below the radix, including unreduced
# ECDSA hashes. The second operand is reduced modulo the context modulus.
def multiply(+context: Context, a: Big.BigNat, b: Big.BigNat) -> Big.BigNat:
  match context:
    case Context{_,_,_,squaredRadix}: montgomery(context,montgomery(context,a,squaredRadix),b)

# SEC 2 group orders. R = 2^(16*limbs), factor = -n^-1 mod 2^16,
# squaredRadix = R^2 mod n. These constants are checked by integer oracles.
def p256() -> Context:
  Context{Big.BigNat{9553 <> 64611 <> 51906 <> 62393 <> 40580 <> 42775 <> 64173 <> 48358 <> 65535 <> 65535 <> 65535 <> 65535 <> 0 <> 0 <> 65535 <> 65535 <> Nil{}},48207,16n,Big.BigNat{61090 <> 48761 <> 19605 <> 33572 <> 28582 <> 18877 <> 31132 <> 18073 <> 60505 <> 11115 <> 45625 <> 10309 <> 22048 <> 62425 <> 11668 <> 26337 <> Nil{}}}

def p384() -> Context:
  Context{Big.BigNat{10611 <> 52421 <> 6506 <> 60652 <> 42874 <> 18608 <> 3506 <> 22554 <> 11743 <> 62519 <> 19841 <> 51043 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> 65535 <> Nil{}},56389,24n,Big.BigNat{2473 <> 6580 <> 39716 <> 11569 <> 42009 <> 57114 <> 33253 <> 65341 <> 10567 <> 64696 <> 18490 <> 48190 <> 7365 <> 19115 <> 18711 <> 54285 <> 26773 <> 10278 <> 23418 <> 16304 <> 48929 <> 11065 <> 60929 <> 3204 <> Nil{}}}

# Inversion uses twelve machine words: one allocation per integer rather than
# a linked node per half-word. P-256 values simply have four leading zero words.
type Wide is Data:
  Wide{a0: U32,a1: U32,a2: U32,a3: U32,a4: U32,a5: U32,a6: U32,a7: U32,a8: U32,a9: U32,a10: U32,a11: U32}

type WideSum is Data:
  WideSum{value: Wide, carry: U32}

def wideZero() -> Wide: Wide{0,0,0,0,0,0,0,0,0,0,0,0}

def wideOne() -> Wide: Wide{1,0,0,0,0,0,0,0,0,0,0,0}

def wideEqual(a: Wide, b: Wide) -> Bool:
  match a b:
    case Wide{+a0,+a1,+a2,+a3,+a4,+a5,+a6,+a7,+a8,+a9,+a10,+a11} Wide{+b0,+b1,+b2,+b3,+b4,+b5,+b6,+b7,+b8,+b9,+b10,+b11}: U32.is_eq(a0,b0) && U32.is_eq(a1,b1) && U32.is_eq(a2,b2) && U32.is_eq(a3,b3) && U32.is_eq(a4,b4) && U32.is_eq(a5,b5) && U32.is_eq(a6,b6) && U32.is_eq(a7,b7) && U32.is_eq(a8,b8) && U32.is_eq(a9,b9) && U32.is_eq(a10,b10) && U32.is_eq(a11,b11)

def wideCompare(a: Wide, b: Wide) -> Cmp:
  match a b:
    case Wide{+a0,+a1,+a2,+a3,+a4,+a5,+a6,+a7,+a8,+a9,+a10,+a11} Wide{+b0,+b1,+b2,+b3,+b4,+b5,+b6,+b7,+b8,+b9,+b10,+b11}: Big.compareLow(U32.cmp(a11,b11),Big.compareLow(U32.cmp(a10,b10),Big.compareLow(U32.cmp(a9,b9),Big.compareLow(U32.cmp(a8,b8),Big.compareLow(U32.cmp(a7,b7),Big.compareLow(U32.cmp(a6,b6),Big.compareLow(U32.cmp(a5,b5),Big.compareLow(U32.cmp(a4,b4),Big.compareLow(U32.cmp(a3,b3),Big.compareLow(U32.cmp(a2,b2),Big.compareLow(U32.cmp(a1,b1),U32.cmp(a0,b0))))))))))))

def wideOdd(value: Wide) -> Bool:
  match value:
    case Wide{a0,_,_,_,_,_,_,_,_,_,_,_}: U32.is_eq(U32.and(a0,1),1)

def wideHalf(carry: U32, value: Wide) -> Wide:
  match value:
    case Wide{+a0,+a1,+a2,+a3,+a4,+a5,+a6,+a7,+a8,+a9,+a10,+a11}: Wide{U32.or(U32.shr(a0),U32.shln(U32.and(a1,1),31n)),U32.or(U32.shr(a1),U32.shln(U32.and(a2,1),31n)),U32.or(U32.shr(a2),U32.shln(U32.and(a3,1),31n)),U32.or(U32.shr(a3),U32.shln(U32.and(a4,1),31n)),U32.or(U32.shr(a4),U32.shln(U32.and(a5,1),31n)),U32.or(U32.shr(a5),U32.shln(U32.and(a6,1),31n)),U32.or(U32.shr(a6),U32.shln(U32.and(a7,1),31n)),U32.or(U32.shr(a7),U32.shln(U32.and(a8,1),31n)),U32.or(U32.shr(a8),U32.shln(U32.and(a9,1),31n)),U32.or(U32.shr(a9),U32.shln(U32.and(a10,1),31n)),U32.or(U32.shr(a10),U32.shln(U32.and(a11,1),31n)),U32.or(U32.shr(a11),U32.shln(carry,31n))}

def wideAdd(a: Wide, b: Wide) -> WideSum:
  match a b:
    case Wide{+a0,+a1,+a2,+a3,+a4,+a5,+a6,+a7,+a8,+a9,+a10,+a11} Wide{+b0,+b1,+b2,+b3,+b4,+b5,+b6,+b7,+b8,+b9,+b10,+b11}:
      +s0 = (a0 + b0 : U32)
      +r0 = s0
      +c0 = Bool.pick(U32,U32.is_lt(s0,a0),1,0)
      +s1 = (a1 + b1 : U32)
      +r1 = (s1 + c0 : U32)
      +c1 = Bool.pick(U32,U32.is_lt(s1,a1) || U32.is_lt(r1,s1),1,0)
      +s2 = (a2 + b2 : U32)
      +r2 = (s2 + c1 : U32)
      +c2 = Bool.pick(U32,U32.is_lt(s2,a2) || U32.is_lt(r2,s2),1,0)
      +s3 = (a3 + b3 : U32)
      +r3 = (s3 + c2 : U32)
      +c3 = Bool.pick(U32,U32.is_lt(s3,a3) || U32.is_lt(r3,s3),1,0)
      +s4 = (a4 + b4 : U32)
      +r4 = (s4 + c3 : U32)
      +c4 = Bool.pick(U32,U32.is_lt(s4,a4) || U32.is_lt(r4,s4),1,0)
      +s5 = (a5 + b5 : U32)
      +r5 = (s5 + c4 : U32)
      +c5 = Bool.pick(U32,U32.is_lt(s5,a5) || U32.is_lt(r5,s5),1,0)
      +s6 = (a6 + b6 : U32)
      +r6 = (s6 + c5 : U32)
      +c6 = Bool.pick(U32,U32.is_lt(s6,a6) || U32.is_lt(r6,s6),1,0)
      +s7 = (a7 + b7 : U32)
      +r7 = (s7 + c6 : U32)
      +c7 = Bool.pick(U32,U32.is_lt(s7,a7) || U32.is_lt(r7,s7),1,0)
      +s8 = (a8 + b8 : U32)
      +r8 = (s8 + c7 : U32)
      +c8 = Bool.pick(U32,U32.is_lt(s8,a8) || U32.is_lt(r8,s8),1,0)
      +s9 = (a9 + b9 : U32)
      +r9 = (s9 + c8 : U32)
      +c9 = Bool.pick(U32,U32.is_lt(s9,a9) || U32.is_lt(r9,s9),1,0)
      +s10 = (a10 + b10 : U32)
      +r10 = (s10 + c9 : U32)
      +c10 = Bool.pick(U32,U32.is_lt(s10,a10) || U32.is_lt(r10,s10),1,0)
      +s11 = (a11 + b11 : U32)
      +r11 = (s11 + c10 : U32)
      +c11 = Bool.pick(U32,U32.is_lt(s11,a11) || U32.is_lt(r11,s11),1,0)
      WideSum{Wide{r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11},c11}

def wideDifference(a: Wide, b: Wide) -> Wide:
  match a b:
    case Wide{+a0,+a1,+a2,+a3,+a4,+a5,+a6,+a7,+a8,+a9,+a10,+a11} Wide{+b0,+b1,+b2,+b3,+b4,+b5,+b6,+b7,+b8,+b9,+b10,+b11}:
      r0 = (a0 - b0 : U32)
      +c0 = Bool.pick(U32,U32.is_lt(a0,b0),1,0)
      r1 = (a1 - b1 - c0 : U32)
      +c1 = Bool.pick(U32,U32.is_lt(a1,b1) || (U32.is_eq(a1,b1) && U32.is_eq(c0,1)),1,0)
      r2 = (a2 - b2 - c1 : U32)
      +c2 = Bool.pick(U32,U32.is_lt(a2,b2) || (U32.is_eq(a2,b2) && U32.is_eq(c1,1)),1,0)
      r3 = (a3 - b3 - c2 : U32)
      +c3 = Bool.pick(U32,U32.is_lt(a3,b3) || (U32.is_eq(a3,b3) && U32.is_eq(c2,1)),1,0)
      r4 = (a4 - b4 - c3 : U32)
      +c4 = Bool.pick(U32,U32.is_lt(a4,b4) || (U32.is_eq(a4,b4) && U32.is_eq(c3,1)),1,0)
      r5 = (a5 - b5 - c4 : U32)
      +c5 = Bool.pick(U32,U32.is_lt(a5,b5) || (U32.is_eq(a5,b5) && U32.is_eq(c4,1)),1,0)
      r6 = (a6 - b6 - c5 : U32)
      +c6 = Bool.pick(U32,U32.is_lt(a6,b6) || (U32.is_eq(a6,b6) && U32.is_eq(c5,1)),1,0)
      r7 = (a7 - b7 - c6 : U32)
      +c7 = Bool.pick(U32,U32.is_lt(a7,b7) || (U32.is_eq(a7,b7) && U32.is_eq(c6,1)),1,0)
      r8 = (a8 - b8 - c7 : U32)
      +c8 = Bool.pick(U32,U32.is_lt(a8,b8) || (U32.is_eq(a8,b8) && U32.is_eq(c7,1)),1,0)
      r9 = (a9 - b9 - c8 : U32)
      +c9 = Bool.pick(U32,U32.is_lt(a9,b9) || (U32.is_eq(a9,b9) && U32.is_eq(c8,1)),1,0)
      r10 = (a10 - b10 - c9 : U32)
      +c10 = Bool.pick(U32,U32.is_lt(a10,b10) || (U32.is_eq(a10,b10) && U32.is_eq(c9,1)),1,0)
      r11 = (a11 - b11 - c10 : U32)
      Wide{r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11}

def wideSumValue(value: WideSum) -> Wide:
  match value:
    case WideSum{n,_}: n

def wideSumHalf(value: WideSum) -> Wide:
  match value:
    case WideSum{n,c}: wideHalf(c,n)

def wideSubtractOrder(order: Cmp, modulus: Wide, a: Wide, b: Wide) -> Wide:
  match order:
    case LT{}: wideSumValue(wideAdd(wideDifference(a,b),modulus))
    case _: wideDifference(a,b)

def wideSubtract(+modulus: Wide, +a: Wide, +b: Wide) -> Wide: wideSubtractOrder(wideCompare(a,b),modulus,a,b)

def wideHalfCoefficient(isOdd: Bool, modulus: Wide, value: Wide) -> Wide:
  match isOdd:
    case True{}: wideSumHalf(wideAdd(value,modulus))
    case False{}: wideHalf(0,value)

def packWords(limbs: List<&2,U32>) -> List<&2,U32>:
  match limbs:
    case Nil{}: Nil{}
    case a <> Nil{}: a <> Nil{}
    case a <> b <> rest: U32.or(a,U32.shln(b,16n)) <> packWords(rest)

def wideRead(words: List<&2,U32>) -> Wide:
  match words:
    case Nil{}: Wide{0,0,0,0,0,0,0,0,0,0,0,0}
    case a0 <> rest0:
    match rest0:
      case Nil{}: Wide{a0,0,0,0,0,0,0,0,0,0,0,0}
      case a1 <> rest1:
      match rest1:
        case Nil{}: Wide{a0,a1,0,0,0,0,0,0,0,0,0,0}
        case a2 <> rest2:
        match rest2:
          case Nil{}: Wide{a0,a1,a2,0,0,0,0,0,0,0,0,0}
          case a3 <> rest3:
          match rest3:
            case Nil{}: Wide{a0,a1,a2,a3,0,0,0,0,0,0,0,0}
            case a4 <> rest4:
            match rest4:
              case Nil{}: Wide{a0,a1,a2,a3,a4,0,0,0,0,0,0,0}
              case a5 <> rest5:
              match rest5:
                case Nil{}: Wide{a0,a1,a2,a3,a4,a5,0,0,0,0,0,0}
                case a6 <> rest6:
                match rest6:
                  case Nil{}: Wide{a0,a1,a2,a3,a4,a5,a6,0,0,0,0,0}
                  case a7 <> rest7:
                  match rest7:
                    case Nil{}: Wide{a0,a1,a2,a3,a4,a5,a6,a7,0,0,0,0}
                    case a8 <> rest8:
                    match rest8:
                      case Nil{}: Wide{a0,a1,a2,a3,a4,a5,a6,a7,a8,0,0,0}
                      case a9 <> rest9:
                      match rest9:
                        case Nil{}: Wide{a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,0,0}
                        case a10 <> rest10:
                        match rest10:
                          case Nil{}: Wide{a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,0}
                          case a11 <> _: Wide{a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11}

def wideFrom(value: Big.BigNat) -> Wide:
  match value:
    case Big.BigNat{limbs}: wideRead(packWords(limbs))

def wideTo(value: Wide) -> Big.BigNat:
  match value:
    case Wide{+a0,+a1,+a2,+a3,+a4,+a5,+a6,+a7,+a8,+a9,+a10,+a11}: Big.BigNat{Big.trim(U32.and(a0,65535) <> U32.shrn(a0,16n) <> U32.and(a1,65535) <> U32.shrn(a1,16n) <> U32.and(a2,65535) <> U32.shrn(a2,16n) <> U32.and(a3,65535) <> U32.shrn(a3,16n) <> U32.and(a4,65535) <> U32.shrn(a4,16n) <> U32.and(a5,65535) <> U32.shrn(a5,16n) <> U32.and(a6,65535) <> U32.shrn(a6,16n) <> U32.and(a7,65535) <> U32.shrn(a7,16n) <> U32.and(a8,65535) <> U32.shrn(a8,16n) <> U32.and(a9,65535) <> U32.shrn(a9,16n) <> U32.and(a10,65535) <> U32.shrn(a10,16n) <> U32.and(a11,65535) <> U32.shrn(a11,16n) <> Nil{})}

type WideInversion is Data:
  WideInversion{u: Wide, v: Wide, x: Wide, y: Wide}

def wideStepOrder(order: Cmp, +modulus: Wide, +u: Wide, +v: Wide, +x: Wide, +y: Wide) -> WideInversion:
  match order:
    case GT{}:
      +coefficient = wideSubtract(modulus,x,y)
      WideInversion{wideHalf(0,wideDifference(u,v)),v,wideHalfCoefficient(wideOdd(coefficient),modulus,coefficient),y}
    case _:
      +coefficient = wideSubtract(modulus,y,x)
      WideInversion{u,wideHalf(0,wideDifference(v,u)),x,wideHalfCoefficient(wideOdd(coefficient),modulus,coefficient)}

def wideStepFlags(evenU: Bool, evenV: Bool, +modulus: Wide, +u: Wide, +v: Wide, +x: Wide, +y: Wide) -> WideInversion:
  match evenU evenV:
    case True{} _: WideInversion{wideHalf(0,u),v,wideHalfCoefficient(wideOdd(x),modulus,x),y}
    case False{} True{}: WideInversion{u,wideHalf(0,v),x,wideHalfCoefficient(wideOdd(y),modulus,y)}
    case False{} False{}: wideStepOrder(wideCompare(u,v),modulus,u,v,x,y)

def wideStep(+modulus: Wide, state: WideInversion) -> WideInversion:
  match state:
    case WideInversion{+u,+v,x,y}: wideStepFlags(Bool.not(wideOdd(u)),Bool.not(wideOdd(v)),modulus,u,v,x,y)

def wideFinished(state: WideInversion) -> Bool:
  match state:
    case WideInversion{+u,+v,_,_}: wideEqual(u,wideOne()) || wideEqual(v,wideOne()) || wideEqual(u,wideZero()) || wideEqual(v,wideZero())

def wideResult(state: WideInversion) -> Maybe<&2,Wide>:
  match state:
    case WideInversion{u,+v,x,y}:
      Bool.pick(Maybe<&2,Wide>,wideEqual(u,wideOne()),Some{x},Bool.pick(Maybe<&2,Wide>,wideEqual(v,wideOne()),Some{y},None{}))

def wideLoop(fuel: Nat, done: Bool, +modulus: Wide, state: WideInversion) -> Maybe<&2,Wide>:
  match fuel done:
    case _ True{}: wideResult(state)
    case 0n False{}: None{}
    case 1n+n False{}:
      +next = wideStep(modulus,state)
      wideLoop(n,wideFinished(next),modulus,next)


def wideMaybe(value: Maybe<&2,Wide>) -> Maybe<&2,Big.BigNat>:
  match value:
    case None{}: None{}
    case Some{n}: Some{wideTo(n)}

def wideInverse(value: Big.BigNat, +modulus: Big.BigNat) -> Maybe<&2,Big.BigNat>:
  +state = {WideInversion{wideFrom(value),wideFrom(modulus),wideOne(),wideZero()} : WideInversion}
  wideMaybe(wideLoop(1537n,wideFinished(state),wideFrom(modulus),state))

def inverseSize(fits: Bool, value: Big.BigNat, modulus: Big.BigNat) -> Maybe<&2,Big.BigNat>:
  match fits:
    case True{}: wideInverse(value,modulus)
    case False{}: inverseGeneric(value,modulus)

def inverseValid(valid: Bool, value: Big.BigNat, modulus: Big.BigNat) -> Maybe<&2,Big.BigNat>:
  match valid modulus:
    case False{} _: None{}
    case True{} Big.BigNat{+limbs}: inverseSize(Nat.is_le(List.length(&2,U32,limbs),24n),value,Big.BigNat{limbs})

def inverse(+value: Big.BigNat, +modulus: Big.BigNat) -> Maybe<&2,Big.BigNat>: inverseValid(odd(modulus) && Bool.not(Big.equal(modulus,Big.one())),value,modulus)

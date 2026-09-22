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

type Half is Data:
  Half{limbs: List<&2,U32>, carry: U32}

def halfHead(+head: U32, tail: Half) -> Half:
  match tail:
    case Half{limbs,carry}: Half{Big.trimHead(U32.or(U32.shr(head),U32.shln(carry,15n)),limbs),U32.and(head,1)}

def halfLimbs(limbs: List<&2,U32>) -> Half:
  match limbs:
    case Nil{}: Half{Nil{},0}
    case head <> rest: halfHead(head,halfLimbs(rest))

def halfResult(value: Half) -> Big.BigNat:
  match value:
    case Half{limbs,_}: Big.BigNat{limbs}

def half(value: Big.BigNat) -> Big.BigNat:
  match value:
    case Big.BigNat{limbs}: halfResult(halfLimbs(limbs))

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
    case GT{}: Inversion{difference(u,v),v,subtract(modulus,x,y),y}
    case _: Inversion{u,difference(v,u),x,subtract(modulus,y,x)}

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

# Input must be reduced. Each halving decreases the total operand bit length;
# each subtraction of odd operands enables a halving on the following step.
def inverseOdd(valid: Bool, value: Big.BigNat, modulus: Big.BigNat) -> Maybe<&2,Big.BigNat>:
  match valid modulus:
    case False{} _: None{}
    case True{} Big.BigNat{+limbs}:
      +state = {Inversion{value,Big.BigNat{limbs},Big.one(),Big.zero()} : Inversion}
      inverseLoop(List.length(&2,U32,limbs) * 64n + 1n,finished(state),Big.BigNat{limbs},state)

def inverse(+value: Big.BigNat, +modulus: Big.BigNat) -> Maybe<&2,Big.BigNat>:
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

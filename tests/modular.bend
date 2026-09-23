import Base
import ../packages/runtime/src/modular.bend as M
import ../packages/runtime/src/big-nat.bend as Big
import ../packages/runtime/src/string.bend as S

def parsed(value: Maybe<&2,Big.BigNat>) -> Big.BigNat:
  match value:
    case None{}: Big.zero()
    case Some{n}: n

def number(value: String) -> Big.BigNat: parsed(Big.fromDecimal(value))

def shown(value: Maybe<&2,Big.BigNat>) -> String:
  match value:
    case None{}: "none"
    case Some{n}: Big.toDecimal(n)

def context(curve: String) -> M.Context:
  match curve:
    case "256": M.p256()
    case _: M.p384()

def modulus(value: M.Context) -> Big.BigNat:
  match value:
    case M.Context{n,_,_,_}: n

def benchStep(+ctx: M.Context, +value: Big.BigNat, inverted: Maybe<&2,Big.BigNat>) -> Big.BigNat:
  match inverted:
    case None{}: Big.zero()
    case Some{w}: M.multiply(ctx,value,w)

def bench(count: Nat, +ctx: M.Context, +value: Big.BigNat, accumulator: Big.BigNat) -> Big.BigNat:
  match count:
    case 0n: accumulator
    case 1n+n: bench(n,ctx,value,Big.add(accumulator,benchStep(ctx,value,M.inverse(value,modulus(ctx)))))

def inverseValue(value: Maybe<&2,Big.BigNat>) -> Big.BigNat:
  match value:
    case None{}: Big.zero()
    case Some{n}: n

def benchInverse(count: Nat, +ctx: M.Context, +value: Big.BigNat, accumulator: Big.BigNat) -> Big.BigNat:
  match count:
    case 0n: accumulator
    case 1n+n: benchInverse(n,ctx,value,Big.add(accumulator,inverseValue(M.inverse(value,modulus(ctx)))))

def benchMultiply(count: Nat, +ctx: M.Context, +value: Big.BigNat, accumulator: Big.BigNat) -> Big.BigNat:
  match count:
    case 0n: accumulator
    case 1n+n: benchMultiply(n,ctx,value,Big.add(accumulator,M.multiply(ctx,value,value)))

def run(parts: List<&2,String>) -> String:
  match parts:
    case "i" <> a <> n <> Nil{}: shown(M.inverse(number(a),number(n)))
    case "m" <> curve <> a <> b <> Nil{}: Big.toDecimal(M.multiply(context(curve),number(a),number(b)))
    case "bi" <> curve <> a <> Nil{}: Big.toDecimal(benchInverse(1000n,context(curve),number(a),Big.zero()))
    case "bm" <> curve <> a <> Nil{}: Big.toDecimal(benchMultiply(1000n,context(curve),number(a),Big.zero()))
    case "b" <> curve <> a <> Nil{}: Big.toDecimal(bench(1000n,context(curve),number(a),Big.zero()))
    case _: "invalid"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(S.split(head,':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

# F64 arithmetic on literals is folded at compile time (BEND-047), so records
# holding such values can be static. Expected: 0.02 14 -8 natively and on Bun.
import Base

type Cost is Data: Cost{a: F64, b: F64, c: F64}

def cost() -> Cost: Cost{F64.div(U32.to_f64(1), U32.to_f64(50)), U32.to_f64(14), F64.mul(F64.sub(U32.to_f64(3), U32.to_f64(7)), U32.to_f64(2))}

def shown(value: Cost) -> String:
  match value:
    case Cost{a, b, c}: F64.show(a) ++ " " ++ F64.show(b) ++ " " ++ F64.show(c)

def main() -> IO(Unit): IO.print(shown(cost()))

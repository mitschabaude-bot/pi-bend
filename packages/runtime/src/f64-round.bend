import Base
import ./f64.bend as F

# Rounding toward positive infinity preserves negative zero and non-finite
# values. Only a positive fractional remainder requires an increment.
def rounded(order: Maybe<&2, Cmp>, integral: F.F64) -> F.F64:
  match order:
    case Some{GT{}}: F.add(integral, F.fromU32(1))
    case _: integral

def ceil(+value: F.F64) -> F.F64:
  +integral = F.truncate(value)
  rounded(F.compare(value, integral), integral)

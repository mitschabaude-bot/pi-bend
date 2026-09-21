import Base
import ./calendar.bend as C
import ./u64.bend as W

# Invert the existing literal-year UTC conversion over years 0000..9999.
# Shift signed epochs into a nonnegative day count before unsigned division.
type Error is Data:
  OutOfRange{}
  ReconstructionMismatch{}

def epochOffset() -> W.U64: W.multiply(W.fromU32(719528), W.fromU32(86400000))
def extent() -> W.U64: W.multiply(W.fromU32(C.yearStart(10000)), W.fromU32(86400000))

def year(fuel: Nat, +day: U32, +low: U32, +high: U32) -> U32:
  match fuel:
    case Zero{}: low
    case Succ{rest}:
      +middle = ((low + high + 1) / 2 : U32)
      +fits = U32.is_le(C.yearStart(middle), day)
      year(rest, day, Bool.pick(U32, fits, middle, low), Bool.pick(U32, fits, high, (middle - 1 : U32)))

def month(fuel: Nat, +day: U32, +year: U32, +candidate: U32) -> U32:
  match fuel:
    case Zero{}: 1
    case Succ{rest}:
      Bool.pick(U32, U32.is_ge(day, C.dayIndex(year, candidate, 1)), candidate, month(rest, day, year, (candidate - 1 : U32)))

def civil(+day: U32, +millis: U32, +year: U32, +month: U32) -> C.CivilTime:
  C.CivilTime{year, month, (day - C.dayIndex(year, month, 1) + 1 : U32), (millis / 3600000 : U32), ((millis / 60000) % 60 : U32), ((millis / 1000) % 60 : U32), (millis % 1000 : U32)}

def inYear(+day: U32, millis: U32, +selected: U32) -> C.CivilTime:
  civil(day, millis, selected, month(12n, day, selected, 12))

def same(epoch: W.U64, result: Result<&2, &2, C.CalendarError, W.U64>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{value}: W.equal(epoch, value)

# Never expose an invalid or lossy reconstruction. This check also makes the
# public success invariant independent of the search implementation.
def verified(value: C.CivilTime, valid: Bool) -> Result<&2, &2, Error, C.CivilTime>:
  match valid:
    case False{}: Fail{ReconstructionMismatch{}}
    case True{}: Done{value}

def checked(epoch: W.U64, +value: C.CivilTime) -> Result<&2, &2, Error, C.CivilTime>:
  verified(value, same(epoch, C.toEpochMilliseconds(value)))

def narrowed(epoch: W.U64, +day: U32, millis: U32, valid: Bool) -> Result<&2, &2, Error, C.CivilTime>:
  match valid:
    case False{}: Fail{ReconstructionMismatch{}}
    case True{}: Done{inYear(day, millis, year(14n, day, 0, 9999))}

def words(epoch: W.U64, day: W.U64, millis: W.U64) -> Result<&2, &2, Error, C.CivilTime>:
  match day millis:
    case W.U64{highDay, lowDay} W.U64{highMillis, lowMillis}:
      narrowed(epoch, lowDay, lowMillis, U32.is_eq(highDay, 0) && U32.is_eq(highMillis, 0))

def divided(epoch: W.U64, result: Maybe<&2, W.Division>) -> Result<&2, &2, Error, C.CivilTime>:
  match result:
    case None{}: Fail{ReconstructionMismatch{}}
    case Some{W.Division{day, millis}}: words(epoch, day, millis)

def ranged(epoch: W.U64, shifted: W.U64, order: Cmp) -> Result<&2, &2, Error, C.CivilTime>:
  match order:
    case LT{}: divided(epoch, W.divide(shifted, W.fromU32(86400000)))
    case _: Fail{OutOfRange{}}

def validate(epoch: W.U64, result: Result<&2, &2, Error, C.CivilTime>) -> Result<&2, &2, Error, C.CivilTime>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{value}: checked(epoch, value)

def fromEpochMilliseconds(+epoch: W.U64) -> Result<&2, &2, Error, C.CivilTime>:
  +shifted = W.add(epoch, epochOffset())
  validate(epoch, ranged(epoch, shifted, W.compare(shifted, extent())))

import Base
import ./u64.bend as W


# Proleptic Gregorian UTC fields for four-digit protocol years. Year zero is
# literal year zero; two-digit year interpretation belongs to the parser.
type CivilTime is Data:
  CivilTime{year: U32, month: U32, day: U32, hour: U32, minute: U32, second: U32, millisecond: U32}

type CalendarError is Data:
  InvalidYear{}
  InvalidMonth{}
  InvalidDay{}
  InvalidTime{}

def leapYear(+year: U32) -> Bool:
  U32.is_eq((year % 4 : U32), 0) && (Bool.not(U32.is_eq((year % 100 : U32), 0)) || U32.is_eq((year % 400 : U32), 0))

def daysInMonth(year: U32, month: U32) -> U32:
  match month:
    case 1: 31
    case 2: Bool.pick(U32, leapYear(year), 29, 28)
    case 3: 31
    case 4: 30
    case 5: 31
    case 6: 30
    case 7: 31
    case 8: 31
    case 9: 30
    case 10: 31
    case 11: 30
    case 12: 31
    case _: 0

def commonMonthStart(month: U32) -> U32:
  match month:
    case 1: 0
    case 2: 31
    case 3: 59
    case 4: 90
    case 5: 120
    case 6: 151
    case 7: 181
    case 8: 212
    case 9: 243
    case 10: 273
    case 11: 304
    case 12: 334
    case _: 0

# Count leap days before January 1. The +3/+99/+399 terms include year
# zero's leap day when appropriate without subtracting below unsigned zero.
def yearStart(+year: U32) -> U32:
  (year * 365 + (year + 3) / 4 - (year + 99) / 100 + (year + 399) / 400 : U32)

def dayIndex(+year: U32, +month: U32, day: U32) -> U32:
  (yearStart(year) + commonMonthStart(month) + Bool.pick(U32, U32.is_gt(month, 2) && leapYear(year), 1, 0) + day - 1 : U32)

def timeMilliseconds(hour: U32, minute: U32, second: U32, millisecond: U32) -> U32:
  (hour * 3600000 + minute * 60000 + second * 1000 + millisecond : U32)

# A two's-complement U64 is an exact signed millisecond count. Subtract the
# epoch offset in word arithmetic, retaining pre-1970 dates without floats.
def epochUnchecked(value: CivilTime) -> W.U64:
  match value:
    case CivilTime{year, month, day, hour, minute, second, millisecond}:
      days = W.subtract(W.fromU32(dayIndex(year, month, day)), W.fromU32(719528))
      W.add(W.multiply(days, W.fromU32(86400000)), W.fromU32(timeMilliseconds(hour, minute, second, millisecond)))

def validateTime(valid: Bool, value: CivilTime) -> Result<&2, &2, CalendarError, W.U64>:
  match valid:
    case False{}: Fail{InvalidTime{}}
    case True{}: Done{epochUnchecked(value)}

def validateDay(valid: Bool, +value: CivilTime) -> Result<&2, &2, CalendarError, W.U64>:
  match valid value:
    case False{} _: Fail{InvalidDay{}}
    case True{} CivilTime{_, _, _, hour, minute, second, millisecond}:
      validateTime(U32.is_lt(hour, 24) && U32.is_lt(minute, 60) && U32.is_lt(second, 60) && U32.is_lt(millisecond, 1000), value)

def validateMonth(valid: Bool, +value: CivilTime) -> Result<&2, &2, CalendarError, W.U64>:
  match valid value:
    case False{} _: Fail{InvalidMonth{}}
    case True{} CivilTime{year, month, +day, _, _, _, _}:
      validateDay(U32.is_ge(day, 1) && U32.is_le(day, daysInMonth(year, month)), value)

def validateYear(valid: Bool, +value: CivilTime) -> Result<&2, &2, CalendarError, W.U64>:
  match valid value:
    case False{} _: Fail{InvalidYear{}}
    case True{} CivilTime{_, +month, _, _, _, _, _}:
      validateMonth(U32.is_ge(month, 1) && U32.is_le(month, 12), value)

def toEpochMilliseconds(+value: CivilTime) -> Result<&2, &2, CalendarError, W.U64>:
  match value:
    case CivilTime{year, _, _, _, _, _, _}: validateYear(U32.is_le(year, 9999), value)


# Invert the existing literal-year UTC conversion over years 0000..9999.
# Shift signed epochs into a nonnegative day count before unsigned division.
type Error is Data:
  OutOfRange{}
  ReconstructionMismatch{}

def epochOffset() -> W.U64: W.multiply(W.fromU32(719528), W.fromU32(86400000))
def extent() -> W.U64: W.multiply(W.fromU32(yearStart(10000)), W.fromU32(86400000))

def inverseYear(fuel: Nat, +day: U32, +low: U32, +high: U32) -> U32:
  match fuel:
    case Zero{}: low
    case Succ{rest}:
      +middle = ((low + high + 1) / 2 : U32)
      +fits = U32.is_le(yearStart(middle), day)
      inverseYear(rest, day, Bool.pick(U32, fits, middle, low), Bool.pick(U32, fits, high, (middle - 1 : U32)))

def inverseMonth(fuel: Nat, +day: U32, +year: U32, +candidate: U32) -> U32:
  match fuel:
    case Zero{}: 1
    case Succ{rest}:
      Bool.pick(U32, U32.is_ge(day, dayIndex(year, candidate, 1)), candidate, inverseMonth(rest, day, year, (candidate - 1 : U32)))

def civil(+day: U32, +millis: U32, +year: U32, +month: U32) -> CivilTime:
  CivilTime{year, month, (day - dayIndex(year, month, 1) + 1 : U32), (millis / 3600000 : U32), ((millis / 60000) % 60 : U32), ((millis / 1000) % 60 : U32), (millis % 1000 : U32)}

def inYear(+day: U32, millis: U32, +selected: U32) -> CivilTime:
  civil(day, millis, selected, inverseMonth(12n, day, selected, 12))

def same(epoch: W.U64, result: Result<&2, &2, CalendarError, W.U64>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{value}: W.equal(epoch, value)

# Never expose an invalid or lossy reconstruction. This check also makes the
# public success invariant independent of the search implementation.
def verified(value: CivilTime, valid: Bool) -> Result<&2, &2, Error, CivilTime>:
  match valid:
    case False{}: Fail{ReconstructionMismatch{}}
    case True{}: Done{value}

def checked(epoch: W.U64, +value: CivilTime) -> Result<&2, &2, Error, CivilTime>:
  verified(value, same(epoch, toEpochMilliseconds(value)))

def narrowed(epoch: W.U64, +day: U32, millis: U32, valid: Bool) -> Result<&2, &2, Error, CivilTime>:
  match valid:
    case False{}: Fail{ReconstructionMismatch{}}
    case True{}: Done{inYear(day, millis, inverseYear(14n, day, 0, 9999))}

def words(epoch: W.U64, day: W.U64, millis: W.U64) -> Result<&2, &2, Error, CivilTime>:
  match day millis:
    case W.U64{highDay, lowDay} W.U64{highMillis, lowMillis}:
      narrowed(epoch, lowDay, lowMillis, U32.is_eq(highDay, 0) && U32.is_eq(highMillis, 0))

def divided(epoch: W.U64, result: Maybe<&2, W.Division>) -> Result<&2, &2, Error, CivilTime>:
  match result:
    case None{}: Fail{ReconstructionMismatch{}}
    case Some{W.Division{day, millis}}: words(epoch, day, millis)

def ranged(epoch: W.U64, shifted: W.U64, order: Cmp) -> Result<&2, &2, Error, CivilTime>:
  match order:
    case LT{}: divided(epoch, W.divide(shifted, W.fromU32(86400000)))
    case _: Fail{OutOfRange{}}

def validate(epoch: W.U64, result: Result<&2, &2, Error, CivilTime>) -> Result<&2, &2, Error, CivilTime>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{value}: checked(epoch, value)

def fromEpochMilliseconds(+epoch: W.U64) -> Result<&2, &2, Error, CivilTime>:
  +shifted = W.add(epoch, epochOffset())
  validate(epoch, ranged(epoch, shifted, W.compare(shifted, extent())))

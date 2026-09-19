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

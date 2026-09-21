import Base
import ./http-date-syntax.bend as Syntax
import ./http-date-year.bend as Year
import ./calendar.bend as Calendar
import ./u64.bend as W

# Unix timestamps cannot identify a leap second uniquely. Preserve that case
# explicitly rather than silently shifting it into the following day.
type Instant is Data:
  Ordinary{milliseconds: W.U64}
  LeapSecond{precedingMilliseconds: W.U64}

type Error is Data:
  InvalidSyntax{}
  YearFailure{cause: Year.Error}
  CalendarFailure{cause: Calendar.CalendarError}
  WeekdayMismatch{}
  InvalidLeapPosition{}

type UnixError is Data:
  LeapSecondNotRepresentable{}

def unixMilliseconds(instant: Instant) -> Result<&2, &2, UnixError, W.U64>:
  match instant:
    case Ordinary{value}: Done{value}
    case LeapSecond{_}: Fail{LeapSecondNotRepresentable{}}

def tagged(leap: Bool, milliseconds: W.U64) -> Instant:
  match leap:
    case False{}: Ordinary{milliseconds}
    case True{}: LeapSecond{milliseconds}

def checkedWeekday(valid: Bool, leap: Bool, milliseconds: W.U64) -> Result<&2, &2, Error, Instant>:
  match valid:
    case False{}: Fail{WeekdayMismatch{}}
    case True{}: Done{tagged(leap, milliseconds)}

# Calendar day zero (0000-01-01) is Saturday; syntax numbers Monday as one.
def weekday(year: U32, month: U32, day: U32) -> U32:
  ((Calendar.dayIndex(year, month, day) + 5) % 7 + 1 : U32)

def checkedCalendar(year: U32, month: U32, day: U32, claimedWeekday: U32, leap: Bool, result: Result<&2, &2, Calendar.CalendarError, W.U64>) -> Result<&2, &2, Error, Instant>:
  match result:
    case Fail{cause}: Fail{CalendarFailure{cause}}
    case Done{milliseconds}: checkedWeekday(U32.is_eq(weekday(year, month, day), claimedWeekday), leap, milliseconds)

def clock(validLeap: Bool, +year: U32, date: Syntax.DateFields, +leap: Bool) -> Result<&2, &2, Error, Instant>:
  match validLeap date:
    case False{} _: Fail{InvalidLeapPosition{}}
    case True{} Syntax.DateFields{_, claimed, _, +month, +day, Syntax.ClockFields{hour, minute, second}}:
      checkedCalendar(year, month, day, claimed, leap, Calendar.toEpochMilliseconds(Calendar.CivilTime{year, month, day, hour, minute, Bool.pick(U32, leap, 59, second), 0}))

def resolvedYear(+date: Syntax.DateFields, result: Result<&2, &2, Year.Error, U32>) -> Result<&2, &2, Error, Instant>:
  match date result:
    case _ Fail{cause}: Fail{YearFailure{cause}}
    case Syntax.DateFields{_, _, _, _, _, Syntax.ClockFields{hour, minute, +second}} Done{year}:
      +leap = U32.is_eq(second, 60)
      clock(Bool.not(leap) || (U32.is_eq(hour, 23) && U32.is_eq(minute, 59)), year, date, leap)

def interpret(reference: Calendar.CivilTime, +date: Syntax.DateFields) -> Result<&2, &2, Error, Instant>:
  resolvedYear(date, Year.resolve(reference, date))

def parsed(reference: Calendar.CivilTime, fields: Maybe<&2, Syntax.DateFields>) -> Result<&2, &2, Error, Instant>:
  match fields:
    case None{}: Fail{InvalidSyntax{}}
    case Some{date}: interpret(reference, date)

def parseAt(reference: Calendar.CivilTime, text: String) -> Result<&2, &2, Error, Instant>:
  parsed(reference, Syntax.parse(text))

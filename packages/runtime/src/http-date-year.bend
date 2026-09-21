import Base
import ./calendar.bend as Calendar
import ./http-date-syntax.bend as Syntax
import ./u64.bend as W

# RFC 9110's obsolete two-digit year is relative to the current UTC date.
# Calendar/weekday validation of the resolved input belongs to the interpreter.
type Error is Data:
  InvalidShortYear{}
  InvalidReference{cause: Calendar.CalendarError}
  OutsideCalendar{}

def bounded(+year: U32) -> Result<&2, &2, Error, U32>:
  Bool.pick(Result<&2, &2, Error, U32>, U32.is_le(year, 9999), Done{year}, Fail{OutsideCalendar{}})

def afterField(+left: U32, +right: U32, suffix: Bool) -> Bool:
  U32.is_gt(left, right) || (U32.is_eq(left, right) && suffix)

# Compare the anniversary's remaining fields rather than treating a year as
# a fixed number of days. The parsed date has whole-second precision.
def laterInYear(date: Syntax.DateFields, reference: Calendar.CivilTime) -> Bool:
  match date reference:
    case Syntax.DateFields{_, _, _, month, day, Syntax.ClockFields{hour, minute, second}} Calendar.CivilTime{_, rmonth, rday, rhour, rminute, rsecond, _}:
      afterField(month, rmonth, afterField(day, rday, afterField(hour, rhour, afterField(minute, rminute, U32.is_gt(second, rsecond)))))

def previous(+candidate: U32, valid: Bool) -> Result<&2, &2, Error, U32>:
  match valid:
    case False{}: Fail{OutsideCalendar{}}
    case True{}: bounded((candidate - 100 : U32))

def select(+candidate: U32, rollback: Bool) -> Result<&2, &2, Error, U32>:
  match rollback:
    case False{}: bounded(candidate)
    case True{}: previous(candidate, U32.is_ge(candidate, 100))

def candidate(+upper: U32, +year: U32, later: Bool) -> Result<&2, &2, Error, U32>:
  +value = ((upper / 100) * 100 + year : U32)
  select(value, afterField(value, upper, later))

def window(reference: Calendar.CivilTime, +date: Syntax.DateFields) -> Result<&2, &2, Error, U32>:
  match reference date:
    case Calendar.CivilTime{+year, month, day, hour, minute, second, millis} Syntax.DateFields{_, _, shortYear, _, _, _}:
      candidate((year + 50 : U32), shortYear, laterInYear(date, Calendar.CivilTime{year, month, day, hour, minute, second, millis}))

def checkedReference(reference: Calendar.CivilTime, date: Syntax.DateFields, valid: Result<&2, &2, Calendar.CalendarError, W.U64>) -> Result<&2, &2, Error, U32>:
  match valid:
    case Fail{cause}: Fail{InvalidReference{cause}}
    case Done{_}: window(reference, date)

def shortYear(+reference: Calendar.CivilTime, date: Syntax.DateFields, valid: Bool) -> Result<&2, &2, Error, U32>:
  match valid:
    case False{}: Fail{InvalidShortYear{}}
    case True{}: checkedReference(reference, date, Calendar.toEpochMilliseconds(reference))

def resolve(reference: Calendar.CivilTime, +date: Syntax.DateFields) -> Result<&2, &2, Error, U32>:
  match date:
    case Syntax.DateFields{Syntax.Rfc850{}, _, year, _, _, _}: shortYear(reference, date, U32.is_lt(year, 100))
    case Syntax.DateFields{_, _, year, _, _, _}: bounded(year)

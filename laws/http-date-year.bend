import Base
import ../packages/runtime/src/http-message.bend as Year
import ../packages/runtime/src/http-message.bend as S
import ../packages/runtime/src/calendar.bend as C

# Literal years must not acquire the obsolete format's clock-dependent pivot.
def literalYear(+year: U32) -> Result<&2, &2, Year.DateYearError, U32>:
  Bool.pick(Result<&2, &2, Year.DateYearError, U32>, U32.is_le(year, 9999), Done{year}, Fail{Year.OutsideCalendar{}})

law imf_year_is_literal:
  for reference: C.CivilTime
  for weekday: U32
  for +year: U32
  for month: U32
  for day: U32
  for clock: S.ClockFields
  {Year.resolve(reference, S.DateFields{S.ImfFixdate{}, weekday, year, month, day, clock}) == literalYear(year) : Result<&2, &2, Year.DateYearError, U32>}

law asctime_year_is_literal:
  for reference: C.CivilTime
  for weekday: U32
  for +year: U32
  for month: U32
  for day: U32
  for clock: S.ClockFields
  {Year.resolve(reference, S.DateFields{S.Asctime{}, weekday, year, month, day, clock}) == literalYear(year) : Result<&2, &2, Year.DateYearError, U32>}

# A weekday is checked against the resolved date later; it must never cause
# the year resolver to search for a different century that happens to match.
law weekday_does_not_choose_century:
  for +reference: C.CivilTime
  for +format: S.Format
  for first: U32
  for second: U32
  for +year: U32
  for +month: U32
  for +day: U32
  for +clock: S.ClockFields
  {Year.resolve(reference, S.DateFields{format, first, year, month, day, clock}) == Year.resolve(reference, S.DateFields{format, second, year, month, day, clock}) : Result<&2, &2, Year.DateYearError, U32>}

law invalid_reference_preserves_cause:
  for reference: C.CivilTime
  for date: S.DateFields
  for +cause: C.CalendarError
  {Year.checkedReference(reference, date, Fail{cause}) == Fail{Year.InvalidReference{cause}} : Result<&2, &2, Year.DateYearError, U32>}

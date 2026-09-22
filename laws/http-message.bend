import Base
import ../packages/runtime/src/http-message.bend as Year
import ../packages/runtime/src/http-message.bend as S
import ../packages/runtime/src/calendar.bend as C
import ../packages/runtime/src/http-message.bend as H
import ../packages/runtime/src/http-message.bend as Y
import ../packages/runtime/src/u64.bend as W
import ../packages/runtime/src/http-message.bend as Plan
import ../packages/runtime/src/http-message.bend as URL
import ../packages/runtime/src/url.bend as Host

# Http date year

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


# Http date

law ordinary_unix_conversion_is_exact:
  for +milliseconds: W.U64
  {H.unixMilliseconds(H.Ordinary{milliseconds}) == Done{milliseconds} : Result<&2, &2, H.UnixError, W.U64>}

law leap_seconds_never_silently_become_unix_timestamps:
  for milliseconds: W.U64
  {H.unixMilliseconds(H.LeapSecond{milliseconds}) == Fail{H.LeapSecondNotRepresentable{}} : Result<&2, &2, H.UnixError, W.U64>}

law calendar_failure_preserves_cause:
  for year: U32
  for month: U32
  for day: U32
  for claimed: U32
  for leap: Bool
  for +cause: C.CalendarError
  {H.checkedCalendar(year, month, day, claimed, leap, Fail{cause}) == Fail{H.CalendarFailure{cause}} : Result<&2, &2, H.Error, H.Instant>}

law mismatched_weekday_never_produces_an_instant:
  for leap: Bool
  for milliseconds: W.U64
  {H.checkedWeekday(False{}, leap, milliseconds) == Fail{H.WeekdayMismatch{}} : Result<&2, &2, H.Error, H.Instant>}

law year_failure_preserves_cause:
  for date: S.DateFields
  for +cause: Y.DateYearError
  {H.resolvedYear(date, Fail{cause}) == Fail{H.YearFailure{cause}} : Result<&2, &2, H.Error, H.Instant>}


# Http exchange plan

law tls_cannot_start_cleartext:
  for -R: Data
  for host: Host.Host
  for port: U32
  for authority: String
  for target: String
  for request: R
  for maximum: U32
  {Plan.prepareExchangePlan(R, URL.Endpoint{URL.TLS{}, host, port, authority, target}, request, maximum) == Plan.Rejected{Plan.TLSRequired{}} : Plan.Plan<R>}

law zero_read_size_cannot_start:
  for -R: Data
  for host: Host.Host
  for port: U32
  for authority: String
  for target: String
  for request: R
  {Plan.prepareExchangePlan(R, URL.Endpoint{URL.Plaintext{}, host, port, authority, target}, request, 0) == Plan.Rejected{Plan.InvalidReadSize{}} : Plan.Plan<R>}

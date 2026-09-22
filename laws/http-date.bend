import Base
import ../packages/runtime/src/http-message.bend as H
import ../packages/runtime/src/http-message.bend as Y
import ../packages/runtime/src/http-message.bend as S
import ../packages/runtime/src/calendar.bend as C
import ../packages/runtime/src/u64.bend as W

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

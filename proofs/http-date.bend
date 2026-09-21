import Base
import ../laws/http-date.bend as Laws
import ../packages/runtime/src/http-date-syntax.bend as S

def Laws.ordinary_unix_conversion_is_exact(milliseconds): {==}
def Laws.leap_seconds_never_silently_become_unix_timestamps(milliseconds): {==}
def Laws.calendar_failure_preserves_cause(year, month, day, claimed, leap, cause): {==}
def Laws.mismatched_weekday_never_produces_an_instant(leap, milliseconds): {==}
def Laws.year_failure_preserves_cause(date, cause):
  match date:
    case S.DateFields{_, _, _, _, _, S.ClockFields{_, _, _}}: {==}

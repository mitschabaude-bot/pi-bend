import Base
import ../laws/http-message.bend as Laws
import ../packages/runtime/src/http-message.bend as S
import ../packages/runtime/src/http-message.bend as Y
import ../packages/runtime/src/calendar.bend as C
import ../packages/runtime/src/u64.bend as W

# Http date year

law window_weekday:
  for +reference: C.CivilTime
  for a: U32
  for b: U32
  for +year: U32
  for +month: U32
  for +day: U32
  for +clock: S.ClockFields
  {Y.window(reference, S.DateFields{S.Rfc850{}, a, year, month, day, clock}) == Y.window(reference, S.DateFields{S.Rfc850{}, b, year, month, day, clock}) : Result<&2, &2, Y.DateYearError, U32>}

def window_weekday(reference, a, b, year, month, day, clock):
  match reference clock:
    case C.CivilTime{_, _, _, _, _, _, _} S.ClockFields{_, _, _}: {==}

law checked_weekday:
  for +reference: C.CivilTime
  for a: U32
  for b: U32
  for +year: U32
  for +month: U32
  for +day: U32
  for +clock: S.ClockFields
  for +valid: Result<&2, &2, C.CalendarError, W.U64>
  {Y.checkedReference(reference, S.DateFields{S.Rfc850{}, a, year, month, day, clock}, valid) == Y.checkedReference(reference, S.DateFields{S.Rfc850{}, b, year, month, day, clock}, valid) : Result<&2, &2, Y.DateYearError, U32>}

def checked_weekday(reference, a, b, year, month, day, clock, valid):
  match valid:
    case Fail{_}: {==}
    case Done{_}: window_weekday(reference, a, b, year, month, day, clock)

law short_weekday:
  for +reference: C.CivilTime
  for a: U32
  for b: U32
  for +year: U32
  for +month: U32
  for +day: U32
  for +clock: S.ClockFields
  for +valid: Bool
  {Y.shortYearDateYear(reference, S.DateFields{S.Rfc850{}, a, year, month, day, clock}, valid) == Y.shortYearDateYear(reference, S.DateFields{S.Rfc850{}, b, year, month, day, clock}, valid) : Result<&2, &2, Y.DateYearError, U32>}

def short_weekday(reference, a, b, year, month, day, clock, valid):
  match valid:
    case False{}: {==}
    case True{}: checked_weekday(reference, a, b, year, month, day, clock, C.toEpochMilliseconds(reference))

def Laws.imf_year_is_literal(reference, weekday, year, month, day, clock): {==}
def Laws.asctime_year_is_literal(reference, weekday, year, month, day, clock): {==}
def Laws.weekday_does_not_choose_century(reference, format, first, second, year, month, day, clock):
  match format:
    case S.ImfFixdate{}: {==}
    case S.Rfc850{}: short_weekday(reference, first, second, year, month, day, clock, U32.is_lt(year, 100))
    case S.Asctime{}: {==}
def Laws.invalid_reference_preserves_cause(reference, date, cause): {==}


# Http date

def Laws.ordinary_unix_conversion_is_exact(milliseconds): {==}
def Laws.leap_seconds_never_silently_become_unix_timestamps(milliseconds): {==}
def Laws.calendar_failure_preserves_cause(year, month, day, claimed, leap, cause): {==}
def Laws.mismatched_weekday_never_produces_an_instant(leap, milliseconds): {==}
def Laws.year_failure_preserves_cause(date, cause):
  match date:
    case S.DateFields{_, _, _, _, _, S.ClockFields{_, _, _}}: {==}


# Http exchange plan

def Laws.tls_cannot_start_cleartext(R, host, port, authority, target, request, maximum): {==}
def Laws.zero_read_size_cannot_start(R, host, port, authority, target, request): {==}

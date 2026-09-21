import Base
import ../laws/http-date-year.bend as Laws
import ../packages/runtime/src/http-date-syntax.bend as S
import ../packages/runtime/src/http-date-year.bend as Y
import ../packages/runtime/src/calendar.bend as C
import ../packages/runtime/src/u64.bend as W

law window_weekday:
  for +reference: C.CivilTime
  for a: U32
  for b: U32
  for +year: U32
  for +month: U32
  for +day: U32
  for +clock: S.ClockFields
  {Y.window(reference, S.DateFields{S.Rfc850{}, a, year, month, day, clock}) == Y.window(reference, S.DateFields{S.Rfc850{}, b, year, month, day, clock}) : Result<&2, &2, Y.Error, U32>}

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
  {Y.checkedReference(reference, S.DateFields{S.Rfc850{}, a, year, month, day, clock}, valid) == Y.checkedReference(reference, S.DateFields{S.Rfc850{}, b, year, month, day, clock}, valid) : Result<&2, &2, Y.Error, U32>}

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
  {Y.shortYear(reference, S.DateFields{S.Rfc850{}, a, year, month, day, clock}, valid) == Y.shortYear(reference, S.DateFields{S.Rfc850{}, b, year, month, day, clock}, valid) : Result<&2, &2, Y.Error, U32>}

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

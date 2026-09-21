import Base
import ../../../runtime/src/http-date.bend as HTTP
import ../../../runtime/src/calendar-inverse.bend as Inverse
import ../../../runtime/src/calendar.bend as Calendar
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/u64.bend as W
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/callback.bend as C

# The provider's numeric retry API uses NaN for an unusable date hint. Keep
# strict parsing and unrepresentable leap seconds explicit below this boundary.
def unix(result: Result<&2, &2, HTTP.UnixError, W.U64>) -> F.F64:
  match result:
    case Fail{_}: F.nan()
    case Done{milliseconds}: Date.fromMilliseconds(milliseconds)

def interpreted(result: Result<&2, &2, HTTP.Error, HTTP.Instant>) -> F.F64:
  match result:
    case Fail{_}: F.nan()
    case Done{instant}: unix(HTTP.unixMilliseconds(instant))

def reference(text: String, result: Result<&2, &2, Inverse.Error, Calendar.CivilTime>) -> F.F64:
  match result:
    case Fail{_}: F.nan()
    case Done{current}: interpreted(HTTP.parseAt(current, text))

def at(epoch: W.U64, text: String) -> F.F64:
  reference(text, Inverse.fromEpochMilliseconds(epoch))

def body(environment: Unit, text: String) -> IO(F.F64):
  do IO<F.F64>:
    epoch : U32 & U32 <- IO.unixMilliseconds()
    return at(Date.words(epoch), text)

# The caller owns this callback and must retire it after all retry users.
def create() -> IO(C.Callback<String, F.F64>):
  C.create(~Unit, ~String, ~F.F64, ~body, Unit{})

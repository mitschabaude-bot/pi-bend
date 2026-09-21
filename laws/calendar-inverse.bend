import Base
import ../packages/runtime/src/calendar-inverse.bend as I
import ../packages/runtime/src/calendar.bend as C
import ../packages/runtime/src/u64.bend as W

# Failed conversions make no date claim. Every successful conversion must be
# valid in the forward calendar and reproduce the exact original signed bits.
def encodedSame(epoch: W.U64, encoded: Result<&2, &2, C.CalendarError, W.U64>) -> Bool:
  match encoded:
    case Fail{_}: False{}
    case Done{value}: W.equal(epoch, value)

def reconstructs(epoch: W.U64, result: Result<&2, &2, I.Error, C.CivilTime>) -> Bool:
  match result:
    case Fail{_}: True{}
    case Done{value}: encodedSame(epoch, C.toEpochMilliseconds(value))

law successful_inverse_reconstructs_original_epoch:
  for +epoch: W.U64
  {reconstructs(epoch, I.fromEpochMilliseconds(epoch)) == True{} : Bool}

import Base
import ../laws/calendar-inverse.bend as Laws
import ../packages/runtime/src/calendar-inverse.bend as I
import ../packages/runtime/src/calendar.bend as C
import ../packages/runtime/src/u64.bend as W

law verified_result:
  for +epoch: W.U64
  for +value: C.CivilTime
  for +valid: Bool
  for equality: {Laws.encodedSame(epoch, C.toEpochMilliseconds(value)) == valid : Bool}
  {Laws.reconstructs(epoch, I.verified(value, valid)) == True{} : Bool}

def verified_result(epoch, value, valid, equality):
  match valid:
    case False{}: {==}
    case True{}: equality

law same_projection:
  for epoch: W.U64
  for encoded: Result<&2, &2, C.CalendarError, W.U64>
  {Laws.encodedSame(epoch, encoded) == I.same(epoch, encoded) : Bool}

def same_projection(epoch, encoded):
  match encoded:
    case Fail{_}: {==}
    case Done{_}: {==}

law checked_result:
  for +epoch: W.U64
  for +value: C.CivilTime
  {Laws.reconstructs(epoch, I.checked(epoch, value)) == True{} : Bool}

def checked_result(epoch, value):
  verified_result(epoch, value, I.same(epoch, C.toEpochMilliseconds(value)), same_projection(epoch, C.toEpochMilliseconds(value)))

law validated_result:
  for +epoch: W.U64
  for +result: Result<&2, &2, I.Error, C.CivilTime>
  {Laws.reconstructs(epoch, I.validate(epoch, result)) == True{} : Bool}

def validated_result(epoch, result):
  match result:
    case Fail{_}: {==}
    case Done{value}: checked_result(epoch, value)

def Laws.successful_inverse_reconstructs_original_epoch(epoch):
  +shifted = W.add(epoch, I.epochOffset())
  validated_result(epoch, I.ranged(epoch, shifted, W.compare(shifted, I.extent())))

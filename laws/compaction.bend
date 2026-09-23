import Base
import ../packages/coding-agent/src/core/compaction/plan.bend as C

# The automatic-compaction decision, characterized over every combination of
# its facts. Together the laws fix the plan: a skipped check never compacts,
# a compact-and-retry happens exactly for the first failed overflow (so
# recovery runs at most once until re-armed), recovery is reported exhausted
# exactly for a repeated failed overflow, and threshold compaction happens
# exactly when nothing overflowed and the context is past the threshold.

def plansRetry(plan: C.CompactionPlan) -> Bool:
  match plan:
    case C.OverflowCompaction{True{}}: True{}
    case _: False{}

def exhausted(plan: C.CompactionPlan) -> Bool:
  match plan:
    case C.RecoveryExhausted{_}: True{}
    case _: False{}

def thresholdPlanned(plan: C.CompactionPlan) -> Bool:
  match plan:
    case C.ThresholdCompaction{}: True{}
    case _: False{}

law skipped_check_never_compacts:
  for contextOverflow: Bool
  for recoverableLength: Bool
  for completed: Bool
  for attempted: Bool
  for overThreshold: Bool
  {C.decideCompaction(True{}, contextOverflow, recoverableLength, completed, attempted, overThreshold) == C.NoCompaction{} : C.CompactionPlan}

law retry_exactly_for_first_failed_overflow:
  for skipped: Bool
  for contextOverflow: Bool
  for recoverableLength: Bool
  for completed: Bool
  for attempted: Bool
  for overThreshold: Bool
  {plansRetry(C.decideCompaction(skipped, contextOverflow, recoverableLength, completed, attempted, overThreshold)) == Bool.and(Bool.not(skipped), Bool.and(Bool.or(contextOverflow, recoverableLength), Bool.and(Bool.not(completed), Bool.not(attempted)))) : Bool}

law exhausted_exactly_for_repeated_failed_overflow:
  for skipped: Bool
  for contextOverflow: Bool
  for recoverableLength: Bool
  for completed: Bool
  for attempted: Bool
  for overThreshold: Bool
  {exhausted(C.decideCompaction(skipped, contextOverflow, recoverableLength, completed, attempted, overThreshold)) == Bool.and(Bool.not(skipped), Bool.and(Bool.or(contextOverflow, recoverableLength), Bool.and(Bool.not(completed), attempted))) : Bool}

law threshold_exactly_without_overflow:
  for skipped: Bool
  for contextOverflow: Bool
  for recoverableLength: Bool
  for completed: Bool
  for attempted: Bool
  for overThreshold: Bool
  {thresholdPlanned(C.decideCompaction(skipped, contextOverflow, recoverableLength, completed, attempted, overThreshold)) == Bool.and(Bool.not(skipped), Bool.and(Bool.not(Bool.or(contextOverflow, recoverableLength)), overThreshold)) : Bool}

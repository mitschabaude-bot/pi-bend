import Base

# The automatic-compaction decision
# ---------------------------------
# upstream AgentSession._checkCompaction decides from these facts, in order:
# a skipped check never compacts; a context overflow or recoverable length
# stop compacts, and retries the turn once when the response did not
# complete; otherwise the context compacts past the threshold.

type CompactionPlan is Data:
  NoCompaction{}
  RecoveryExhausted{errorMessage: String}
  OverflowCompaction{willRetry: Bool}
  ThresholdCompaction{}

def recoveryMessage(contextOverflow: Bool) -> String:
  match contextOverflow:
    case True{}: "Context overflow recovery failed after one compact-and-retry attempt. Try reducing context or switching to a larger-context model."
    case False{}: "Truncated response recovery failed after one compact-and-retry attempt."

def overflowPlan(completed: Bool, attempted: Bool, contextOverflow: Bool) -> CompactionPlan:
  match completed attempted:
    case True{} _: OverflowCompaction{False{}}
    case False{} True{}: RecoveryExhausted{recoveryMessage(contextOverflow)}
    case False{} False{}: OverflowCompaction{True{}}

def triggeredPlan(overflow: Bool, contextOverflow: Bool, completed: Bool, attempted: Bool, overThreshold: Bool) -> CompactionPlan:
  match overflow:
    case True{}: overflowPlan(completed, attempted, contextOverflow)
    case False{}: Bool.pick(CompactionPlan, overThreshold, ThresholdCompaction{}, NoCompaction{})

def decideCompaction(skipped: Bool, +contextOverflow: Bool, recoverableLength: Bool, completed: Bool, attempted: Bool, overThreshold: Bool) -> CompactionPlan:
  match skipped:
    case True{}: NoCompaction{}
    case False{}: triggeredPlan(Bool.or(contextOverflow, recoverableLength), contextOverflow, completed, attempted, overThreshold)

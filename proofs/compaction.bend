import Base
import ../laws/compaction.bend as Laws
import ../packages/coding-agent/src/core/compaction/plan.bend as C

def Laws.skipped_check_never_compacts(contextOverflow, recoverableLength, completed, attempted, overThreshold): {==}

# Each plan predicate is decided by the overflow facts, then by completion
# and the recovery flag, or by the threshold.
def Laws.retry_exactly_for_first_failed_overflow(skipped, contextOverflow, recoverableLength, completed, attempted, overThreshold):
  match skipped contextOverflow recoverableLength completed attempted overThreshold:
    case True{} _ _ _ _ _: {==}
    case False{} True{} _ True{} _ _: {==}
    case False{} True{} _ False{} True{} _: {==}
    case False{} True{} _ False{} False{} _: {==}
    case False{} False{} True{} True{} _ _: {==}
    case False{} False{} True{} False{} True{} _: {==}
    case False{} False{} True{} False{} False{} _: {==}
    case False{} False{} False{} _ _ True{}: {==}
    case False{} False{} False{} _ _ False{}: {==}

def Laws.exhausted_exactly_for_repeated_failed_overflow(skipped, contextOverflow, recoverableLength, completed, attempted, overThreshold):
  match skipped contextOverflow recoverableLength completed attempted overThreshold:
    case True{} _ _ _ _ _: {==}
    case False{} True{} _ True{} _ _: {==}
    case False{} True{} _ False{} True{} _: {==}
    case False{} True{} _ False{} False{} _: {==}
    case False{} False{} True{} True{} _ _: {==}
    case False{} False{} True{} False{} True{} _: {==}
    case False{} False{} True{} False{} False{} _: {==}
    case False{} False{} False{} _ _ True{}: {==}
    case False{} False{} False{} _ _ False{}: {==}

def Laws.threshold_exactly_without_overflow(skipped, contextOverflow, recoverableLength, completed, attempted, overThreshold):
  match skipped contextOverflow recoverableLength completed attempted overThreshold:
    case True{} _ _ _ _ _: {==}
    case False{} True{} _ True{} _ _: {==}
    case False{} True{} _ False{} True{} _: {==}
    case False{} True{} _ False{} False{} _: {==}
    case False{} False{} True{} True{} _ _: {==}
    case False{} False{} True{} False{} True{} _: {==}
    case False{} False{} True{} False{} False{} _: {==}
    case False{} False{} False{} _ _ True{}: {==}
    case False{} False{} False{} _ _ False{}: {==}

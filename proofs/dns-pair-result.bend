import Base
import ../laws/dns-pair-result.bend as Laws
import ../packages/runtime/src/dns-pair-result.bend as Pair

def Laws.left_terminal_retains_both(Report, priority, left, right, other):
  match priority:
    case Pair.IPv4First{}:
      match other:
        case Pair.Answer{}: {==}
        case Pair.Reply{code}: {==}
        case Pair.Unavailable{cause}: {==}
        case Pair.Terminal{}: {==}
    case Pair.IPv6First{}:
      match other:
        case Pair.Answer{}: {==}
        case Pair.Reply{code}: {==}
        case Pair.Unavailable{cause}: {==}
        case Pair.Terminal{}: {==}

def Laws.right_terminal_retains_both(Report, priority, left, right, other):
  match priority:
    case Pair.IPv4First{}:
      match other:
        case Pair.Answer{}: {==}
        case Pair.Reply{code}: {==}
        case Pair.Unavailable{cause}: {==}
        case Pair.Terminal{}: {==}
    case Pair.IPv6First{}:
      match other:
        case Pair.Answer{}: {==}
        case Pair.Reply{code}: {==}
        case Pair.Unavailable{cause}: {==}
        case Pair.Terminal{}: {==}

def Laws.answer_and_reply_retained(Report, priority, left, right, code):
  match priority:
    case Pair.IPv4First{}: {==}
    case Pair.IPv6First{}: {==}
def Laws.unavailable_and_answer_retained(Report, priority, left, right, cause):
  match priority:
    case Pair.IPv4First{}: {==}
    case Pair.IPv6First{}: {==}
def Laws.empty_reply_defers_to_other_code(code): {==}
def Laws.unavailable_does_not_override_reply(code, cause): {==}
def Laws.same_failure_is_stable(cause): {==}

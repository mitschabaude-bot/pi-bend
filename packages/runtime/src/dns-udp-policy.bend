import Base
import ./dns-message.bend as Message

# This policy runs only after transaction matching. A retryable RCODE takes
# precedence over truncation. Extended EDNS status is a separate obligation.
type Status is Data:
  Success{}
  FailureCode{}
  NotImplementedCode{}
  RefusedCode{}
  Other{code: U32}

type Rejection is Data:
  ServerFailure{}
  NotImplemented{}
  Refused{}
  UnhelpfulEmpty{}

type Decision is Data:
  Accept{}
  UseTCP{}
  Retry{reason: Rejection}

def status(code: U32) -> Status:
  match code:
    case 0: Success{}
    case 2: FailureCode{}
    case 4: NotImplementedCode{}
    case 5: RefusedCode{}
    case other: Other{other}

def transport(truncated: Bool, ignoreTruncation: Bool) -> Decision:
  match truncated ignoreTruncation:
    case True{} False{}: UseTCP{}
    case _ _: Accept{}

def success(unhelpful: Bool, truncated: Bool, ignoreTruncation: Bool) -> Decision:
  match unhelpful:
    case True{}: Retry{UnhelpfulEmpty{}}
    case False{}: transport(truncated, ignoreTruncation)

def decide(status: Status, unhelpful: Bool, truncated: Bool, ignoreTruncation: Bool) -> Decision:
  match status:
    case FailureCode{}: Retry{ServerFailure{}}
    case NotImplementedCode{}: Retry{NotImplemented{}}
    case RefusedCode{}: Retry{Refused{}}
    case Success{}: success(unhelpful, truncated, ignoreTruncation)
    case Other{_}: transport(truncated, ignoreTruncation)

# Authority records do not enter the reference's empty-reply decision. AA,
# RA, answer count and additional count do. Keep that distinction explicit.
def header(value: Message.Header, ignoreTruncation: Bool) -> Decision:
  match value:
    case Message.Header{_, +flags, _, answers, _, additional}:
      decide(status(U32.and(flags, 15)), U32.is_eq(answers, 0) && U32.is_eq(U32.and(flags, 1152), 0) && U32.is_eq(additional, 0), U32.is_ne(U32.and(flags, 512), 0), ignoreTruncation)

import Base
import ./dns-message.bend as Message
import ./dns-edns-response.bend as Edns

# This policy runs only after transaction matching. A retryable RCODE takes
# precedence over truncation. Complete messages use validated EDNS status.
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
def headerCode(code: U32, value: Message.Header, ignoreTruncation: Bool) -> Decision:
  match value:
    case Message.Header{_, +flags, _, answers, _, additional}:
      decide(status(code), U32.is_eq(answers, 0) && U32.is_eq(U32.and(flags, 1152), 0) && U32.is_eq(additional, 0), U32.is_ne(U32.and(flags, 512), 0), ignoreTruncation)

# Only a validated truncated header is available on the incomplete-message
# path. Complete responses instead enter message() to validate the OPT record.
def header(+value: Message.Header, ignoreTruncation: Bool) -> Decision:
  headerCode(Edns.responseCode(value, None{}), value, ignoreTruncation)

def inspected(+fields: Message.Header, ignoreTruncation: Bool, extension: Result<&2, &2, Edns.Error, Maybe<&2, Edns.Response>>) -> Result<&2, &2, Edns.Error, Decision>:
  match extension:
    case Fail{error}: Fail{error}
    case Done{value}: Done{headerCode(Edns.responseCode(fields, value), fields, ignoreTruncation)}

def messageHeader(value: Message.Message) -> Message.Header:
  match value:
    case Message.Message{_, fields, _, _, _, _}: fields

def message(+value: Message.Message, ignoreTruncation: Bool) -> Result<&2, &2, Edns.Error, Decision>:
  inspected(messageHeader(value), ignoreTruncation, Edns.inspect(value))

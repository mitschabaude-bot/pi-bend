import Base
import ./dns-search-response.bend as Response
import ./dns-search-run.bend as Run

# Keep a complete report beside its classification. A protocol response is
# distinct from absence of a response; code zero means a valid empty answer.
type Disposition is Data:
  Answer{}
  Reply{code: U32}
  Unavailable{cause: Response.Cause}
  Terminal{}

type Classified<-Report: Data> is Data:
  Classified{report: Report, disposition: Disposition}

type Reports<-Report: Data> is Data:
  Reports{ipv4: Classified<Report>, ipv6: Classified<Report>}

# The caller chooses precedence explicitly; receipt-order compatibility and
# deterministic family ordering can both use the same pure merge kernel.
type Priority is Data:
  IPv4First{}
  IPv6First{}

type Decision is Data:
  Accepted{}
  Failed{cause: Response.Cause}
  Stopped{}

def response(code: U32) -> Response.Cause:
  match code:
    case 0: Response.EmptyAnswer{}
    case 2: Response.ServerFailure{}
    case 3: Response.Missing{}
    case _: Response.Unrecoverable{}

# With two negative DNS replies, prefer the first error unless it is NOERROR.
# A real reply also takes precedence over an unavailable sibling response.
def replies(+ipv4: U32, ipv6: U32) -> Response.Cause:
  response(Bool.pick(U32, U32.is_eq(ipv4, 0), ipv6, ipv4))

# Malformed data, cancellation, entropy and cleanup failures are terminal.
# A usable address can coexist with an ordinary DNS or network failure.
def decide(ipv4: Disposition, ipv6: Disposition) -> Decision:
  match ipv4 ipv6:
    case Terminal{} _: Stopped{}
    case _ Terminal{}: Stopped{}
    case Answer{} _: Accepted{}
    case _ Answer{}: Accepted{}
    case Reply{a} Reply{b}: Failed{replies(a, b)}
    case Reply{code} Unavailable{_}: Failed{response(code)}
    case Unavailable{_} Reply{code}: Failed{response(code)}
    case Unavailable{cause} Unavailable{_}: Failed{cause}

def prioritized(priority: Priority, ipv4: Disposition, ipv6: Disposition) -> Decision:
  match priority:
    case IPv4First{}: decide(ipv4, ipv6)
    case IPv6First{}: decide(ipv6, ipv4)

def deliver(-Report: Data, reports: Reports<Report>, decision: Decision) -> Run.Outcome<Reports<Report>, Reports<Report>>:
  match decision:
    case Accepted{}: Run.Answer{reports}
    case Failed{cause}: Run.Failed{cause}
    case Stopped{}: Run.Halt{reports}

# Successful and terminal outcomes retain both reports, in family order.
def merge(-Report: Data, priority: Priority, ipv4: Classified<Report>, ipv6: Classified<Report>) -> Run.Outcome<Reports<Report>, Reports<Report>>:
  match ipv4 ipv6:
    case Classified{a, +da} Classified{b, +db}: deliver(Report, Reports{Classified{a, da}, Classified{b, db}}, prioritized(priority, da, db))

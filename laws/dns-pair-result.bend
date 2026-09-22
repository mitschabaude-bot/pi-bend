import Base
import ../packages/runtime/src/dns-resolver.bend as Pair
import ../packages/runtime/src/dns-message.bend as Run
import ../packages/runtime/src/dns-message.bend as Response

law left_terminal_retains_both:
  for -Report: Data
  for +priority: Pair.Priority
  for +left: Report
  for +right: Report
  for +other: Pair.Disposition
  {Pair.merge(Report, priority, Pair.Classified{left, Pair.Terminal{}}, Pair.Classified{right, other}) == Run.SearchHalt{Pair.PairResultReports{Pair.Classified{left, Pair.Terminal{}}, Pair.Classified{right, other}}} : Run.Outcome<Pair.PairResultReports<Report>, Pair.PairResultReports<Report>>}

law right_terminal_retains_both:
  for -Report: Data
  for +priority: Pair.Priority
  for +left: Report
  for +right: Report
  for +other: Pair.Disposition
  {Pair.merge(Report, priority, Pair.Classified{left, other}, Pair.Classified{right, Pair.Terminal{}}) == Run.SearchHalt{Pair.PairResultReports{Pair.Classified{left, other}, Pair.Classified{right, Pair.Terminal{}}}} : Run.Outcome<Pair.PairResultReports<Report>, Pair.PairResultReports<Report>>}

law answer_and_reply_retained:
  for -Report: Data
  for +priority: Pair.Priority
  for +left: Report
  for +right: Report
  for +code: U32
  {Pair.merge(Report, priority, Pair.Classified{left, Pair.Answer{}}, Pair.Classified{right, Pair.Reply{code}}) == Run.Answer{Pair.PairResultReports{Pair.Classified{left, Pair.Answer{}}, Pair.Classified{right, Pair.Reply{code}}}} : Run.Outcome<Pair.PairResultReports<Report>, Pair.PairResultReports<Report>>}

law unavailable_and_answer_retained:
  for -Report: Data
  for +priority: Pair.Priority
  for +left: Report
  for +right: Report
  for +cause: Response.Cause
  {Pair.merge(Report, priority, Pair.Classified{left, Pair.Unavailable{cause}}, Pair.Classified{right, Pair.Answer{}}) == Run.Answer{Pair.PairResultReports{Pair.Classified{left, Pair.Unavailable{cause}}, Pair.Classified{right, Pair.Answer{}}}} : Run.Outcome<Pair.PairResultReports<Report>, Pair.PairResultReports<Report>>}

law empty_reply_defers_to_other_code:
  for +code: U32
  {Pair.replies(0, code) == Pair.response(code) : Response.Cause}

law unavailable_does_not_override_reply:
  for +code: U32
  for cause: Response.Cause
  {Pair.decide(Pair.Unavailable{cause}, Pair.Reply{code}) == Pair.Failed{Pair.response(code)} : Pair.Decision}

law same_failure_is_stable:
  for +cause: Response.Cause
  {Pair.decide(Pair.Unavailable{cause}, Pair.Unavailable{cause}) == Pair.Failed{cause} : Pair.Decision}

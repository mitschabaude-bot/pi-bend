import Base
import ../packages/runtime/src/dns-pair-result.bend as Pair
import ../packages/runtime/src/dns-search-run.bend as Run
import ../packages/runtime/src/dns-search-response.bend as Response

law left_terminal_retains_both:
  for -Report: Data
  for +priority: Pair.Priority
  for +left: Report
  for +right: Report
  for +other: Pair.Disposition
  {Pair.merge(Report, priority, Pair.Classified{left, Pair.Terminal{}}, Pair.Classified{right, other}) == Run.Halt{Pair.Reports{Pair.Classified{left, Pair.Terminal{}}, Pair.Classified{right, other}}} : Run.Outcome<Pair.Reports<Report>, Pair.Reports<Report>>}

law right_terminal_retains_both:
  for -Report: Data
  for +priority: Pair.Priority
  for +left: Report
  for +right: Report
  for +other: Pair.Disposition
  {Pair.merge(Report, priority, Pair.Classified{left, other}, Pair.Classified{right, Pair.Terminal{}}) == Run.Halt{Pair.Reports{Pair.Classified{left, other}, Pair.Classified{right, Pair.Terminal{}}}} : Run.Outcome<Pair.Reports<Report>, Pair.Reports<Report>>}

law answer_and_reply_retained:
  for -Report: Data
  for +priority: Pair.Priority
  for +left: Report
  for +right: Report
  for +code: U32
  {Pair.merge(Report, priority, Pair.Classified{left, Pair.Answer{}}, Pair.Classified{right, Pair.Reply{code}}) == Run.Answer{Pair.Reports{Pair.Classified{left, Pair.Answer{}}, Pair.Classified{right, Pair.Reply{code}}}} : Run.Outcome<Pair.Reports<Report>, Pair.Reports<Report>>}

law unavailable_and_answer_retained:
  for -Report: Data
  for +priority: Pair.Priority
  for +left: Report
  for +right: Report
  for +cause: Response.Cause
  {Pair.merge(Report, priority, Pair.Classified{left, Pair.Unavailable{cause}}, Pair.Classified{right, Pair.Answer{}}) == Run.Answer{Pair.Reports{Pair.Classified{left, Pair.Unavailable{cause}}, Pair.Classified{right, Pair.Answer{}}}} : Run.Outcome<Pair.Reports<Report>, Pair.Reports<Report>>}

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

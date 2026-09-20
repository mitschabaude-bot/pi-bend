import Base
import ./dns-pair-result.bend as Pair
import ./dns-search-run.bend as Run
import ./dns-search-response.bend as Response
import ./dns-address-search.bend as Search
import ./dns-address-lookup.bend as Lookup
import ./dns-address-answer.bend as Answer
# Reuse the native classifier's abort/cleanup/OS-error checks first. Refine
# only its nonterminal failures using the original report, before discarding
# distinctions needed to merge A and AAAA responses.
# Exhausted UDP rejections stay unavailable, as the transport policy did not
# accept them as replies. Their RCODE/header remain in the original report.
def disposition(-Reason: Data, original: Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>, outcome: Run.Outcome<Lookup.Error<Reason>, Answer.Selection>) -> Pair.Disposition:
  match original outcome:
    case _ Run.Halt{_}: Pair.Terminal{}
    case _ Run.Answer{_}: Pair.Answer{}
    case Fail{Lookup.Selection{Answer.ResponseCode{code}}} Run.Failed{_}: Pair.Reply{code}
    case _ Run.Failed{Response.EmptyAnswer{}}: Pair.Reply{0}
    case _ Run.Failed{cause}: Pair.Unavailable{cause}

def classify(~Reason: Data, +original: Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>) -> IO(Pair.Classified<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>):
  do IO<Pair.Classified<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>>:
    outcome : Run.Outcome<Lookup.Error<Reason>, Answer.Selection> <- Search.completed(Reason, original)
    return Pair.Classified{original, disposition(Reason, original, outcome)}

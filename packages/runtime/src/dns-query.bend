import Base
import ./dns-message.bend as Message
import ./dns-edns.bend as Edns

# One immutable query intent, retained unchanged across transport retries.
# Absence of EDNS is explicit; transport never invents negotiation policy.
type Request is Data:
  Request{id: U32, flags: U32, question: Message.Question, extension: Maybe<&2, Edns.Query>}

def plain(id: U32, flags: U32, question: Message.Question) -> Request:
  Request{id, flags, question, None{}}

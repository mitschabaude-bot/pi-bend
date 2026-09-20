import Base
import ./dns-message.bend as Message
import ./dns-edns.bend as Edns

# One immutable query intent, retained unchanged across transport retries.
# Absence of EDNS is explicit; transport never invents negotiation policy.
type Request is Data:
  Request{id: U32, flags: U32, question: Message.Question, extension: Maybe<&2, Edns.Query>}

def plain(id: U32, flags: U32, question: Message.Question) -> Request:
  Request{id, flags, question, None{}}

# Settings shared by distinct questions in one lookup/search. IDs and question
# names are supplied separately, so alias follow-ups do not reuse either.
type Options is Data:
  Options{flags: U32, extension: Maybe<&2, Edns.Query>}

def defaults() -> Options: Options{256, None{}}

def create(options: Options, id: U32, question: Message.Question) -> Request:
  match options:
    case Options{flags, extension}: Request{id, flags, question, extension}

# Shared checked wire encoding for transport selection and transmission.
def encoded(value: Result<&2, &2, Message.Error, List<&2, U32>>) -> Result<&2, &2, Edns.Error, List<&2, U32>>:
  match value:
    case Fail{error}: Fail{Edns.Message{error}}
    case Done{bytes}: Done{bytes}

def encode(request: Request) -> Result<&2, &2, Edns.Error, List<&2, U32>>:
  match request:
    case Request{id, flags, question, None{}}: encoded(Message.query(id, flags, question))
    case Request{id, flags, question, Some{extension}}: Edns.query(id, flags, question, extension)

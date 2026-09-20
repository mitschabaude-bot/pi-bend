import Base
import ../packages/runtime/src/dns-query.bend as Query
import ../packages/runtime/src/dns-message.bend as Message

type Intent is Data:
  Intent{options: Query.Options, id: U32, question: Message.Question}

def intent(request: Query.Request) -> Intent:
  match request:
    case Query.Request{id, flags, question, extension}: Intent{Query.Options{flags, extension}, id, question}

# Constructing a new question retains every caller option, independently of ID
# and question contents. Validation and transmission are separate obligations.
law creation_preserves_intent:
  for +options: Query.Options
  for +id: U32
  for +question: Message.Question
  {intent(Query.create(options, id, question)) == Intent{options, id, question} : Intent}

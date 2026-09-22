import Base
import ../laws/dns-query.bend as Laws
import ../packages/runtime/src/dns-message.bend as Query

def Laws.creation_preserves_intent(options, id, question):
  match options:
    case Query.QueryOptions{_, _}: {==}

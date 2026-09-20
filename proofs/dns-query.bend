import Base
import ../laws/dns-query.bend as Laws
import ../packages/runtime/src/dns-query.bend as Query

def Laws.creation_preserves_intent(options, id, question):
  match options:
    case Query.Options{_, _}: {==}

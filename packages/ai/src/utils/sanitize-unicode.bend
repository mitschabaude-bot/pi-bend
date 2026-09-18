import Base
import ../../../runtime/src/utf16.bend as U

# Canonicalize valid pairs before removing unpaired surrogate units. Ordinary
# Unicode spelling, combining marks and supplementary characters are retained.
def removeUnpaired(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{+code}, rest}:
      +tail = removeUnpaired(rest)
      Bool.pick(String, U.highSurrogate(code) || U.lowSurrogate(code), tail, SCon{Chr{code}, tail})

def sanitizeSurrogates(text: String) -> String:
  removeUnpaired(U.normalize(text))

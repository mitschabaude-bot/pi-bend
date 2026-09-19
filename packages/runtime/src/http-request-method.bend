import Base
import ./http-header.bend as H

type MethodError is Data:
  InvalidMethod{}
  ForbiddenMethod{}

# Fetch normalizes six common methods, preserving other token spellings.
def normalized(lower: String, original: String) -> Result<&2, &2, MethodError, String>:
  match lower:
    case "connect": Fail{ForbiddenMethod{}}
    case "trace": Fail{ForbiddenMethod{}}
    case "track": Fail{ForbiddenMethod{}}
    case "delete": Done{"DELETE"}
    case "get": Done{"GET"}
    case "head": Done{"HEAD"}
    case "options": Done{"OPTIONS"}
    case "post": Done{"POST"}
    case "put": Done{"PUT"}
    case _: Done{original}

def checked(valid: Bool, +method: String) -> Result<&2, &2, MethodError, String>:
  match valid:
    case False{}: Fail{InvalidMethod{}}
    case True{}: normalized(H.lowercase(method), method)

def normalize(+method: String) -> Result<&2, &2, MethodError, String>:
  checked(H.validName(method), method)

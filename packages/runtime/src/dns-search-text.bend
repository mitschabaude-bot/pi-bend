import Base
import ./dns-presentation.bend as Presentation
import ./dns-name.bend as Name

# The search threshold counts presentation dots, including the terminal dot.
# Parsing first bounds the accepted input before conversion to the U32 API.
type Input is Data:
  Input{name: Name.Name, dots: U32, absolute: Bool}

def counted(dot: Bool, rest: Nat) -> Nat:
  match dot:
    case True{}: Succ{rest}
    case False{}: rest

def dots(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{Chr{code}, rest}: counted(U32.is_eq(code, 46), dots(rest))

def parsed(text: String, result: Result<&2, &2, Presentation.Error, Presentation.Parsed>) -> Result<&2, &2, Presentation.Error, Input>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Presentation.Parsed{name, absolute}}: Done{Input{name, U32.from_nat(dots(text)), absolute}}

def prepare(+text: String) -> Result<&2, &2, Presentation.Error, Input>:
  parsed(text, Presentation.parse(text))

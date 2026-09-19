import Base
import ./unicode-joining-type.bend as Joining

# RFC 5892 Appendix A.1/A.2. Only an immediate CCC=9 predecessor permits ZWJ.
# ZWNJ additionally permits L/D T* ZWNJ T* R/D joining context.
type State is Data:
  Active{beforeVirama: Bool, leftJoining: Bool, awaitingRight: Bool}
  Invalid{}

def start() -> State:
  Active{False{}, False{}, False{}}

def leftContext(value: Joining.JoiningType, previous: Bool) -> Bool:
  match value:
    case Joining.Transparent{}: previous
    case Joining.LeftJoining{}: True{}
    case Joining.DualJoining{}: True{}
    case _: False{}

def rightContext(value: Joining.JoiningType) -> Bool:
  match value:
    case Joining.RightJoining{}: True{}
    case Joining.DualJoining{}: True{}
    case _: False{}

def resolved(valid: Bool, beforeVirama: Bool, leftJoining: Bool) -> State:
  match valid:
    case True{}: Active{beforeVirama, leftJoining, False{}}
    case False{}: Invalid{}

def ordinary(value: Joining.JoiningType, virama: Bool, leftJoining: Bool, awaitingRight: Bool) -> State:
  match value awaitingRight:
    case Joining.Transparent{} waiting: Active{virama, leftJoining, waiting}
    case +other False{}: Active{virama, leftContext(other, False{}), False{}}
    case +other True{}: resolved(rightContext(other), virama, leftContext(other, False{}))

def nonJoiner(beforeVirama: Bool, leftJoining: Bool, awaitingRight: Bool) -> State:
  match beforeVirama leftJoining awaitingRight:
    case _ _ True{}: Invalid{}
    case True{} _ False{}: Active{False{}, False{}, False{}}
    case False{} True{} False{}: Active{False{}, False{}, True{}}
    case _ _ _: Invalid{}

def joiner(beforeVirama: Bool, awaitingRight: Bool) -> State:
  resolved(beforeVirama && Bool.not(awaitingRight), False{}, False{})

def character(code: U32, joining: Joining.JoiningType, virama: Bool, beforeVirama: Bool, leftJoining: Bool, awaitingRight: Bool) -> State:
  match code:
    case 8204: nonJoiner(beforeVirama, leftJoining, awaitingRight)
    case 8205: joiner(beforeVirama, awaitingRight)
    case _: ordinary(joining, virama, leftJoining, awaitingRight)

# Feed properties of one scalar in logical label order. Join-control properties
# are fixed by Unicode; their identity takes precedence over supplied properties.
def push(state: State, code: U32, joining: Joining.JoiningType, combiningClass: U32) -> State:
  match state:
    case Invalid{}: Invalid{}
    case Active{beforeVirama, leftJoining, awaitingRight}:
      character(code, joining, U32.is_eq(combiningClass, 9), beforeVirama, leftJoining, awaitingRight)

def finish(state: State) -> Bool:
  match state:
    case Invalid{}: False{}
    case Active{_, _, awaitingRight}: Bool.not(awaitingRight)

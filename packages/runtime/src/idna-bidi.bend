import Base
import ./unicode-bidi-class.bend as Bidi

# RFC 5893 section 2. The caller applies validity to every label if any label
# contains R, AL or AN. This rule does not replace IDNA mapping/label validity.
type DirectionState is Data:
  Initial{}
  Left{terminal: Bool}
  Right{terminal: Bool, european: Bool, arabic: Bool}
  Invalid{}

type State is Data:
  State{direction: DirectionState, hasRTL: Bool}

type Analysis is Data:
  Analysis{hasRTL: Bool, valid: Bool}

def start() -> State:
  State{Initial{}, False{}}

def rtlClass(value: Bidi.Class) -> Bool:
  match value:
    case Bidi.R{}: True{}
    case Bidi.AL{}: True{}
    case Bidi.AN{}: True{}
    case _: False{}

def initial(value: Bidi.Class) -> DirectionState:
  match value:
    case Bidi.L{}: Left{True{}}
    case Bidi.R{}: Right{True{}, False{}, False{}}
    case Bidi.AL{}: Right{True{}, False{}, False{}}
    case _: Invalid{}

def left(value: Bidi.Class, terminal: Bool) -> DirectionState:
  match value:
    case Bidi.L{}: Left{True{}}
    case Bidi.EN{}: Left{True{}}
    case Bidi.NSM{}: Left{terminal}
    case Bidi.ES{}: Left{False{}}
    case Bidi.CS{}: Left{False{}}
    case Bidi.ET{}: Left{False{}}
    case Bidi.ON{}: Left{False{}}
    case Bidi.BN{}: Left{False{}}
    case _: Invalid{}

def right(value: Bidi.Class, terminal: Bool, european: Bool, arabic: Bool) -> DirectionState:
  match value:
    case Bidi.R{}: Right{True{}, european, arabic}
    case Bidi.AL{}: Right{True{}, european, arabic}
    case Bidi.EN{}: Right{True{}, True{}, arabic}
    case Bidi.AN{}: Right{True{}, european, True{}}
    case Bidi.NSM{}: Right{terminal, european, arabic}
    case Bidi.ES{}: Right{False{}, european, arabic}
    case Bidi.CS{}: Right{False{}, european, arabic}
    case Bidi.ET{}: Right{False{}, european, arabic}
    case Bidi.ON{}: Right{False{}, european, arabic}
    case Bidi.BN{}: Right{False{}, european, arabic}
    case _: Invalid{}

def advance(state: DirectionState, value: Bidi.Class) -> DirectionState:
  match state:
    case Initial{}: initial(value)
    case Left{terminal}: left(value, terminal)
    case Right{terminal, european, arabic}: right(value, terminal, european, arabic)
    case Invalid{}: Invalid{}

# Continue collecting hasRTL even after rule failure: a late RTL character
# still makes other labels in the domain subject to the Bidi rule.
def push(state: State, +value: Bidi.Class) -> State:
  match state:
    case State{direction, hasRTL}: State{advance(direction, value), hasRTL || rtlClass(value)}

def accepted(state: DirectionState) -> Bool:
  match state:
    case Left{terminal}: terminal
    case Right{terminal, european, arabic}: terminal && Bool.not(european && arabic)
    case _: False{}

def finish(state: State) -> Analysis:
  match state:
    case State{direction, hasRTL}: Analysis{hasRTL, accepted(direction)}

def scan(values: List<&2, Bidi.Class>, state: State) -> Analysis:
  match values:
    case Nil{}: finish(state)
    case value <> rest: scan(rest, push(state, value))

def analyze(values: List<&2, Bidi.Class>) -> Analysis:
  scan(values, start())

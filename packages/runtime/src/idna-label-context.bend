import Base
import ./u32-table.bend as Table
import ./idna-properties.bend as Properties
import ./idna-bidi.bend as Bidi
import ./idna-contextj.bend as Joiners

type State is Data:
  State{first: Bool, leadingMark: Bool, bidi: Bidi.State, joiners: Joiners.State}

type Analysis is Data:
  Analysis{leadingMark: Bool, bidi: Bidi.Analysis, joinersValid: Bool}

def mark(first: Bool, previous: Bool, current: Bool) -> Bool:
  match first:
    case True{}: current
    case False{}: previous

def advance(properties: Maybe<&2, Properties.Properties>, code: U32, state: State) -> Result<&2, &2, U32, State>:
  match properties state:
    case None{} _: Fail{code}
    case Some{Properties.Properties{direction, joining, combiningClass, isMark}} State{first, leadingMark, bidi, joiners}:
      Done{State{False{}, mark(first, leadingMark, isMark), Bidi.push(bidi, direction), Joiners.push(joiners, code, joining, combiningClass)}}

def finish(state: State) -> Analysis:
  match state:
    case State{_, leadingMark, bidi, joiners}: Analysis{leadingMark, Bidi.finish(bidi), Joiners.finish(joiners)}

def scan(text: String, +table: Table.Table<Properties.Entry>, state: Result<&2, &2, U32, State>) -> Result<&2, &2, U32, Analysis>:
  match text state:
    case _ Fail{code}: Fail{code}
    case SNil{} Done{value}: Done{finish(value)}
    case SCon{Chr{+code}, rest} Done{value}: scan(rest, table, advance(Properties.lookup(table, code), code, value))

# Analyze a prepared, decoded label. The caller still checks mapping status,
# NFC, hyphens, ACE handling and domain-level applicability of the Bidi rule.
def analyze(table: Table.Table<Properties.Entry>, text: String) -> Result<&2, &2, U32, Analysis>:
  scan(text, table, Done{State{True{}, False{}, Bidi.start(), Joiners.start()}})

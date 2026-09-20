import Base

# Values returned by choose carry the next rotation state. The owning resolver
# serializes those transitions; no process-global counter or numeric wrap is
# needed. Initialization preserves the order supplied by the caller.
type State<-Server: Data> is Data:
  State{original: List<&2, Server>, current: List<&2, Server>}

type Chosen<-Server: Data> is Data:
  Chosen{servers: List<&2, Server>, next: State<Server>}

def start(-Server: Data, +servers: List<&2, Server>) -> State<Server>:
  State{servers, servers}

# Tail-recursive append of one item, avoiding Base's non-tail List.append.
def prependReversed(-Server: Data, reversed: List<&2, Server>, tail: List<&2, Server>) -> List<&2, Server>:
  match reversed:
    case Nil{}: tail
    case item <> rest: prependReversed(Server, rest, item <> tail)

def shift(-Server: Data, servers: List<&2, Server>) -> List<&2, Server>:
  match servers:
    case Nil{}: Nil{}
    case first <> rest: prependReversed(Server, List.reverse(&2, Server, rest), first <> Nil{})

# Disabling rotation selects the original order without advancing the retained
# position. Enabled selections return the current order then move one place.
# Empty/singleton lists stay structurally unchanged; duplicates are preserved.
def choose(-Server: Data, enabled: Bool, state: State<Server>) -> Chosen<Server>:
  match enabled state:
    case False{} State{+original, current}: Chosen{original, State{original, current}}
    case True{} State{original, +current}: Chosen{current, State{original, shift(Server, current)}}

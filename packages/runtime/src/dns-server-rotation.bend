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

# Split once, then join suffix and prefix. Initialization is linear in the
# list length, rather than repeatedly shifting the entire list.
def offsetList(-Server: Data, offset: Nat, servers: List<&2, Server>, reversed: List<&2, Server>) -> List<&2, Server>:
  match offset servers:
    case 0n suffix: prependReversed(Server, List.reverse(&2, Server, suffix), List.reverse(&2, Server, reversed))
    case 1n+rest first <> tail: offsetList(Server, rest, tail, first <> reversed)
    case _ Nil{}: List.reverse(&2, Server, reversed)

def positioned(-Server: Data, offset: Nat, +servers: List<&2, Server>, length: Nat) -> State<Server>:
  match length:
    case 0n: State{servers, servers}
    case count: State{servers, offsetList(Server, Nat.mod(offset, count), servers, Nil{})}

def countServers(-Server: Data, servers: List<&2, Server>, count: Nat) -> Nat:
  match servers:
    case Nil{}: count
    case _ <> rest: countServers(Server, rest, 1n+count)

# The seed chooses only the initial position. Disabled choices always return
# the configured order, and do not discard this retained position.
def startAt(-Server: Data, offset: Nat, +servers: List<&2, Server>) -> State<Server>:
  positioned(Server, offset, servers, countServers(Server, servers, 0n))

# Disabling rotation selects the original order without advancing the retained
# position. Enabled selections return the current order then move one place.
# Empty/singleton lists stay structurally unchanged; duplicates are preserved.
def choose(-Server: Data, enabled: Bool, state: State<Server>) -> Chosen<Server>:
  match enabled state:
    case False{} State{+original, current}: Chosen{original, State{original, current}}
    case True{} State{original, +current}: Chosen{current, State{original, shift(Server, current)}}

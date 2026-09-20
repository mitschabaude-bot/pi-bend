import Base

# One query's selected server order is retained across retry rounds. The caller
# supplies already-rotated entries (including their original server indices).
# This cursor stores two lists, not a materialized attempts-by-servers product.
type Cursor<-Server: Data> is Data:
  Cursor{laterRounds: Nat, servers: List<&2, Server>, remaining: List<&2, Server>}

type Step<-Server: Data> is Data:
  Exhausted{}
  Try{server: Server, next: Cursor<Server>}

def start(-Server: Data, attempts: Nat, +servers: List<&2, Server>) -> Cursor<Server>:
  match attempts:
    case Zero{}: Cursor{Zero{}, Nil{}, Nil{}}
    case Succ{later}: Cursor{later, servers, servers}

def restart(-Server: Data, rounds: Nat, +servers: List<&2, Server>) -> Step<Server>:
  match rounds servers:
    case Zero{} _: Exhausted{}
    case _ Nil{}: Exhausted{}
    case Succ{later} first <> rest: Try{first, Cursor{later, servers, rest}}

def next(-Server: Data, cursor: Cursor<Server>) -> Step<Server>:
  match cursor:
    case Cursor{later, servers, Nil{}}: restart(Server, later, servers)
    case Cursor{later, servers, first <> rest}: Try{first, Cursor{later, servers, rest}}

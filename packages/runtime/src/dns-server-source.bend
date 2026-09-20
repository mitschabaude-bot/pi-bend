import Base
import ./ref.bend as Ref
import ./dns-server-rotation.bend as Rotation

type Owner<-Server: Data> is Type:
  Owner{original: List<&2, Server>, state: Ref.Ref<Rotation.State<Server>>}

type Source<-Server: Data> is Data:
  Fixed{servers: List<&2, Server>}
  Rotating{original: List<&2, Server>, state: Ref.Ref<Rotation.State<Server>>, enabled: Bool}

def create(-Server: Data, +servers: List<&2, Server>) -> IO(Owner<Server>):
  do IO<Owner<Server>>:
    state : Ref.Ref<Rotation.State<Server>> <- Ref.new(Rotation.State<Server>, Rotation.start(Server, servers))
    return Owner{servers, state}

# Sources are borrowed. All uses must finish before the owner is closed.
def borrow(-Server: Data, enabled: Bool, owner: Owner<Server>) -> Owner<Server> & Source<Server>:
  match owner:
    case Owner{+configured, +state}: (Owner{configured, state}, Rotating{configured, state, enabled})

def original(-Server: Data, source: Source<Server>) -> List<&2, Server>:
  match source:
    case Fixed{servers}: servers
    case Rotating{servers, _, _}: servers

def nonempty(-Server: Data, servers: List<&2, Server>) -> Bool:
  match servers:
    case Nil{}: False{}
    case _ <> _: True{}

def available(-Server: Data, source: Source<Server>) -> Bool:
  nonempty(Server, original(Server, source))

def transition(-Server: Data, choice: Rotation.Chosen<Server>) -> Rotation.State<Server> & List<&2, Server>:
  match choice:
    case Rotation.Chosen{servers, next}: (next, servers)

# The callback is pure and the state is exclusively held until its replacement
# is sent back. Concurrent selections each consume one distinct rotation step.
def choose(-Server: Data, source: Source<Server>) -> IO(List<&2, Server>):
  match source:
    case Fixed{servers}: IO.pure(List<&2, Server>, servers)
    case Rotating{_, state, enabled}: Ref.modify(Rotation.State<Server>, List<&2, Server>, state, saved => transition(Server, Rotation.choose(Server, enabled, saved)))

def close(-Server: Data, owner: Owner<Server>) -> IO(Unit):
  match owner:
    case Owner{_, state}:
      do IO<Unit>:
        retired : Rotation.State<Server> <- Ref.dispose(Rotation.State<Server>, state)
        return Unit{}

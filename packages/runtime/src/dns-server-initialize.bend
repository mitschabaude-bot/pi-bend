import Base
import ./dns-server-source.bend as Source
import ./dns-server-rotation.bend as Rotation
import ./random-index.bend as Index

# Allocate the owner only after sampling succeeds. Failure owns no selector
# resources; the source environment remains with its caller.
def selected(-Server: Data, servers: List<&2, Server>, result: Result<&2, &2, Index.Error, Nat>) -> IO(Result<&2, &1, Index.Error, Source.Owner<Server>>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &1, Index.Error, Source.Owner<Server>>, Fail{error})
    case Done{offset}:
      do IO<Result<&2, &1, Index.Error, Source.Owner<Server>>>:
        owner : Source.Owner<Server> <- Source.createAt(Server, offset, servers)
        return Done{owner}

def counted(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), -Server: Data, environment: Environment, servers: List<&2, Server>, count: Nat) -> IO(Result<&2, &1, Index.Error, Source.Owner<Server>>):
  match count:
    case 0n: selected(Server, servers, Done{0n})
    case size:
      do IO<Result<&2, &1, Index.Error, Source.Owner<Server>>>:
        index : Result<&2, &2, Index.Error, Nat> <- Index.sampleWith(~Environment, ~draw, environment, size)
        selected(Server, servers, index)

def createWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), -Server: Data, environment: Environment, +servers: List<&2, Server>) -> IO(Result<&2, &1, Index.Error, Source.Owner<Server>>):
  counted(~Environment, ~draw, Server, environment, servers, Rotation.countServers(Server, servers, 0n))

# Empty and singleton lists need no entropy. Larger lists receive a uniformly
# selected initial position, while disabled choices retain configured order.
def random(-Server: Data, servers: List<&2, Server>) -> IO(Result<&2, &1, Index.Error, Source.Owner<Server>>):
  createWith(~Unit, ~Index.word, Server, Unit{}, servers)

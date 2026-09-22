import Base
import ./numeric-scope.bend as Scope
import ./network-interface.bend as Interface
import ./hosts.bend as Family
import ./socket.bend as Connect

# Resolve a numeric destination through the native interface-index primitive.
# No DNS, resolver owner, hosts file, port or connection is involved.
def prepare(family: Family.Family, text: String) -> IO(Result<&2, &2, Scope.Error<Interface.Error>, Connect.Address>):
  Scope.prepareWith(~Interface.Error, ~Unit, ~Interface.lookup, Unit{}, family, text)

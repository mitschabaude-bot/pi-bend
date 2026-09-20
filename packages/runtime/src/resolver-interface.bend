import Base
import ./network-interface.bend as Interface
import ./resolver-address.bend as Address
import ./resolver-scope.bend as Scope

# Keep the OS effect separate from the injectable pure scope policy.
def resolve(address: Address.Address) -> IO(Scope.Report<Interface.Error>):
  Scope.resolveWith(~Interface.Error, ~Unit, ~Interface.lookup, Unit{}, address)

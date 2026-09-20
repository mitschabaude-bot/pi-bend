import Base
import ./network-interface.bend as Interface
import ./resolver-address.bend as Address
import ./resolver-scope.bend as Scope
import ./resolver-servers.bend as Servers
import ./resolver-settings.bend as Settings

# Keep the OS effect separate from the injectable pure scope policy.
def resolve(address: Address.Address) -> IO(Scope.Report<Interface.Error>):
  Scope.resolveWith(~Interface.Error, ~Unit, ~Interface.lookup, Unit{}, address)

def resolveAll(addresses: List<&2, Address.Address>) -> IO(Servers.Report<Interface.Error>):
  Servers.resolveWith(~Interface.Error, ~Unit, ~Interface.lookup, Unit{}, addresses)

def prepare(settings: Settings.Settings) -> IO(Servers.Configuration<Interface.Error>):
  Servers.prepareWith(~Interface.Error, ~Unit, ~Interface.lookup, Unit{}, settings)

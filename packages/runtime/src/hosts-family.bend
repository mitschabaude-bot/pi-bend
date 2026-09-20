import Base
import ./hosts.bend as Hosts
import ./hosts-file.bend as File

# Filtering never maps addresses or sorts/deduplicates source entries.
type Family is Data:
  Any{}
  IPv4Only{}
  IPv6Only{}

def accepts(family: Family, address: File.Address) -> Bool:
  match family address:
    case Any{} _: True{}
    case IPv4Only{} File.V4{_}: True{}
    case IPv6Only{} File.V6{_}: True{}
    case _ _: False{}

def select(+family: Family, entries: List<&2, Hosts.Entry<File.Address>>) -> List<&2, Hosts.Entry<File.Address>>:
  match entries:
    case Nil{}: Nil{}
    case Hosts.Entry{+address, canonical, aliases} <> rest: Hosts.selected(File.Address, accepts(family, address), Hosts.Entry{address, canonical, aliases}, select(family, rest))

def lookup(family: Family, name: String, entries: List<&2, Hosts.Entry<File.Address>>) -> List<&2, Hosts.Entry<File.Address>>:
  select(family, Hosts.lookup(File.Address, name, entries))

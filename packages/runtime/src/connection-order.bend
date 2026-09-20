import Base
import ./abortable-connect.bend as Connect
import ./url-ipv4.bend as IPv4
import ./url-ipv6.bend as IPv6
import ./connection-addresses.bend as Candidates
import ./list-interleave.bend as Interleave

type Preference is Data:
  IPv4First{}
  IPv6First{}

def family(address: Connect.Address) -> Preference:
  match address:
    case Connect.V4{_}: IPv4First{}
    case Connect.V6{_, _}: IPv6First{}

# Address identity is numeric and includes the IPv6 interface scope. Values
# from hosts/DNS are already parsed, so spelling is not a second identity.
def same(left: Connect.Address, right: Connect.Address) -> Bool:
  match left right:
    case Connect.V4{IPv4.Address{a}} Connect.V4{IPv4.Address{b}}: U32.is_eq(a, b)
    case Connect.V6{IPv6.Address{a, b, c, d}, scope} Connect.V6{IPv6.Address{w, x, y, z}, other}: U32.is_eq(a, w) && U32.is_eq(b, x) && U32.is_eq(c, y) && U32.is_eq(d, z) && U32.is_eq(scope, other)
    case _ _: False{}

def contains(addresses: List<&2, Connect.Address>, +address: Connect.Address) -> Bool:
  match addresses:
    case Nil{}: False{}
    case first <> rest: same(first, address) || contains(rest, address)

type Groups is Data:
  Groups{ipv4: List<&2, Connect.Address>, ipv6: List<&2, Connect.Address>}

def added(seen: Bool, address: Connect.Address, group: List<&2, Connect.Address>) -> List<&2, Connect.Address>:
  match seen:
    case True{}: group
    case False{}: address <> group

def insert(address: Connect.Address, groups: Groups) -> Groups:
  match address groups:
    case Connect.V4{+value} Groups{+ipv4, ipv6}: Groups{added(contains(ipv4, Connect.V4{value}), Connect.V4{value}, ipv4), ipv6}
    case Connect.V6{+value, +scope} Groups{ipv4, +ipv6}: Groups{ipv4, added(contains(ipv6, Connect.V6{value, scope}), Connect.V6{value, scope}, ipv6)}

def collect(addresses: List<&2, Connect.Address>, groups: Groups) -> Groups:
  match addresses:
    case Nil{}: groups
    case first <> rest: collect(rest, insert(first, groups))

def ordered(preference: Preference, groups: Groups) -> List<&2, Connect.Address>:
  match preference groups:
    case IPv4First{} Groups{ipv4, ipv6}: Interleave.interleave(Connect.Address, List.reverse(&2, Connect.Address, ipv4), List.reverse(&2, Connect.Address, ipv6))
    case IPv6First{} Groups{ipv4, ipv6}: Interleave.interleave(Connect.Address, List.reverse(&2, Connect.Address, ipv6), List.reverse(&2, Connect.Address, ipv4))

# Ordered resolver output chooses its first family's preference. Paired output
# has no cross-family order, so the caller must supply that policy explicitly.
# Deduplication applies to attempts only; original resolution reports remain intact.
def prepare(preference: Preference, candidates: Candidates.Candidates) -> List<&2, Connect.Address>:
  match candidates:
    case Candidates.Ordered{+first, rest}: ordered(family(first), collect(first <> rest, Groups{Nil{}, Nil{}}))
    case Candidates.Paired{ipv4, ipv6}: ordered(preference, collect(ipv6, collect(ipv4, Groups{Nil{}, Nil{}})))

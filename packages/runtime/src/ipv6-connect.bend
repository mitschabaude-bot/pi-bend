import Base
import ./url.bend as IPv6

# Reuse the native address value; the effect receives four network-order words.
# A URL host uses scope 0. Interface-scoped OS addresses can supply a scope ID.
def connect(address: IPv6.Ipv6Address, port: U32, scope: U32) -> IO(Result<&1, &1, U32 & String, Socket>):
  match address:
    case IPv6.Ipv6Address{a, b, c, d}: TCP.connect_ipv6(a, b, c, d, port, scope)

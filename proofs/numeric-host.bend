import Base
import ../laws/numeric-host.bend as Laws
import ../packages/runtime/src/numeric-host.bend as Host

def Laws.unrestricted_preserves_input(input):
  match input:
    case Host.V4{address}: {==}
    case Host.V6{address, zone}: {==}
def Laws.ipv4_preserves_address(address): {==}
def Laws.ipv6_preserves_address_and_zone(address, zone): {==}
def Laws.ipv4_rejects_ipv6(address, zone): {==}
def Laws.ipv6_rejects_ipv4(address): {==}
def Laws.failed_parse_retained(family, error): {==}

import Base
import ../packages/runtime/src/numeric-host.bend as Host
import ../packages/runtime/src/hosts.bend as Family
import ../packages/runtime/src/url.bend as IPv4
import ../packages/runtime/src/url.bend as IPv6

law unrestricted_preserves_input:
  for +input: Host.Input
  {Host.selected(Family.Any{}, input) == Done{input} : Result<&2, &2, Host.Error, Host.Input>}

law ipv4_preserves_address:
  for +address: IPv4.Address
  {Host.selected(Family.IPv4Only{}, Host.V4{address}) == Done{Host.V4{address}} : Result<&2, &2, Host.Error, Host.Input>}

law ipv6_preserves_address_and_zone:
  for +address: IPv6.Ipv6Address
  for +zone: Maybe<&2, String>
  {Host.selected(Family.IPv6Only{}, Host.V6{address, zone}) == Done{Host.V6{address, zone}} : Result<&2, &2, Host.Error, Host.Input>}

law ipv4_rejects_ipv6:
  for address: IPv6.Ipv6Address
  for zone: Maybe<&2, String>
  {Host.selected(Family.IPv4Only{}, Host.V6{address, zone}) == Fail{Host.FamilyMismatch{}} : Result<&2, &2, Host.Error, Host.Input>}

law ipv6_rejects_ipv4:
  for address: IPv4.Address
  {Host.selected(Family.IPv6Only{}, Host.V4{address}) == Fail{Host.FamilyMismatch{}} : Result<&2, &2, Host.Error, Host.Input>}

law failed_parse_retained:
  for family: Family.Family
  for +error: Host.Error
  {Host.accepted(family, Fail{error}) == Fail{error} : Result<&2, &2, Host.Error, Host.Input>}

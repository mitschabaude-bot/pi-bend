import Base
import ../packages/runtime/src/http-host-route.bend as Route
import ../packages/runtime/src/url-host.bend as Host
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/src/abortable-connect.bend as Connect

law ipv4_bypasses_lookup:
  for +address: IPv4.Address
  {Route.plan(Host.IPv4{address}) == Route.Numeric{Connect.V4{address}} : Route.Plan}

law ipv6_bypasses_lookup:
  for +address: IPv6.Address
  {Route.plan(Host.IPv6{address}) == Route.Numeric{Connect.V6{address, 0}} : Route.Plan}

law domain_spelling_retained:
  for +first: Char
  for +rest: String
  {Route.plan(Host.Domain{SCon{first, rest}}) == Route.Lookup{SCon{first, rest}} : Route.Plan}

law opaque_host_rejected:
  for text: String
  {Route.plan(Host.Opaque{text}) == Route.Invalid{} : Route.Plan}

law empty_domain_rejected:
  {Route.plan(Host.Domain{""}) == Route.Invalid{} : Route.Plan}

law empty_host_rejected:
  {Route.plan(Host.Empty{}) == Route.Invalid{} : Route.Plan}

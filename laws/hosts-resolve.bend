import Base
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/hosts.bend as File
import ../packages/runtime/src/hosts.bend as Family
import ../packages/runtime/src/hosts.bend as Resolve
import ../packages/runtime/src/url.bend as IPv4
import ../packages/runtime/src/url.bend as IPv6

law any_preserves_database:
  for +entries: List<&2, Hosts.Entry<File.Address>>
  {Family.select(Family.Any{}, entries) == entries : List<&2, Hosts.Entry<File.Address>>}

law family_append:
  for +family: Family.Family
  for +left: List<&2, Hosts.Entry<File.Address>>
  for +right: List<&2, Hosts.Entry<File.Address>>
  {Family.select(family, List.append(&2, Hosts.Entry<File.Address>, left, right)) == List.append(&2, Hosts.Entry<File.Address>, Family.select(family, left), Family.select(family, right)) : List<&2, Hosts.Entry<File.Address>>}

law ipv4_excludes_ipv6:
  for address: IPv6.Ipv6Address
  for canonical: String
  for aliases: List<&2, String>
  for +rest: List<&2, Hosts.Entry<File.Address>>
  {Family.select(Family.IPv4Only{}, Hosts.Entry{File.V6{address}, canonical, aliases} <> rest) == Family.select(Family.IPv4Only{}, rest) : List<&2, Hosts.Entry<File.Address>>}

law ipv6_excludes_ipv4:
  for address: IPv4.Address
  for canonical: String
  for aliases: List<&2, String>
  for +rest: List<&2, Hosts.Entry<File.Address>>
  {Family.select(Family.IPv6Only{}, Hosts.Entry{File.V4{address}, canonical, aliases} <> rest) == Family.select(Family.IPv6Only{}, rest) : List<&2, Hosts.Entry<File.Address>>}

law source_error_is_terminal:
  for -Error: Data
  for family: Family.Family
  for name: String
  for +error: Error
  {Resolve.plan(Error, family, name, Fail{error}) == Resolve.SourceFailure{error} : Resolve.Plan<Error>}

law empty_database_queries_original:
  for -Error: Data
  for +family: Family.Family
  for +name: String
  {Resolve.plan(Error, family, name, Done{Nil{}}) == Resolve.Query{family, name} : Resolve.Plan<Error>}

law eligible_rows_are_local:
  for -Error: Data
  for family: Family.Family
  for name: String
  for +first: Hosts.Entry<File.Address>
  for +rest: List<&2, Hosts.Entry<File.Address>>
  {Resolve.selectedResolve(Error, family, name, first <> rest) == Resolve.Local{first, rest} : Resolve.Plan<Error>}

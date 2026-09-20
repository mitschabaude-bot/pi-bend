import Base
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/src/connection-addresses.bend as Candidates
import ../packages/runtime/src/abortable-connect.bend as Connect
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/hosts-file.bend as File
import ../packages/runtime/src/dns-address-answer.bend as DNS

law hosts_count:
  for +entries: List<&2, Hosts.Entry<File.Address>>
  {List.length(&2, Connect.Address, Candidates.hosts(entries)) == List.length(&2, Hosts.Entry<File.Address>, entries) : Nat}

law answers_count:
  for +addresses: List<&2, DNS.Address>
  {List.length(&2, Connect.Address, Candidates.answers(addresses)) == List.length(&2, DNS.Address, addresses) : Nat}

law hosts_append:
  for +left: List<&2, Hosts.Entry<File.Address>>
  for +right: List<&2, Hosts.Entry<File.Address>>
  {Candidates.hosts(List.append(&2, Hosts.Entry<File.Address>, left, right)) == List.append(&2, Connect.Address, Candidates.hosts(left), Candidates.hosts(right)) : List<&2, Connect.Address>}

law answers_append:
  for +left: List<&2, DNS.Address>
  for +right: List<&2, DNS.Address>
  {Candidates.answers(List.append(&2, DNS.Address, left, right)) == List.append(&2, Connect.Address, Candidates.answers(left), Candidates.answers(right)) : List<&2, Connect.Address>}

law ordered_retains_report_and_occurrences:
  for -R: Data
  for +report: R
  for +first: Connect.Address
  for +rest: List<&2, Connect.Address>
  {Candidates.ordered(R, report, first <> rest) == Candidates.Addresses{report, Candidates.Ordered{first, rest}} : Candidates.Plan<R>}

law empty_order_retains_report:
  for -R: Data
  for +report: R
  {Candidates.ordered(R, report, Nil{}) == Candidates.NoAddresses{report} : Candidates.Plan<R>}

law paired_retains_both_groups:
  for -R: Data
  for +report: R
  for +first: Connect.Address
  for +rest: List<&2, Connect.Address>
  for +other: List<&2, Connect.Address>
  {Candidates.paired(R, report, first <> rest, other) == Candidates.Addresses{report, Candidates.Paired{first <> rest, other}} : Candidates.Plan<R>}

law ipv6_only_retains_group:
  for -R: Data
  for +report: R
  for +first: Connect.Address
  for +rest: List<&2, Connect.Address>
  {Candidates.paired(R, report, Nil{}, first <> rest) == Candidates.Addresses{report, Candidates.Paired{Nil{}, first <> rest}} : Candidates.Plan<R>}

law empty_pair_retains_report:
  for -R: Data
  for +report: R
  {Candidates.paired(R, report, Nil{}, Nil{}) == Candidates.NoAddresses{report} : Candidates.Plan<R>}

law ipv4_host_address_retained:
  for +address: IPv4.Address
  for canonical: String
  for aliases: List<&2, String>
  {Candidates.host(Hosts.Entry{File.V4{address}, canonical, aliases}) == Connect.V4{address} : Connect.Address}

law ipv6_host_address_retained:
  for +address: IPv6.Address
  for canonical: String
  for aliases: List<&2, String>
  {Candidates.host(Hosts.Entry{File.V6{address}, canonical, aliases}) == Connect.V6{address, 0} : Connect.Address}

law ipv4_answer_address_retained:
  for +address: IPv4.Address
  for ttl: U32
  {Candidates.answer(DNS.V4{address, ttl}) == Connect.V4{address} : Connect.Address}

law ipv6_answer_address_retained:
  for +address: IPv6.Address
  for ttl: U32
  {Candidates.answer(DNS.V6{address, ttl}) == Connect.V6{address, 0} : Connect.Address}

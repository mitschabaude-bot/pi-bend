import Base
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/hosts-file.bend as File
import ../packages/runtime/src/dns-address-answer.bend as DNS
import ../laws/connection-addresses.bend as Laws
import ../packages/runtime/src/connection-addresses.bend as Candidates
import ../packages/runtime/src/abortable-connect.bend as Connect

def Laws.hosts_count(entries):
  match entries:
    case Nil{}: {==}
    case first <> rest:
      %Laws.hosts_count(rest) : {Succ{List.length(&2, Connect.Address, Candidates.hosts(rest))} == Succ{_} : Nat}
      {==}

def Laws.answers_count(addresses):
  match addresses:
    case Nil{}: {==}
    case first <> rest:
      %Laws.answers_count(rest) : {Succ{List.length(&2, Connect.Address, Candidates.answers(rest))} == Succ{_} : Nat}
      {==}

def Laws.hosts_append(left, right):
  match left:
    case Nil{}: {==}
    case first <> rest:
      %Laws.hosts_append(rest, right) : {Candidates.host(first) <> Candidates.hosts(List.append(&2, Hosts.Entry<File.Address>, rest, right)) == Candidates.host(first) <> _ : List<&2, Connect.Address>}
      {==}

def Laws.answers_append(left, right):
  match left:
    case Nil{}: {==}
    case first <> rest:
      %Laws.answers_append(rest, right) : {Candidates.answer(first) <> Candidates.answers(List.append(&2, DNS.Address, rest, right)) == Candidates.answer(first) <> _ : List<&2, Connect.Address>}
      {==}

def Laws.ordered_retains_report_and_occurrences(R, report, first, rest): {==}
def Laws.empty_order_retains_report(R, report): {==}
def Laws.paired_retains_both_groups(R, report, first, rest, other): {==}
def Laws.ipv6_only_retains_group(R, report, first, rest): {==}
def Laws.empty_pair_retains_report(R, report): {==}

def Laws.ipv4_host_address_retained(address, canonical, aliases): {==}
def Laws.ipv6_host_address_retained(address, canonical, aliases): {==}
def Laws.ipv4_answer_address_retained(address, ttl): {==}
def Laws.ipv6_answer_address_retained(address, ttl): {==}

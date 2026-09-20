import Base
import ../laws/hosts-resolve.bend as Laws
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/hosts-file.bend as File
import ../packages/runtime/src/hosts-family.bend as Family
import ./hosts.bend as Prior

def Laws.any_preserves_database(entries):
  match entries:
    case Nil{}: {==}
    case Hosts.Entry{address, canonical, aliases} <> rest:
      %Laws.any_preserves_database(rest) : {Hosts.Entry{address, canonical, aliases} <> Family.select(Family.Any{}, rest) == Hosts.Entry{address, canonical, aliases} <> _ : List<&2, Hosts.Entry<File.Address>>}
      {==}

def Laws.family_append(family, left, right):
  match left:
    case Nil{}: {==}
    case Hosts.Entry{address, canonical, aliases} <> rest:
      %Equal.sym(List<&2, Hosts.Entry<File.Address>>, Family.select(family, List.append(&2, Hosts.Entry<File.Address>, rest, right)), List.append(&2, Hosts.Entry<File.Address>, Family.select(family, rest), Family.select(family, right)), Laws.family_append(family, rest, right)) : {Hosts.selected(File.Address, Family.accepts(family, address), Hosts.Entry{address, canonical, aliases}, _) == List.append(&2, Hosts.Entry<File.Address>, Hosts.selected(File.Address, Family.accepts(family, address), Hosts.Entry{address, canonical, aliases}, Family.select(family, rest)), Family.select(family, right)) : List<&2, Hosts.Entry<File.Address>>}
      Prior.selected_append(File.Address, Family.accepts(family, address), Hosts.Entry{address, canonical, aliases}, Family.select(family, rest), Family.select(family, right))

def Laws.ipv4_excludes_ipv6(address, canonical, aliases, rest): {==}
def Laws.ipv6_excludes_ipv4(address, canonical, aliases, rest): {==}
def Laws.source_error_is_terminal(Error, family, name, error): {==}
def Laws.empty_database_queries_original(Error, family, name):
  match family:
    case Family.Any{}: {==}
    case Family.IPv4Only{}: {==}
    case Family.IPv6Only{}: {==}
def Laws.eligible_rows_are_local(Error, family, name, first, rest): {==}

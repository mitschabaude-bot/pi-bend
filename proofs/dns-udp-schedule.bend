import Base
import ../laws/dns-udp-schedule.bend as Laws
import ../packages/runtime/src/resolver-config.bend as Schedule

law empty_rounds:
  for -Server: Data
  for count: Nat
  {Nil{} == Laws.rounds(Server, count, Nil{}) : List<&2, Server>}

def empty_rounds(Server, count):
  match count:
    case Zero{}: {==}
    case Succ{rest}: empty_rounds(Server, rest)

def Laws.initial_sequence(Server, count, servers):
  match count:
    case Zero{}: {==}
    case Succ{_}: {==}

def Laws.next_sequence(Server, cursor):
  match cursor:
    case Schedule.Cursor{_, _, first <> rest}: {==}
    case Schedule.Cursor{Zero{}, Nil{}, Nil{}}: {==}
    case Schedule.Cursor{Zero{}, _ <> _, Nil{}}: {==}
    case Schedule.Cursor{Succ{later}, first <> rest, Nil{}}: {==}
    case Schedule.Cursor{Succ{later}, Nil{}, Nil{}}:
      %empty_rounds(Server, later) : {Laws.Observation{None{}, Nil{}} == Laws.uncons(Server, _) : Laws.Observation<Server>}
      {==}

def Laws.zero_attempts(Server, servers): {==}

def Laws.no_servers(Server, count):
  match count:
    case Zero{}: {==}
    case Succ{Zero{}}: {==}
    case Succ{Succ{_}}: {==}

law append_length:
  for -Server: Data
  for +left: List<&2, Server>
  for +right: List<&2, Server>
  {Nat.add(List.length(&2, Server, left), List.length(&2, Server, right)) == List.length(&2, Server, List.append(&2, Server, left, right)) : Nat}

def append_length(Server, left, right):
  match left:
    case Nil{}: {==}
    case _ <> rest:
      %append_length(Server, rest, right) : {Succ{Nat.add(List.length(&2, Server, rest), List.length(&2, Server, right))} == Succ{_} : Nat}
      {==}

law rounds_length:
  for -Server: Data
  for +count: Nat
  for +servers: List<&2, Server>
  {Nat.mul(count, List.length(&2, Server, servers)) == List.length(&2, Server, Laws.rounds(Server, count, servers)) : Nat}

def rounds_length(Server, count, servers):
  match count:
    case Zero{}: {==}
    case Succ{rest}:
      %append_length(Server, servers, Laws.rounds(Server, rest, servers)) : {Nat.add(List.length(&2, Server, servers), Nat.mul(rest, List.length(&2, Server, servers))) == _ : Nat}
      %rounds_length(Server, rest, servers) : {Nat.add(List.length(&2, Server, servers), Nat.mul(rest, List.length(&2, Server, servers))) == Nat.add(List.length(&2, Server, servers), _) : Nat}
      {==}

def Laws.initial_count(Server, count, servers):
  match count:
    case Zero{}: {==}
    case Succ{rest}:
      %append_length(Server, servers, Laws.rounds(Server, rest, servers)) : {_ == Nat.add(List.length(&2, Server, servers), Nat.mul(rest, List.length(&2, Server, servers))) : Nat}
      %rounds_length(Server, rest, servers) : {Nat.add(List.length(&2, Server, servers), _) == Nat.add(List.length(&2, Server, servers), Nat.mul(rest, List.length(&2, Server, servers))) : Nat}
      {==}

def Laws.fallback_current_pass(Server, selected, later, original, pending): {==}

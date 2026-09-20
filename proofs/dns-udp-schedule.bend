import Base
import ../laws/dns-udp-schedule.bend as Laws
import ../packages/runtime/src/dns-udp-schedule.bend as Schedule

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

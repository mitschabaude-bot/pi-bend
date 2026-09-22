import Base
import ../packages/runtime/src/resolver-config.bend as Schedule

# Independent list specification: repeat the entire selected order per round.
def rounds(-Server: Data, count: Nat, +servers: List<&2, Server>) -> List<&2, Server>:
  match count:
    case Zero{}: Nil{}
    case Succ{rest}: List.append(&2, Server, servers, rounds(Server, rest, servers))

def remaining(-Server: Data, cursor: Schedule.Cursor<Server>) -> List<&2, Server>:
  match cursor:
    case Schedule.Cursor{later, servers, pending}: List.append(&2, Server, pending, rounds(Server, later, servers))

type Observation<-Server: Data> is Data:
  Observation{server: Maybe<&2, Server>, remaining: List<&2, Server>}

def uncons(-Server: Data, servers: List<&2, Server>) -> Observation<Server>:
  match servers:
    case Nil{}: Observation{None{}, Nil{}}
    case first <> rest: Observation{Some{first}, rest}

def observe(-Server: Data, step: Schedule.Step<Server>) -> Observation<Server>:
  match step:
    case Schedule.Exhausted{}: Observation{None{}, Nil{}}
    case Schedule.Try{server, cursor}: Observation{Some{server}, remaining(Server, cursor)}

law initial_sequence:
  for -Server: Data
  for +count: Nat
  for +servers: List<&2, Server>
  {remaining(Server, Schedule.start(Server, count, servers)) == rounds(Server, count, servers) : List<&2, Server>}

law next_sequence:
  for -Server: Data
  for +cursor: Schedule.Cursor<Server>
  {observe(Server, Schedule.next(Server, cursor)) == uncons(Server, remaining(Server, cursor)) : Observation<Server>}

law zero_attempts:
  for -Server: Data
  for servers: List<&2, Server>
  {Schedule.next(Server, Schedule.start(Server, Zero{}, servers)) == Schedule.Exhausted{} : Schedule.Step<Server>}

law no_servers:
  for -Server: Data
  for count: Nat
  {Schedule.next(Server, Schedule.start(Server, count, Nil{})) == Schedule.Exhausted{} : Schedule.Step<Server>}

# The driver's structural recursion budget covers the complete selected order
# across all rounds, for arbitrary server values, duplicates and list sizes.
law initial_count:
  for -Server: Data
  for +count: Nat
  for +servers: List<&2, Server>
  {List.length(&2, Server, remaining(Server, Schedule.start(Server, count, servers))) == Nat.mul(count, List.length(&2, Server, servers)) : Nat}

# Switching transports preserves the exact occurrence and remaining suffix,
# independently of later retry rounds or earlier duplicate server values.
law fallback_current_pass:
  for -Server: Data
  for +selected: Server
  for later: Nat
  for original: List<&2, Server>
  for +pending: List<&2, Server>
  {Schedule.fallback(Server, selected, Schedule.Cursor{later, original, pending}) == selected <> pending : List<&2, Server>}

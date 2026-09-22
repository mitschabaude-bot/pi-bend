import Base
import ../laws/resolver-config.bend as Laws
import ../packages/runtime/src/resolver-config.bend as Schedule
import ../packages/runtime/src/resolver-config.bend as Timeout

# Resolver configuration

def Laws.shared_search_settings(Server, options, servers, domains, milliseconds, maximum): {==}
def Laws.assembly_retains_configuration(Server, domains, milliseconds, maximum, transport): {==}
def Laws.rejects_invalid_transport(Server, domains, milliseconds, maximum, error): {==}


# Resolver request

def Laws.preserves_settings(options): {==}

def Laws.rejects_diagnostics(options, first, rest): {==}


# Resolver search

def Laws.preserves_request_policy(configuration, name, dots, absolute): {==}

def Laws.preserves_search_policy(configuration, name, dots, absolute): {==}

def Laws.search_rejects_diagnostics(options, first, rest, domains): {==}


# Resolver transport

def Laws.settings_and_entries_preserved(Server, options, entries): {==}
def Laws.preparation_failure_retained(Server, options, error): {==}


# Dns udp plan

def Laws.assignment_preserves_payloads(Server, servers):
  match servers:
    case Nil{}: {==}
    case _ <> Nil{}: {==}
    case _ <> _ <> Nil{}: {==}
    case _ <> _ <> _ <> Nil{}: {==}
    case _ <> _ <> _ <> _ <> _: {==}

def Laws.timing_preserves_identity(Server, server, position, duration): {==}
def Laws.invalid_layout_stops_preparation(Server, timeout, error): {==}


# Dns udp schedule

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


# Dns udp timeout

def Laws.duration_positive(duration):
  match duration:
    case Timeout.Duration{_}: {==}

def Laws.positive_preserved(additional): {==}
def Laws.zero_floor(): {==}
def Laws.first_server_undivided(timeout): {==}
law two_checked:
  for +valid: Bool
  for +timeout: U32
  {Timeout.checked(valid, timeout, Timeout.SecondOfTwo{}) == Timeout.checked(valid, timeout, Timeout.First{}) : Result<&2, &2, Timeout.UdpTimeoutError, Timeout.Duration>}

def two_checked(valid, timeout):
  match valid:
    case False{}: {==}
    case True{}: {==}

def Laws.two_servers_equal_budgets(timeout): two_checked(U32.is_le(timeout, 30), timeout)

def Laws.oversized_duration_rejected(extra): {==}

import Base
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/resolver-config.bend as Transport
import ../packages/runtime/src/resolver-config.bend as Search
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/resolver-config.bend as Domains
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/resolver-config.bend as Request
import ../packages/runtime/src/resolver-config.bend as Resolver
import ../packages/runtime/src/resolver-config.bend as Configuration
import ../packages/runtime/src/dns-message.bend as Query
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/resolver-config.bend as Timeout
import ../packages/runtime/src/resolver-config.bend as Schedule

# Resolver configuration

# Search and transport cannot accidentally use different option snapshots.
law shared_search_settings:
  for -Server: Data
  for +options: Options.ResolverOptions
  for servers: List<&2, Plan.Attempt<Server>>
  for +domains: Domains.Report
  for milliseconds: U32
  for maximum: U32
  {Config.search(Server, Config.Config{Transport.TransportPrepared{options, servers}, domains, milliseconds, maximum}) == Search.Configuration{options, domains} : Search.Configuration}

law assembly_retains_configuration:
  for -Server: Data
  for +domains: Domains.Report
  for +milliseconds: U32
  for +maximum: U32
  for +transport: Transport.TransportPrepared<Server>
  {Config.assembled(Server, domains, milliseconds, maximum, Done{transport}) == Done{Config.Config{transport, domains, milliseconds, maximum}} : Result<&2, &2, Plan.Error, Config.Config<Server>>}

law rejects_invalid_transport:
  for -Server: Data
  for domains: Domains.Report
  for milliseconds: U32
  for maximum: U32
  for +error: Plan.Error
  {Config.assembled(Server, domains, milliseconds, maximum, Fail{error}) == Fail{error} : Result<&2, &2, Plan.Error, Config.Config<Server>>}


# Resolver request

def settings(prepared: Request.Prepared) -> Resolver.ResolverOptions:
  match prepared:
    case Request.Prepared{options, _}: options

law preserves_settings:
  for +options: Resolver.ResolverOptions
  {settings(Request.prepareRequest(options)) == options : Resolver.ResolverOptions}

law rejects_diagnostics:
  for options: Resolver.ResolverOptions
  for +first: Resolver.Diagnostic
  for +rest: List<&2, Resolver.Diagnostic>
  {Request.checkedRequest(Resolver.OptionsReport{options, first <> rest}) == Fail{first <> rest} : Result<&2, &2, List<&2, Resolver.Diagnostic>, Request.Prepared>}


# Resolver search

def request(plan: Configuration.Plan) -> Query.QueryOptions:
  match plan:
    case Configuration.Plan{options, _}: options

def searchCursor(plan: Configuration.Plan) -> Message.SearchCursor:
  match plan:
    case Configuration.Plan{_, value}: value

law preserves_request_policy:
  for +configuration: Configuration.Configuration
  for name: Name.Name
  for dots: U32
  for absolute: Bool
  {request(Configuration.plan(configuration, name, dots, absolute)) == Configuration.requestOptions(configuration) : Query.QueryOptions}

law preserves_search_policy:
  for +configuration: Configuration.Configuration
  for +name: Name.Name
  for +dots: U32
  for +absolute: Bool
  {searchCursor(Configuration.plan(configuration, name, dots, absolute)) == Configuration.startSearch(configuration, name, dots, absolute) : Message.SearchCursor}

law search_rejects_diagnostics:
  for options: Options.ResolverOptions
  for +first: Options.Diagnostic
  for +rest: List<&2, Options.Diagnostic>
  for domains: List<&2, String>
  {Configuration.checkedSearch(Options.OptionsReport{options, first <> rest}, domains) == Fail{first <> rest} : Result<&2, &2, List<&2, Options.Diagnostic>, Configuration.Configuration>}


# Resolver transport

# Assembly must retain the full settings, including options interpreted by
# later layers, and every timed entry with its original-position metadata.
law settings_and_entries_preserved:
  for -Server: Data
  for +options: Options.ResolverOptions
  for +entries: List<&2, Plan.Attempt<Server>>
  {Transport.timedTransport(Server, options, Done{entries}) == Done{Transport.TransportPrepared{options, entries}} : Result<&2, &2, Plan.Error, Transport.TransportPrepared<Server>>}

law preparation_failure_retained:
  for -Server: Data
  for options: Options.ResolverOptions
  for +error: Plan.Error
  {Transport.timedTransport(Server, options, Fail{error}) == Fail{error} : Result<&2, &2, Plan.Error, Transport.TransportPrepared<Server>>}


# Dns udp plan

def values(-Server: Data, entries: List<&2, Plan.Located<Server>>) -> List<&2, Server>:
  match entries:
    case Nil{}: Nil{}
    case Plan.Located{server, _} <> rest: server <> values(Server, rest)

def payloads(-Server: Data, result: Result<&2, &2, Plan.Error, List<&2, Plan.Located<Server>>>) -> Result<&2, &2, Plan.Error, List<&2, Server>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entries}: Done{values(Server, entries)}

# Reference acceptance domain, independent of the assigned position metadata.
def accepted(-Server: Data, +servers: List<&2, Server>) -> Result<&2, &2, Plan.Error, List<&2, Server>>:
  match servers:
    case Nil{}: Fail{Plan.NoServers{}}
    case _ <> Nil{}: Done{servers}
    case _ <> _ <> Nil{}: Done{servers}
    case _ <> _ <> _ <> Nil{}: Done{servers}
    case _ <> _ <> _ <> _ <> _: Fail{Plan.TooManyServers{}}

law assignment_preserves_payloads:
  for -Server: Data
  for +servers: List<&2, Server>
  {payloads(Server, Plan.locate(Server, servers)) == accepted(Server, servers) : Result<&2, &2, Plan.Error, List<&2, Server>>}

law timing_preserves_identity:
  for -Server: Data
  for +server: Server
  for +position: Timeout.Position
  for +duration: Timeout.Duration
  {Plan.timed(Server, server, position, Done{duration}) == Done{Plan.Attempt{server, position, duration}} : Result<&2, &2, Plan.Error, Plan.Attempt<Server>>}

law invalid_layout_stops_preparation:
  for -Server: Data
  for timeout: U32
  for +error: Plan.Error
  {Plan.located(Server, timeout, Fail{error}) == Fail{error} : Result<&2, &2, Plan.Error, List<&2, Plan.Attempt<Server>>>}


# Dns udp schedule

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


# Dns udp timeout

def isPositive(value: Nat) -> Bool:
  match value:
    case Zero{}: False{}
    case Succ{_}: True{}

law duration_positive:
  for duration: Timeout.Duration
  {isPositive(Timeout.seconds(duration)) == True{} : Bool}

law positive_preserved:
  for +additional: Nat
  {Timeout.seconds(Timeout.positive(Succ{additional})) == Succ{additional} : Nat}

law zero_floor:
  {Timeout.seconds(Timeout.positive(Zero{})) == Succ{Zero{}} : Nat}

law first_server_undivided:
  for +timeout: U32
  {Timeout.scaled(timeout, Timeout.First{}) == timeout : U32}

law two_servers_equal_budgets:
  for +timeout: U32
  {Timeout.budget(timeout, Timeout.SecondOfTwo{}) == Timeout.budget(timeout, Timeout.First{}) : Result<&2, &2, Timeout.UdpTimeoutError, Timeout.Duration>}

law oversized_duration_rejected:
  for extra: Nat
  {Timeout.milliseconds(Timeout.Duration{Nat.add(40n, extra)}) == Fail{Timeout.OutOfRange{}} : Result<&2, &2, Timeout.MillisecondsError, U32>}

import Base
import ./socket.bend as Connect
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./hosts.bend as Hosts
import ./dns-resolver.bend as DNS
import ./url.bend as IPv4
import ./url.bend as IPv6
import ./list-interleave.bend as Interleave

type Error<-Reason: Data> is Data:
  SocketFailure{code: U32, message: String}
  TimedOut{}
  Aborted{reason: Abort.AbortReason<Reason>}
  UnexpectedDefaultAbort{}

def timedError(-Reason: Data, error: Connect.Error<Deadline.Cause<Reason>>) -> Error<Reason>:
  match error:
    case Connect.SocketError{code, message}: SocketFailure{code, message}
    case Connect.Aborted{Abort.Supplied{Deadline.Expired{}}}: TimedOut{}
    case Connect.Aborted{Abort.Supplied{Deadline.ParentAbort{reason}}}: Aborted{reason}
    case Connect.Aborted{Abort.DefaultAbort{}}: UnexpectedDefaultAbort{}

def plainError(-Reason: Data, error: Connect.Error<Reason>) -> Error<Reason>:
  match error:
    case Connect.SocketError{code, message}: SocketFailure{code, message}
    case Connect.Aborted{reason}: Aborted{reason}

def timedAttemptResult(-Reason: Data, -Value: Type, result: Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Value>) -> Result<&2, &1, Error<Reason>, Value>:
  match result:
    case Fail{error}: Fail{timedError(Reason, error)}
    case Done{value}: Done{value}

def plain(-Reason: Data, -Value: Type, result: Result<&2, &1, Connect.Error<Reason>, Value>) -> Result<&2, &1, Error<Reason>, Value>:
  match result:
    case Fail{error}: Fail{plainError(Reason, error)}
    case Done{value}: Done{value}

type Mode is Data:
  NonFinal{}
  Final{}

type ProgressError<-Reason: Data> is Data:
  ProgressNoAddresses{}
  Exhausted{}
  ProgressAborted{reason: Abort.AbortReason<Reason>}
  ProgressUnexpectedDefaultAbort{}

type Decision<-Reason: Data> is Data:
  Accept{}
  Advance{}
  Stop{error: ProgressError<Reason>}

def mode(-Address: Data, remaining: List<&2, Address>) -> Mode:
  match remaining:
    case Nil{}: Final{}
    case _ <> _: NonFinal{}

# Only ordinary socket errors and expiry permit fallback. A retained parent
# abort wins even over a successful connector, at this observation boundary.
def decide(-Reason: Data, outcome: Result<&2, &2, Error<Reason>, Unit>, parent: Maybe<&2, Abort.AbortReason<Reason>>) -> Decision<Reason>:
  match outcome parent:
    case _ Some{reason}: Stop{ProgressAborted{reason}}
    case Done{_} None{}: Accept{}
    case Fail{SocketFailure{_, _}} None{}: Advance{}
    case Fail{TimedOut{}} None{}: Advance{}
    case Fail{Aborted{reason}} None{}: Stop{ProgressAborted{reason}}
    case Fail{UnexpectedDefaultAbort{}} None{}: Stop{ProgressUnexpectedDefaultAbort{}}

# Produce a duplicable observation without copying the owned success value.
def observedProgress(-Reason: Data, -Value: Type, result: Result<&2, &1, Error<Reason>, Value>) -> Result<&2, &1, Error<Reason>, Value> & Result<&2, &2, Error<Reason>, Unit>:
  match result:
    case Done{value}: (Done{value}, Done{Unit{}})
    case Fail{+error}: (Fail{error}, Fail{error})

type AttemptReport<-Reason: Data, -Value: Type> is Type:
  AttemptReport{result: Result<&2, &1, Error<Reason>, Value>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

def scoped(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Abort.AbortSignal<Deadline.Cause<Reason>> -> IO(Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Value>), context: Context, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(AttemptReport<Reason, Value>):
  match pair:
    case (scope, signal):
      do IO<AttemptReport<Reason, Value>>:
        result : Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Value> <- connect(context, signal)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return AttemptReport{timedAttemptResult(Reason, Value, result), reason}

# The connector must settle all work borrowed from the child signal before
# returning. Close joins the deadline's tasks before exposing the affine value.
# Late expiry is retained as a diagnostic, not substituted for a settled result.
def timedWith(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Abort.AbortSignal<Deadline.Cause<Reason>> -> IO(Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Value>), context: Context, parent: Abort.AbortSignal<Reason>, milliseconds: U32) -> IO(AttemptReport<Reason, Value>):
  do IO<AttemptReport<Reason, Value>>:
    scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
    scoped(~Context, ~Reason, ~Value, ~connect, context, Deadline.borrow(Reason, scope))

# Final attempts borrow the parent directly and allocate no family timer.
def finalWith(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Abort.AbortSignal<Reason> -> IO(Result<&2, &1, Connect.Error<Reason>, Value>), context: Context, parent: Abort.AbortSignal<Reason>) -> IO(AttemptReport<Reason, Value>):
  do IO<AttemptReport<Reason, Value>>:
    result : Result<&2, &1, Connect.Error<Reason>, Value> <- connect(context, parent)
    return AttemptReport{plain(Reason, Value, result), None{}}

type Endpoint is Data:
  Endpoint{address: Connect.Address, port: U32}

def openAttempt(~Reason: Data, endpoint: Endpoint, signal: Abort.AbortSignal<Reason>) -> IO(Result<&2, &1, Connect.Error<Reason>, Socket>):
  match endpoint:
    case Endpoint{address, port}: Connect.connect(Reason, address, port, signal)

def timed(~Reason: Data, address: Connect.Address, port: U32, parent: Abort.AbortSignal<Reason>, milliseconds: U32) -> IO(AttemptReport<Reason, Socket>):
  timedWith(~Endpoint, ~Reason, ~Socket, ~openAttempt(~Deadline.Cause<Reason>), Endpoint{address, port}, parent, milliseconds)

def final(~Reason: Data, address: Connect.Address, port: U32, parent: Abort.AbortSignal<Reason>) -> IO(AttemptReport<Reason, Socket>):
  finalWith(~Endpoint, ~Reason, ~Socket, ~openAttempt(~Reason), Endpoint{address, port}, parent)

type Entry<-Reason: Data> is Data:
  Entry{address: Connect.Address, mode: Mode, outcome: Result<&2, &2, Error<Reason>, Unit>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

type Report<-Reason: Data, -Value: Type> is Type:
  Report{result: Result<&2, &1, ProgressError<Reason>, Value>, attempts: List<&2, Entry<Reason>>}

type State<-Reason: Data, -Value: Type> is Type:
  Active{reversed: List<&2, Entry<Reason>>}
  Finished{report: Report<Reason, Value>}

def finish(-Reason: Data, -Value: Type, result: Result<&2, &1, ProgressError<Reason>, Value>, reversed: List<&2, Entry<Reason>>) -> Report<Reason, Value>:
  Report{result, List.reverse(&2, Entry<Reason>, reversed)}

def empty(-Reason: Data, -Value: Type, history: List<&2, Entry<Reason>>) -> Report<Reason, Value>:
  match history:
    case Nil{}: finish(Reason, Value, Fail{ProgressNoAddresses{}}, Nil{})
    case first <> rest: finish(Reason, Value, Fail{Exhausted{}}, first <> rest)

# The connector closes all borrowed tasks before returning. Release consumes
# an owned success rejected by the parent-cancellation observation boundary.
def settle(~Reason: Data, ~Value: Type, ~release: Value -> IO(Unit), history: List<&2, Entry<Reason>>, result: Result<&2, &1, Error<Reason>, Value>, decision: Decision<Reason>) -> IO(State<Reason, Value>):
  match result decision:
    case Done{value} Accept{}: IO.pure(State<Reason, Value>, Finished{finish(Reason, Value, Done{value}, history)})
    case Done{value} Stop{error}:
      do IO<State<Reason, Value>>:
        release(value)
        return Finished{finish(Reason, Value, Fail{error}, history)}
    case Fail{_} Stop{error}: IO.pure(State<Reason, Value>, Finished{finish(Reason, Value, Fail{error}, history)})
    case Fail{_} Advance{}: IO.pure(State<Reason, Value>, Active{history})
    case Done{value} Advance{}:
      do IO<State<Reason, Value>>:
        release(value)
        IO.die(State<Reason, Value>, 1, "invalid connection decision")
    case Fail{_} Accept{}: IO.die(State<Reason, Value>, 1, "invalid connection decision")

def observed(~Reason: Data, ~Value: Type, ~release: Value -> IO(Unit), parent: Abort.AbortSignal<Reason>, address: Connect.Address, mode: Mode, history: List<&2, Entry<Reason>>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>, pair: Result<&2, &1, Error<Reason>, Value> & Result<&2, &2, Error<Reason>, Unit>) -> IO(State<Reason, Value>):
  match pair:
    case (result, +outcome):
      do IO<State<Reason, Value>>:
        reason : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, parent)
        settle(~Reason, ~Value, ~release, Entry{address, mode, outcome, deadline} <> history, result, decide(Reason, outcome, reason))

def completed(~Reason: Data, ~Value: Type, ~release: Value -> IO(Unit), parent: Abort.AbortSignal<Reason>, address: Connect.Address, mode: Mode, history: List<&2, Entry<Reason>>, report: AttemptReport<Reason, Value>) -> IO(State<Reason, Value>):
  match report:
    case AttemptReport{result, deadline}: observed(~Reason, ~Value, ~release, parent, address, mode, history, deadline, observedProgress(Reason, Value, result))

def checked(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Connect.Address -> Mode -> Abort.AbortSignal<Reason> -> IO(AttemptReport<Reason, Value>), ~release: Value -> IO(Unit), context: Context, +parent: Abort.AbortSignal<Reason>, +address: Connect.Address, +mode: Mode, history: List<&2, Entry<Reason>>, reason: Maybe<&2, Abort.AbortReason<Reason>>) -> IO(State<Reason, Value>):
  match reason:
    case Some{why}: IO.pure(State<Reason, Value>, Finished{finish(Reason, Value, Fail{ProgressAborted{why}}, history)})
    case None{}:
      do IO<State<Reason, Value>>:
        report : AttemptReport<Reason, Value> <- connect(context, address, mode, parent)
        completed(~Reason, ~Value, ~release, parent, address, mode, history, report)

def exhausted(-Reason: Data, -Value: Type, history: List<&2, Entry<Reason>>, reason: Maybe<&2, Abort.AbortReason<Reason>>) -> Report<Reason, Value>:
  match reason:
    case Some{why}: finish(Reason, Value, Fail{ProgressAborted{why}}, history)
    case None{}: empty(Reason, Value, history)

# Recursion consumes exactly one list cell per call. State cannot add addresses
# or restart earlier attempts, and Finished stops before inspecting the tail.
def drive(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Connect.Address -> Mode -> Abort.AbortSignal<Reason> -> IO(AttemptReport<Reason, Value>), ~release: Value -> IO(Unit), +context: Context, +parent: Abort.AbortSignal<Reason>, remaining: List<&2, Connect.Address>, state: State<Reason, Value>) -> IO(Report<Reason, Value>):
  match remaining state:
    case _ Finished{report}: IO.pure(Report<Reason, Value>, report)
    case Nil{} Active{history}:
      do IO<Report<Reason, Value>>:
        reason : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, parent)
        return exhausted(Reason, Value, history, reason)
    case first <> +rest Active{history}:
      do IO<Report<Reason, Value>>:
        reason : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, parent)
        next : State<Reason, Value> <- checked(~Context, ~Reason, ~Value, ~connect, ~release, context, parent, first, mode(Connect.Address, rest), history, reason)
        drive(~Context, ~Reason, ~Value, ~connect, ~release, context, parent, rest, next)

# Address order is supplied by connection-order. History describes connector
# outcomes; cancellation can reject success before ownership is handed off.
def runWith(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Connect.Address -> Mode -> Abort.AbortSignal<Reason> -> IO(AttemptReport<Reason, Value>), ~release: Value -> IO(Unit), context: Context, addresses: List<&2, Connect.Address>, parent: Abort.AbortSignal<Reason>) -> IO(Report<Reason, Value>):
  drive(~Context, ~Reason, ~Value, ~connect, ~release, context, parent, addresses, Active{Nil{}})

type Options is Data:
  Options{port: U32, attemptMilliseconds: U32}

def open(~Reason: Data, options: Options, address: Connect.Address, mode: Mode, parent: Abort.AbortSignal<Reason>) -> IO(AttemptReport<Reason, Socket>):
  match options mode:
    case Options{port, milliseconds} NonFinal{}: timed(~Reason, address, port, parent, milliseconds)
    case Options{port, _} Final{}: final(~Reason, address, port, parent)

def run(~Reason: Data, options: Options, addresses: List<&2, Connect.Address>, parent: Abort.AbortSignal<Reason>) -> IO(Report<Reason, Socket>):
  runWith(~Options, ~Reason, ~Socket, ~open(~Reason), ~Socket.close, options, addresses, parent)

# Hosts order is already one sequence. DNS families remain separate until the
# connection scheduler explicitly chooses its interleaving/preference policy.
type Candidates is Data:
  Ordered{first: Connect.Address, rest: List<&2, Connect.Address>}
  Paired{ipv4: List<&2, Connect.Address>, ipv6: List<&2, Connect.Address>}

type Plan<-Report: Data> is Data:
  NoAddresses{report: Report}
  Addresses{report: Report, candidates: Candidates}

def ordered(-Report: Data, report: Report, addresses: List<&2, Connect.Address>) -> Plan<Report>:
  match addresses:
    case Nil{}: NoAddresses{report}
    case first <> rest: Addresses{report, Ordered{first, rest}}

def paired(-Report: Data, report: Report, ipv4: List<&2, Connect.Address>, ipv6: List<&2, Connect.Address>) -> Plan<Report>:
  match ipv4 ipv6:
    case Nil{} Nil{}: NoAddresses{report}
    case first <> rest other: Addresses{report, Paired{first <> rest, other}}
    case Nil{} first <> rest: Addresses{report, Paired{Nil{}, first <> rest}}

def local(address: Hosts.Address) -> Connect.Address:
  match address:
    case Hosts.V4{value}: Connect.V4{value}
    case Hosts.V6{value}: Connect.V6{value, 0}

def host(entry: Hosts.Entry<Hosts.Address>) -> Connect.Address:
  match entry:
    case Hosts.Entry{address, _, _}: local(address)

def hosts(entries: List<&2, Hosts.Entry<Hosts.Address>>) -> List<&2, Connect.Address>:
  match entries:
    case Nil{}: Nil{}
    case first <> rest: host(first) <> hosts(rest)

def answer(address: DNS.Address) -> Connect.Address:
  match address:
    case DNS.V4{value, _}: Connect.V4{value}
    case DNS.V6{value, _}: Connect.V6{value, 0}

def answers(addresses: List<&2, DNS.Address>) -> List<&2, Connect.Address>:
  match addresses:
    case Nil{}: Nil{}
    case first <> rest: answer(first) <> answers(rest)

type Preference is Data:
  IPv4First{}
  IPv6First{}

def family(address: Connect.Address) -> Preference:
  match address:
    case Connect.V4{_}: IPv4First{}
    case Connect.V6{_, _}: IPv6First{}

# Address identity is numeric and includes the IPv6 interface scope. Values
# from hosts/DNS are already parsed, so spelling is not a second identity.
def same(left: Connect.Address, right: Connect.Address) -> Bool:
  match left right:
    case Connect.V4{IPv4.Address{a}} Connect.V4{IPv4.Address{b}}: U32.is_eq(a, b)
    case Connect.V6{IPv6.Ipv6Address{a, b, c, d}, scope} Connect.V6{IPv6.Ipv6Address{w, x, y, z}, other}: U32.is_eq(a, w) && U32.is_eq(b, x) && U32.is_eq(c, y) && U32.is_eq(d, z) && U32.is_eq(scope, other)
    case _ _: False{}

def contains(addresses: List<&2, Connect.Address>, +address: Connect.Address) -> Bool:
  match addresses:
    case Nil{}: False{}
    case first <> rest: same(first, address) || contains(rest, address)

type Groups is Data:
  Groups{ipv4: List<&2, Connect.Address>, ipv6: List<&2, Connect.Address>}

def added(seen: Bool, address: Connect.Address, group: List<&2, Connect.Address>) -> List<&2, Connect.Address>:
  match seen:
    case True{}: group
    case False{}: address <> group

def insert(address: Connect.Address, groups: Groups) -> Groups:
  match address groups:
    case Connect.V4{+value} Groups{+ipv4, ipv6}: Groups{added(contains(ipv4, Connect.V4{value}), Connect.V4{value}, ipv4), ipv6}
    case Connect.V6{+value, +scope} Groups{ipv4, +ipv6}: Groups{ipv4, added(contains(ipv6, Connect.V6{value, scope}), Connect.V6{value, scope}, ipv6)}

def collect(addresses: List<&2, Connect.Address>, groups: Groups) -> Groups:
  match addresses:
    case Nil{}: groups
    case first <> rest: collect(rest, insert(first, groups))

def orderedAddresses(preference: Preference, groups: Groups) -> List<&2, Connect.Address>:
  match preference groups:
    case IPv4First{} Groups{ipv4, ipv6}: Interleave.interleave(Connect.Address, List.reverse(&2, Connect.Address, ipv4), List.reverse(&2, Connect.Address, ipv6))
    case IPv6First{} Groups{ipv4, ipv6}: Interleave.interleave(Connect.Address, List.reverse(&2, Connect.Address, ipv6), List.reverse(&2, Connect.Address, ipv4))

# Ordered resolver output chooses its first family's preference. Paired output
# has no cross-family order, so the caller must supply that policy explicitly.
# Deduplication applies to attempts only; original resolution reports remain intact.
def prepare(preference: Preference, candidates: Candidates) -> List<&2, Connect.Address>:
  match candidates:
    case Ordered{+first, rest}: orderedAddresses(family(first), collect(first <> rest, Groups{Nil{}, Nil{}}))
    case Paired{ipv4, ipv6}: orderedAddresses(preference, collect(ipv6, collect(ipv4, Groups{Nil{}, Nil{}})))

type PlanReport<-Resolution: Data, -Reason: Data, -Value: Type> is Type:
  Unresolved{resolution: Resolution}
  Attempted{resolution: Resolution, connection: Report<Reason, Value>}

# Preserve the full resolution in both branches. No-address resolution never
# calls the connector. A connection failure retains its complete attempt log.
def executeWith(-Context: Data, -Resolution: Data, -Reason: Data, -Value: Type, connect: Context -> List<&2, Connect.Address> -> IO(Report<Reason, Value>), context: Context, preference: Preference, plan: Plan<Resolution>) -> IO(PlanReport<Resolution, Reason, Value>):
  match plan:
    case NoAddresses{resolution}: IO.pure(PlanReport<Resolution, Reason, Value>, Unresolved{resolution})
    case Addresses{resolution, candidates}:
      do IO<PlanReport<Resolution, Reason, Value>>:
        connection : Report<Reason, Value> <- connect(context, prepare(preference, candidates))
        return Attempted{resolution, connection}

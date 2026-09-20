import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./dns-udp-plan.bend as Plan
import ./dns-udp-schedule.bend as Schedule
import ./dns-udp-servers.bend as UDP
import ./dns-udp-query.bend as Datagram
import ./dns-tcp-query.bend as TCP
import ./dns-tcp-servers.bend as Stream
import ./abortable-connect.bend as Connect
import ./socket-endpoint.bend as Endpoint
import ./dns-query.bend as Request
import ./dns-transport-choice.bend as Choice
import ./dns-edns.bend as Edns

type Error<-Reason: Data> is Data:
  Encoding{error: Edns.Error}
  Datagram{error: UDP.Error<Reason>}
  Stream{error: Stream.Error<Reason>}

type State<-Reason: Data> is Data:
  Complete{result: Result<&2, &2, Error<Reason>, TCP.Reply>}
  Continue{last: Maybe<&2, UDP.Report<Reason>>}
  Fallback{servers: List<&2, Stream.Server>}

def server(value: Endpoint.Endpoint) -> Stream.Server:
  match value:
    case Endpoint.V4{ip, port}: Stream.Server{Connect.V4{ip}, port}
    case Endpoint.V6{ip, port, scope}: Stream.Server{Connect.V6{ip, scope}, port}

def entry(value: Plan.Attempt<Endpoint.Endpoint>) -> Stream.Server:
  match value:
    case Plan.Attempt{endpoint, _, _}: server(endpoint)

def entries(values: List<&2, Plan.Attempt<Endpoint.Endpoint>>) -> List<&2, Stream.Server>:
  match values:
    case Nil{}: Nil{}
    case first <> rest: entry(first) <> entries(rest)

def exhausted(-Reason: Data, result: Result<&2, &2, UDP.Error<Reason>, UDP.Reply>) -> Result<&2, &2, Error<Reason>, TCP.Reply>:
  match result:
    case Fail{error}: Fail{Datagram{error}}
    case Done{_}: Fail{Datagram{UDP.InvalidCursor{}}}

def transitioned(-Reason: Data, selected: Plan.Attempt<Endpoint.Endpoint>, next: Schedule.Cursor<Plan.Attempt<Endpoint.Endpoint>>, decision: UDP.Decision<Reason>) -> State<Reason>:
  match decision:
    case UDP.Next{last}: Continue{last}
    case UDP.Stop{report}: Complete{Fail{Datagram{UDP.Failed{report}}}}
    case UDP.Answer{UDP.Reply{_, Datagram.Answer{message}}}: Complete{Done{TCP.Answer{message}}}
    case UDP.Answer{UDP.Reply{_, Datagram.Truncated{_}}}: Fallback{entries(Schedule.fallback(Plan.Attempt<Endpoint.Endpoint>, selected, next))}

def streamed(-Reason: Data, result: Result<&2, &2, Stream.Error<Reason>, TCP.Reply>) -> Result<&2, &2, Error<Reason>, TCP.Reply>:
  match result:
    case Done{reply}: Done{reply}
    case Fail{error}: Fail{Stream{error}}

# A UDP TC response switches to one TCP pass starting with that exact entry.
# TCP failures may advance only through the rest of this selected pass, never
# wrapping or restarting UDP. Recoverable TCP resets stay in Stream's owner.
def drive(-Reason: Data, fuel: Nat, step: Schedule.Step<Plan.Attempt<Endpoint.Endpoint>>, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Request.Request, +maximum: U32, state: State<Reason>) -> IO(Result<&2, &2, Error<Reason>, TCP.Reply>):
  match fuel step state:
    case _ _ Complete{result}: IO.pure(Result<&2, &2, Error<Reason>, TCP.Reply>, result)
    case _ _ Fallback{servers}:
      do IO<Result<&2, &2, Error<Reason>, TCP.Reply>>:
        result : Result<&2, &2, Stream.Error<Reason>, TCP.Reply> <- Stream.exchangeRequest(Reason, servers, signal, request, maximum)
        return streamed(Reason, result)
    case _ Schedule.Exhausted{} Continue{last}: IO.pure(Result<&2, &2, Error<Reason>, TCP.Reply>, exhausted(Reason, UDP.exhausted(Reason, last)))
    case Zero{} Schedule.Try{_, _} Continue{_}: IO.pure(Result<&2, &2, Error<Reason>, TCP.Reply>, Fail{Datagram{UDP.InvalidCursor{}}})
    case Succ{rest} Schedule.Try{+selected, +next} Continue{_}:
      do IO<Result<&2, &2, Error<Reason>, TCP.Reply>>:
        decision : UDP.Decision<Reason> <- UDP.attempt(Reason, selected, signal, request)
        drive(Reason, rest, Schedule.next(Plan.Attempt<Endpoint.Endpoint>, next), signal, request, maximum, transitioned(Reason, selected, next, decision))

def prepared(-Reason: Data, +attempts: Nat, +servers: List<&2, Plan.Attempt<Endpoint.Endpoint>>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Request.Request, maximum: U32, choice: Result<&2, &2, Edns.Error, Choice.Mode>) -> IO(Result<&2, &2, Error<Reason>, TCP.Reply>):
  match choice:
    case Fail{error}: IO.pure(Result<&2, &2, Error<Reason>, TCP.Reply>, Fail{Encoding{error}})
    case Done{Choice.UDP{}}: drive(Reason, Nat.mul(attempts, List.length(&2, Plan.Attempt<Endpoint.Endpoint>, servers)), Schedule.next(Plan.Attempt<Endpoint.Endpoint>, Schedule.start(Plan.Attempt<Endpoint.Endpoint>, attempts, servers)), signal, request, maximum, Continue{None{}})
    case Done{Choice.TCP{}}: drive(Reason, Zero{}, Schedule.Exhausted{}, signal, request, maximum, Fallback{entries(servers)})

# Forced and oversized requests start with one TCP pass. Zero configured
# attempts never opens a transport, including when TCP is explicitly forced.
def exchangeWith(-Reason: Data, forced: Bool, attempts: Nat, servers: List<&2, Plan.Attempt<Endpoint.Endpoint>>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Request.Request, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, TCP.Reply>):
  match attempts:
    case Zero{}: IO.pure(Result<&2, &2, Error<Reason>, TCP.Reply>, Fail{Datagram{UDP.NoAttempts{}}})
    case count: prepared(Reason, count, servers, signal, request, maximum, Choice.prepare(forced, request))

# Borrow the same total deadline across initial selection, UDP and TCP.
def exchangeRequest(-Reason: Data, attempts: Nat, servers: List<&2, Plan.Attempt<Endpoint.Endpoint>>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Request.Request, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, TCP.Reply>):
  exchangeWith(Reason, False{}, attempts, servers, signal, request, maximum)

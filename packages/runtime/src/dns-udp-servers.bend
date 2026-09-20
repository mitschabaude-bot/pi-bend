import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./dns-udp-attempt-scope.bend as Scope
import ./dns-udp-timeout.bend as Timeout
import ./dns-udp-plan.bend as Plan
import ./dns-udp-schedule.bend as Schedule
import ./dns-udp-query.bend as Query
import ./dns-query.bend as Request
import ./dns-message.bend as Message
import ./dns-udp-policy.bend as Policy
import ./abortable-datagram.bend as Datagram
import ./datagram-peer.bend as Peer
import ./socket-endpoint.bend as Endpoint

type Failure<-Reason: Data> is Data:
  Rejected{header: Message.Header, reason: Policy.Rejection}
  InvalidDestination{}
  InvalidBudget{error: Timeout.MillisecondsError}
  Exchange{error: Query.Error<Deadline.Cause<Deadline.Cause<Reason>>>}

type Report<-Reason: Data> is Data:
  Report{server: Endpoint.Endpoint, failure: Failure<Reason>, deadline: Scope.End<Reason>}

type Reply is Data:
  Reply{server: Endpoint.Endpoint, value: Query.Reply}

type Error<-Reason: Data> is Data:
  NoAttempts{}
  Failed{report: Report<Reason>}
  InvalidCursor{}

type Decision<-Reason: Data> is Data:
  Answer{reply: Reply}
  Next{last: Maybe<&2, Report<Reason>>}
  Stop{report: Report<Reason>}

def expired(-Reason: Data, why: Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>) -> Bool:
  match why:
    case Abort.Supplied{Deadline.Expired{}}: True{}
    case _: False{}

def retryable(-Reason: Data, error: Query.Error<Deadline.Cause<Deadline.Cause<Reason>>>) -> Bool:
  match error:
    case Query.Transport{Datagram.SocketError{_, _}}: True{}
    case Query.Opening{Peer.Association{_, _}}: True{}
    case Query.Aborted{why}: expired(Reason, why)
    case Query.Transport{Datagram.Aborted{why}}: expired(Reason, why)
    case _: False{}

def retry(-Reason: Data, allowed: Bool, report: Report<Reason>) -> Decision<Reason>:
  match allowed:
    case True{}: Next{Some{report}}
    case False{}: Stop{report}

def failed(-Reason: Data, endpoint: Endpoint.Endpoint, +error: Query.Error<Deadline.Cause<Deadline.Cause<Reason>>>, end: Scope.End<Reason>) -> Decision<Reason>:
  match end:
    case Scope.ParentAborted{why}: Stop{Report{endpoint, Exchange{error}, Scope.ParentAborted{why}}}
    case Scope.UnexpectedDefaultAbort{}: Stop{Report{endpoint, Exchange{error}, Scope.UnexpectedDefaultAbort{}}}
    case other: retry(Reason, retryable(Reason, error), Report{endpoint, Exchange{error}, other})

def rejected(-Reason: Data, endpoint: Endpoint.Endpoint, header: Message.Header, reason: Policy.Rejection, end: Scope.End<Reason>) -> Decision<Reason>:
  match end:
    case Scope.ParentAborted{why}: Stop{Report{endpoint, Rejected{header, reason}, Scope.ParentAborted{why}}}
    case Scope.UnexpectedDefaultAbort{}: Stop{Report{endpoint, Rejected{header, reason}, Scope.UnexpectedDefaultAbort{}}}
    case other: Next{Some{Report{endpoint, Rejected{header, reason}, other}}}

def selected(-Reason: Data, endpoint: Endpoint.Endpoint, header: Message.Header, reply: Query.Reply, end: Scope.End<Reason>, decision: Policy.Decision) -> Decision<Reason>:
  match decision:
    case Policy.Retry{reason}: rejected(Reason, endpoint, header, reason, end)
    case _: Answer{Reply{endpoint, reply}}

def responseHeader(reply: Query.Reply) -> Message.Header:
  match reply:
    case Query.Truncated{header}: header
    case Query.Answer{Message.Message{_, header, _, _, _, _}}: header

def answered(-Reason: Data, endpoint: Endpoint.Endpoint, +header: Message.Header, reply: Query.Reply, end: Scope.End<Reason>) -> Decision<Reason>:
  selected(Reason, endpoint, header, reply, end, Policy.header(header, False{}))

# An accepted reply remains a reply even when scope
# closure observes a later expiry. Failed attempts retain cleanup-time reasons.
def completed(-Reason: Data, endpoint: Endpoint.Endpoint, result: Result<&2, &2, Query.Error<Deadline.Cause<Deadline.Cause<Reason>>>, Query.Reply>, end: Scope.End<Reason>) -> Decision<Reason>:
  match result:
    case Done{+reply}: answered(Reason, endpoint, responseHeader(reply), reply, end)
    case Fail{error}: failed(Reason, endpoint, error, end)

def scoped(-Reason: Data, +endpoint: Endpoint.Endpoint, request: Request.Request, pair: Deadline.Scope<Deadline.Cause<Reason>> & Abort.AbortSignal<Deadline.Cause<Deadline.Cause<Reason>>>) -> IO(Decision<Reason>):
  match pair:
    case (scope, signal):
      do IO<Decision<Reason>>:
        result : Result<&2, &2, Query.Error<Deadline.Cause<Deadline.Cause<Reason>>>, Query.Reply> <- Query.exchangeRequest(Deadline.Cause<Deadline.Cause<Reason>>, endpoint, signal, request)
        end : Scope.End<Reason> <- Scope.close(Reason, scope)
        return completed(Reason, endpoint, result, end)

def created(-Reason: Data, endpoint: Endpoint.Endpoint, request: Request.Request, result: Result<&2, &1, Timeout.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>>) -> IO(Decision<Reason>):
  match result:
    case Fail{error}: IO.pure(Decision<Reason>, Stop{Report{endpoint, InvalidBudget{error}, Scope.Active{}}})
    case Done{scope}: scoped(Reason, endpoint, request, Deadline.borrow(Deadline.Cause<Reason>, scope))

def validPort(+port: U32) -> Bool: U32.is_gt(port, 0) && U32.is_le(port, 65535)

def valid(endpoint: Endpoint.Endpoint) -> Bool:
  match endpoint:
    case Endpoint.V4{_, port}: validPort(port)
    case Endpoint.V6{_, port, _}: validPort(port)

def checked(-Reason: Data, valid: Bool, endpoint: Endpoint.Endpoint, duration: Timeout.Duration, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Request.Request) -> IO(Decision<Reason>):
  match valid:
    case False{}: IO.pure(Decision<Reason>, Stop{Report{endpoint, InvalidDestination{}, Scope.Active{}}})
    case True{}:
      do IO<Decision<Reason>>:
        scope : Result<&2, &1, Timeout.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>> <- Scope.create(Reason, duration, signal)
        created(Reason, endpoint, request, scope)

def attempt(-Reason: Data, entry: Plan.Attempt<Endpoint.Endpoint>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Request.Request) -> IO(Decision<Reason>):
  match entry:
    case Plan.Attempt{+endpoint, _, duration}: checked(Reason, valid(endpoint), endpoint, duration, signal, request)

def exhausted(-Reason: Data, last: Maybe<&2, Report<Reason>>) -> Result<&2, &2, Error<Reason>, Reply>:
  match last:
    case None{}: Fail{NoAttempts{}}
    case Some{report}: Fail{Failed{report}}

# The finite bound is the exact initial schedule size, never a packet budget.
# Each recursive step consumes one scheduled attempt; reads retain their own
# unchanged deadline regardless of how many unrelated packets they encounter.
def drive(-Reason: Data, fuel: Nat, step: Schedule.Step<Plan.Attempt<Endpoint.Endpoint>>, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Request.Request, decision: Decision<Reason>) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  match fuel step decision:
    case _ _ Answer{reply}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, Done{reply})
    case _ _ Stop{report}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, Fail{Failed{report}})
    case _ Schedule.Exhausted{} Next{last}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, exhausted(Reason, last))
    case Zero{} Schedule.Try{_, _} Next{_}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, Fail{InvalidCursor{}})
    case Succ{rest} Schedule.Try{entry, next} Next{_}:
      do IO<Result<&2, &2, Error<Reason>, Reply>>:
        result : Decision<Reason> <- attempt(Reason, entry, signal, request)
        drive(Reason, rest, Schedule.next(Plan.Attempt<Endpoint.Endpoint>, next), signal, request, result)

# Entries are already positioned/timed/rotated. Borrow one total deadline and
# reuse the identical request through every attempt. Return the selected server
# with a reply so a later TCP fallback can target that same endpoint.
# Retryable response codes advance this same cursor. Truncation retains the
# selected endpoint for TCP fallback; EDNS negotiation remains above this layer.
def exchangeRequest(-Reason: Data, +attempts: Nat, +servers: List<&2, Plan.Attempt<Endpoint.Endpoint>>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Request.Request) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  drive(Reason, Nat.mul(attempts, List.length(&2, Plan.Attempt<Endpoint.Endpoint>, servers)), Schedule.next(Plan.Attempt<Endpoint.Endpoint>, Schedule.start(Plan.Attempt<Endpoint.Endpoint>, attempts, servers)), signal, request, Next{None{}})

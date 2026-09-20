import Base
import ../packages/runtime/src/dns-udp-servers.bend as Servers
import ../packages/runtime/src/dns-udp-plan.bend as Plan
import ../packages/runtime/src/dns-udp-timeout.bend as Timeout
import ../packages/runtime/src/dns-server-rotation.bend as Rotation
import ../packages/runtime/src/dns-udp-query.bend as Query
import ../packages/runtime/src/dns-query.bend as Request
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-udp-attempt-scope.bend as Attempt
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-udp-query.bend as QueryTest
import ./dns-udp-attempt-scope.bend as ScopeTest

def port(endpoint: Endpoint.Endpoint) -> String:
  match endpoint:
    case Endpoint.V4{_, value}: U32.show(value)
    case Endpoint.V6{_, value, _}: U32.show(value)

def failure(value: Servers.Failure<String>) -> String:
  match value:
    case Servers.InvalidDestination{}: "destination"
    case Servers.InvalidBudget{_}: "budget"
    case Servers.Exchange{error}: QueryTest.outcome(Fail{error})

def outcome(result: Result<&2, &2, Servers.Error<String>, Servers.Reply>) -> String:
  match result:
    case Done{Servers.Reply{server, value}}: port(server) ++ ":" ++ QueryTest.outcome(Done{value})
    case Fail{Servers.NoAttempts{}}: "empty"
    case Fail{Servers.InvalidCursor{}}: "cursor"
    case Fail{Servers.Failed{Servers.Report{server, value, end}}}: port(server) ++ ":" ++ failure(value) ++ ":" ++ ScopeTest.show(end)

def chosen(value: Rotation.Chosen<Plan.Attempt<Endpoint.Endpoint>>) -> List<&2, Plan.Attempt<Endpoint.Endpoint>>:
  match value:
    case Rotation.Chosen{servers, _}: servers

def entries(+mode: String, +first: Endpoint.Endpoint, second: Endpoint.Endpoint, third: Endpoint.Endpoint) -> Result<&2, &2, Plan.Error, List<&2, Plan.Attempt<Endpoint.Endpoint>>>:
  match mode:
    case "empty": Done{Nil{}}
    case "budget": Done{Plan.Attempt{first, Timeout.First{}, Timeout.Duration{40n}} <> Plan.Attempt{second, Timeout.SecondOfTwo{}, Timeout.Duration{0n}} <> Nil{}}
    case "duplicate": Plan.prepare(Endpoint.Endpoint, 1, first <> first <> Nil{})
    case "rotation": Plan.prepare(Endpoint.Endpoint, 2, first <> second <> third <> Nil{})
    case _: Plan.prepare(Endpoint.Endpoint, 1, first <> second <> Nil{})

def total(+mode: String, servers: List<&2, Plan.Attempt<Endpoint.Endpoint>>, pair: Deadline.Scope<String> & Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Unit):
  match pair:
    case (scope, signal):
      do IO<Unit>:
        result : Result<&2, &2, Servers.Error<String>, Servers.Reply> <- Servers.exchangeRequest(String, Bool.pick(Nat, String.eq(mode, "zero"), 0n, 2n), servers, signal, QueryTest.request(mode))
        IO.print(outcome(result))
        ended : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
        return Unit{}

def prepared(+mode: String, result: Result<&2, &2, Plan.Error, List<&2, Plan.Attempt<Endpoint.Endpoint>>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "unexpected plan rejection")
    case Done{servers}:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        ScopeTest.before(mode, controller)
        task : Chan(Unit) <- IO.fork(Unit, ScopeTest.later(mode, controller))
        scope : Deadline.Scope<String> <- Deadline.create(String, Bool.pick(U32, String.eq(mode, "total"), 1200, 7000), Abort.signal(String, controller))
        total(mode, chosen(Rotation.choose(Plan.Attempt<Endpoint.Endpoint>, True{}, Rotation.startAt(Plan.Attempt<Endpoint.Endpoint>, Bool.pick(Nat, String.eq(mode, "rotation"), 1n, 0n), servers))), Deadline.borrow(String, scope))
        IO.join(Unit, task)
        Abort.dispose(String, controller)

def run(+family: U32, first: U32, second: U32, third: U32, +mode: String) -> IO(Unit):
  prepared(mode, entries(mode, QueryTest.destination(family, Bool.pick(U32, String.eq(mode, "port"), 0, first)), QueryTest.destination(family, second), QueryTest.destination(family, third)))

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> first <> second <> third <> mode <> Nil{}: run(Scalar.decimal(family, 0), Scalar.decimal(first, 0), Scalar.decimal(second, 0), Scalar.decimal(third, 0), mode)
    case _: IO.die(Unit, 1, "expected family three ports mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)

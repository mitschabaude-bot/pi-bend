import Base
import ../packages/runtime/src/dns-udp-timeout.bend as Timeout

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
  {Timeout.budget(timeout, Timeout.SecondOfTwo{}) == Timeout.budget(timeout, Timeout.First{}) : Result<&2, &2, Timeout.Error, Timeout.Duration>}

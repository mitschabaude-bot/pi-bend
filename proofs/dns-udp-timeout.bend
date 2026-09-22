import Base
import ../laws/dns-udp-timeout.bend as Laws
import ../packages/runtime/src/resolver-config.bend as Timeout

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

import Base

# Valid original positions in glibc's one-to-three-server configuration.
# Rotation reorders entries, never changes this position metadata.
type Position is Data:
  First{}
  SecondOfTwo{}
  SecondOfThree{}
  ThirdOfThree{}

# Whole seconds, necessarily positive even when retransmission is configured 0.
type Duration is Data:
  Duration{additionalSeconds: Nat}

type Error is Data:
  InvalidTimeout{seconds: U32}

def positive(seconds: Nat) -> Duration:
  match seconds:
    case Zero{}: Duration{Zero{}}
    case Succ{rest}: Duration{rest}

def seconds(duration: Duration) -> Nat:
  match duration:
    case Duration{additional}: Succ{additional}

def scaled(timeout: U32, position: Position) -> U32:
  match position:
    case First{}: timeout
    case SecondOfTwo{}: timeout
    case SecondOfThree{}: (timeout * 2 / 3 : U32)
    case ThirdOfThree{}: (timeout * 4 / 3 : U32)

def checked(valid: Bool, timeout: U32, position: Position) -> Result<&2, &2, Error, Duration>:
  match valid:
    case False{}: Fail{InvalidTimeout{timeout}}
    case True{}: Done{positive(U32.to_nat(scaled(timeout, position)))}

# Resolver option parsing already caps timeout at 30. Reject direct invalid
# values instead of overflowing arithmetic or silently changing caller input.
# Checked values scale to at most 40 seconds, so U32 arithmetic cannot overflow.
def budget(+timeout: U32, position: Position) -> Result<&2, &2, Error, Duration>:
  checked(U32.is_le(timeout, 30), timeout, position)

# Prepared UDP budgets are 1..40 seconds. Validate even manually constructed
# durations before conversion, consuming at most 40 successors of their Nat.
type MillisecondsError is Data:
  OutOfRange{}

def countMilliseconds(fuel: Nat, seconds: Nat, accumulated: U32) -> Result<&2, &2, MillisecondsError, U32>:
  match fuel seconds:
    case _ Zero{}: Done{accumulated}
    case Zero{} Succ{_}: Fail{OutOfRange{}}
    case Succ{rest} Succ{remaining}: countMilliseconds(rest, remaining, (accumulated + 1000 : U32))

def milliseconds(duration: Duration) -> Result<&2, &2, MillisecondsError, U32>:
  countMilliseconds(40n, seconds(duration), 0)

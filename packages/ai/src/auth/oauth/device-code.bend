import Base
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/timer.bend as Timer

# upstream auth/oauth/device-code.ts: RFC 8628 device-code polling. The poll
# is a callback returning one of upstream's poll results; the interval starts
# at the server's (default 5 s, at least 1 s), `slow_down` raises it to the
# server's new interval or by 5 s, and the flow ends at the expiry.

def CANCEL_MESSAGE() -> String: "Login cancelled"

def TIMEOUT_MESSAGE() -> String: "Device flow timed out"

def SLOW_DOWN_TIMEOUT_MESSAGE() -> String: "Device flow timed out after one or more slow_down responses. This is often caused by clock drift in WSL or VM environments. Please sync or restart the VM clock and try again."

def MINIMUM_INTERVAL_MS() -> F64: F.fromU32(1000)

def DEFAULT_POLL_INTERVAL_SECONDS() -> F64: F.fromU32(5)

def SLOW_DOWN_INTERVAL_INCREMENT_MS() -> F64: F.fromU32(5000)

type OAuthDeviceCodePollResult<-A: Data> is Data:
  PollPending{}
  PollSlowDown{intervalSeconds: Maybe<&2, F64>}
  PollFailed{message: String}
  PollComplete{value: A}

type OAuthDeviceCodePollOptions<-A: Data> is Data:
  OAuthDeviceCodePollOptions{intervalSeconds: Maybe<&2, F64>, expiresInSeconds: Maybe<&2, F64>, waitBeforeFirstPoll: Bool, poll: C.Callback<Unit, OAuthDeviceCodePollResult<A>>, signal: Abort.AbortSignal<Unit>}

def thousand() -> F64: F.fromU32(1000)

def atLeastMinimum(+ms: F64) -> F64: F.maximum(MINIMUM_INTERVAL_MS(), ms)

def positive(value: F64) -> Bool: F.isGreater(F.compare(value, F.fromU32(0)))

def finitePositive(+value: F64) -> Bool: Bool.not(F.isNaN(value)) && positive(value) && F.isGreater(F.compare(F.infinity(False{}), value))

def slowedInterval(interval: F64, server: Maybe<&2, F64>) -> F64:
  match server:
    case Some{+seconds}: Bool.pick(Unit -> F64, finitePositive(seconds), _ => atLeastMinimum(F.truncate(F.multiply(seconds, thousand()))), _ => atLeastMinimum(F.add(interval, SLOW_DOWN_INTERVAL_INCREMENT_MS())))(Unit{})
    case None{}: atLeastMinimum(F.add(interval, SLOW_DOWN_INTERVAL_INCREMENT_MS()))

def remaining(+deadline: F64, now: F64) -> F64: F.subtract(deadline, now)

def expired(slowed: Nat) -> String: Bool.pick(String, Nat.is_gt(slowed, 0n), SLOW_DOWN_TIMEOUT_MESSAGE(), TIMEOUT_MESSAGE())

# Waits are whole milliseconds within the native timer range.
def waitMs(+interval: F64, +left: F64) -> U32: F64.to_u32(F.minimum(interval, left))

def sleptOk(result: Result<&2, &2, Abort.AbortReason<Unit>, Unit>) -> Bool:
  match result:
    case Done{_}: True{}
    case Fail{_}: False{}

type Loop<-A: Data> is Data:
  Loop{poll: C.Callback<Unit, OAuthDeviceCodePollResult<A>>, signal: Abort.AbortSignal<Unit>, deadline: F64}

def loopSignal(-A: Data, loop: Loop<A>) -> Abort.AbortSignal<Unit>:
  match loop:
    case Loop{_, signal, _}: signal

def loopDeadline(-A: Data, loop: Loop<A>) -> F64:
  match loop:
    case Loop{_, _, deadline}: deadline

def loopPoll(-A: Data, loop: Loop<A>) -> C.Callback<Unit, OAuthDeviceCodePollResult<A>>:
  match loop:
    case Loop{poll, _, _}: poll

type Drive<-A: Data> is Data:
  Polling{interval: F64, slowed: Nat}
  Waiting{interval: F64, slowed: Nat}
  Finished{result: Result<&2, &2, String, A>}

def afterPoll(-A: Data, +interval: F64, +slowed: Nat, result: OAuthDeviceCodePollResult<A>) -> Drive<A>:
  match result:
    case PollComplete{value}: Finished{Done{value}}
    case PollFailed{message}: Finished{Fail{message}}
    case PollSlowDown{server}: Waiting{slowedInterval(interval, server), 1n + slowed}
    case PollPending{}: Waiting{interval, slowed}

def afterSleep(-A: Data, +interval: F64, +slowed: Nat, slept: Result<&2, &2, Abort.AbortReason<Unit>, Unit>) -> Drive<A>:
  Bool.pick(Drive<A>, sleptOk(slept), Polling{interval, slowed}, Finished{Fail{CANCEL_MESSAGE()}})

def beforePoll(-A: Data, +interval: F64, +slowed: Nat, +deadline: F64, now: F64, aborted: Bool) -> Maybe<&2, Drive<A>>:
  Bool.pick(Maybe<&2, Drive<A>>, Bool.not(F.isGreater(F.compare(deadline, now))), Some{Finished{Fail{expired(slowed)}}}, Bool.pick(Maybe<&2, Drive<A>>, aborted, Some{Finished{Fail{CANCEL_MESSAGE()}}}, None{}))

@unsafe def polledOrStopped(~A: Data, +loop: Loop<A>, +interval: F64, +slowed: Nat, stop: Maybe<&2, Drive<A>>) -> IO(Drive<A>):
  match stop:
    case Some{finished}: IO.pure(Drive<A>, finished)
    case None{}:
      do IO<Drive<A>>:
        result : OAuthDeviceCodePollResult<A> <- C.call(Unit, OAuthDeviceCodePollResult<A>, loopPoll(A, loop), Unit{})
        return afterPoll(A, interval, slowed, result)

@unsafe def drive(~A: Data, +loop: Loop<A>, current: Drive<A>) -> IO(Result<&2, &2, String, A>):
  match current:
    case Finished{result}: IO.pure(Result<&2, &2, String, A>, result)
    case Polling{+interval, +slowed}:
      do IO<Result<&2, &2, String, A>>:
        now : F64 <- Date.now()
        aborted : Bool <- Abort.aborted(Unit, loopSignal(A, loop))
        next : Drive<A> <- polledOrStopped(~A, loop, interval, slowed, beforePoll(A, interval, slowed, loopDeadline(A, loop), now, aborted))
        drive(~A, loop, next)
    case Waiting{+interval, +slowed}:
      do IO<Result<&2, &2, String, A>>:
        now : F64 <- Date.now()
        +left : F64 <- IO.pure(F64, remaining(loopDeadline(A, loop), now))
        Bool.pick(Unit -> IO(Result<&2, &2, String, A>), positive(left), _ =>
          do IO<Result<&2, &2, String, A>>:
            slept : Result<&2, &2, Abort.AbortReason<Unit>, Unit> <- Timer.sleep(Unit, waitMs(interval, left), loopSignal(A, loop))
            drive(~A, loop, afterSleep(A, interval, slowed, slept)), _ => IO.pure(Result<&2, &2, String, A>, Fail{expired(slowed)}))(Unit{})

def deadlineAt(now: F64, expires: Maybe<&2, F64>) -> F64:
  match expires:
    case Some{seconds}: F.add(now, F.multiply(seconds, thousand()))
    case None{}: F.infinity(False{})

# upstream pollOAuthDeviceCodeFlow: the completed value, or the message of
# the error it throws.
def pollOAuthDeviceCodeFlow(~A: Data, options: OAuthDeviceCodePollOptions<A>) -> IO(Result<&2, &2, String, A>):
  match options:
    case OAuthDeviceCodePollOptions{interval, expires, wait, poll, signal}:
      do IO<Result<&2, &2, String, A>>:
        now : F64 <- Date.now()
        +start : F64 <- IO.pure(F64, atLeastMinimum(F.truncate(F.multiply(Maybe.default(&2, F64, interval, DEFAULT_POLL_INTERVAL_SECONDS()), thousand()))))
        drive(~A, Loop{poll, signal, deadlineAt(now, expires)}, Bool.pick(Drive<A>, wait, Waiting{start, 0n}, Polling{start, 0n}))

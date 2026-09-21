import Base
import ./provider-retry.bend as Retry
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/f64-natural.bend as Natural
import ../../../runtime/src/abort.bend as Abort

type Error is Data:
  InvalidRetryCount{cause: Natural.Error}
  InvalidDelayLimit{value: F.F64}

def countValue(value: Result<&2, &2, Natural.Error, Nat>) -> Result<&2, &2, Error, Maybe<&2, Nat>>:
  match value:
    case Fail{cause}: Fail{InvalidRetryCount{cause}}
    case Done{number}: Done{Some{number}}

def count(value: Maybe<&2, F.F64>) -> Result<&2, &2, Error, Maybe<&2, Nat>>:
  match value:
    case None{}: Done{None{}}
    case Some{number}: countValue(Natural.convert(number))

def delayChecked(value: F.F64, valid: Bool) -> Result<&2, &2, Error, Maybe<&2, F.F64>>:
  match valid:
    case False{}: Fail{InvalidDelayLimit{value}}
    case True{}: Done{Some{value}}

def nonnegative(comparison: Maybe<&2, Cmp>) -> Bool:
  match comparison:
    case Some{EQ{}}: True{}
    case Some{GT{}}: True{}
    case _: False{}

def finite(value: F.Decoded) -> Bool:
  match value:
    case F.Finite{_, _, _}: True{}
    case _: False{}

def delay(value: Maybe<&2, F.F64>) -> Result<&2, &2, Error, Maybe<&2, F.F64>>:
  match value:
    case None{}: Done{None{}}
    case Some{+number}: delayChecked(number, finite(F.decode(number)) && nonnegative(F.compare(number, F.fromU32(0))))

def completed(-Reason: Data, retries: Maybe<&2, Nat>, signal: Maybe<&2, Abort.AbortSignal<Reason>>, value: Result<&2, &2, Error, Maybe<&2, F.F64>>) -> Result<&2, &2, Error, Retry.ProviderRetryOptions<Reason>>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{limit}: Done{Retry.ProviderRetryOptions{retries, limit, signal}}

def counted(-Reason: Data, limit: Maybe<&2, F.F64>, signal: Maybe<&2, Abort.AbortSignal<Reason>>, value: Result<&2, &2, Error, Maybe<&2, Nat>>) -> Result<&2, &2, Error, Retry.ProviderRetryOptions<Reason>>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{retries}: completed(Reason, retries, signal, delay(limit))

# Preserve absent values for the existing retry defaults (zero retries and a
# 60-second server-delay limit). Zero disables the delay cap; finite fractional
# delay limits remain meaningful. Invalid configuration is a typed failure.
def resolve(-Reason: Data, retries: Maybe<&2, F.F64>, limit: Maybe<&2, F.F64>, signal: Maybe<&2, Abort.AbortSignal<Reason>>) -> Result<&2, &2, Error, Retry.ProviderRetryOptions<Reason>>:
  counted(Reason, limit, signal, count(retries))

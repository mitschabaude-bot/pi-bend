import Base
import ../types.bend as T
import ./provider-retry.bend as Retry
import ../../../runtime/src/callback.bend as C

# Payload and response hooks surround the retry loop. All supplied callbacks
# are borrowed; the only locally owned callback is the fixed-payload bridge.
type Error<-E: Data> is Data:
  PayloadFailure{cause: E}
  RequestFailure{cause: Retry.RetryFailure<E>}
  ResponseFailure{cause: E, cleanup: Result<&2, &2, E, Unit>}

def selected(-P: Data, -E: Data, original: P, result: Result<&2, &2, E, Maybe<&2, P>>) -> Result<&2, &2, Error<E>, P>:
  match result:
    case Fail{cause}: Fail{PayloadFailure{cause}}
    case Done{None{}}: Done{original}
    case Done{Some{value}}: Done{value}

def payload(-P: Data, -M: Data, -E: Data, +original: P, model: M, hook: Maybe<&2, T.PayloadCallback(P, M, E)>) -> IO(Result<&2, &2, Error<E>, P>):
  match hook:
    case None{}: IO.pure(Result<&2, &2, Error<E>, P>, Done{original})
    case Some{callback}:
      do IO<Result<&2, &2, Error<E>, P>>:
        result : Result<&2, &2, E, Maybe<&2, P>> <- C.call(T.PayloadInput<P, M>, Result<&2, &2, E, Maybe<&2, P>>, callback, T.PayloadInput{original, model})
        return selected(P, E, original, result)

def responseResult(-E: Data, -Owner: Type, release: Owner -> IO(Result<&2, &2, E, Unit>), owner: Owner, result: Result<&2, &2, E, Unit>) -> IO(Result<&2, &1, Error<E>, Owner>):
  match result:
    case Done{_}: IO.pure(Result<&2, &1, Error<E>, Owner>, Done{owner})
    case Fail{cause}:
      do IO<Result<&2, &1, Error<E>, Owner>>:
        cleanup : Result<&2, &2, E, Unit> <- release(owner)
        return Fail{ResponseFailure{cause, cleanup}}

def observed(-M: Data, -E: Data, -Owner: Type, model: M, hook: T.ResponseCallback(M, E), release: Owner -> IO(Result<&2, &2, E, Unit>), pair: Owner & T.ProviderResponse) -> IO(Result<&2, &1, Error<E>, Owner>):
  match pair:
    case (owner, metadata):
      do IO<Result<&2, &1, Error<E>, Owner>>:
        result : Result<&2, &2, E, Unit> <- C.call(T.ResponseInput<M>, Result<&2, &2, E, Unit>, hook, T.ResponseInput{metadata, model})
        responseResult(E, Owner, release, owner, result)

def response(-M: Data, -E: Data, -Owner: Type, model: M, hook: Maybe<&2, T.ResponseCallback(M, E)>, inspect: Owner -> Owner & T.ProviderResponse, release: Owner -> IO(Result<&2, &2, E, Unit>), result: Result<&2, &1, Retry.RetryFailure<E>, Owner>) -> IO(Result<&2, &1, Error<E>, Owner>):
  match hook result:
    case _ Fail{cause}: IO.pure(Result<&2, &1, Error<E>, Owner>, Fail{RequestFailure{cause}})
    case None{} Done{owner}: IO.pure(Result<&2, &1, Error<E>, Owner>, Done{owner})
    case Some{callback} Done{owner}: observed(M, E, Owner, model, callback, release, inspect(owner))

type Environment<-P: Data, -E: Data, -Owner: Type> is Data:
  Environment{payload: P, request: C.Callback<P, Result<&2, &1, Retry.RequestFailure<E>, Owner>>}

def invoke(-P: Data, -E: Data, -Owner: Type, environment: Environment<P, E, Owner>, unused: Unit) -> IO(Result<&2, &1, Retry.RequestFailure<E>, Owner>):
  match environment:
    case Environment{value, request}: C.call(P, Result<&2, &1, Retry.RequestFailure<E>, Owner>, request, value)

def prepared(~Reason: Data, ~P: Data, ~M: Data, ~E: Data, ~Owner: Type, model: M, responseHook: Maybe<&2, T.ResponseCallback(M, E)>, request: C.Callback<P, Result<&2, &1, Retry.RequestFailure<E>, Owner>>, effects: Retry.Effects<Reason>, options: Retry.ProviderRetryOptions<Reason>, inspect: Owner -> Owner & T.ProviderResponse, release: Owner -> IO(Result<&2, &2, E, Unit>), value: Result<&2, &2, Error<E>, P>) -> IO(Result<&2, &1, Error<E>, Owner>):
  match value:
    case Fail{cause}: IO.pure(Result<&2, &1, Error<E>, Owner>, Fail{cause})
    case Done{preparedPayload}:
      do IO<Result<&2, &1, Error<E>, Owner>>:
        +bridge : C.Callback<Unit, Result<&2, &1, Retry.RequestFailure<E>, Owner>> <- C.create(~Environment<P, E, Owner>, ~Unit, ~Result<&2, &1, Retry.RequestFailure<E>, Owner>, ~(invoke(P, E, Owner)), Environment{preparedPayload, request})
        result : Result<&2, &1, Retry.RetryFailure<E>, Owner> <- Retry.retryProviderRequestOwned(Reason, E, Owner, bridge, effects, options)
        C.dispose(Unit, Result<&2, &1, Retry.RequestFailure<E>, Owner>, bridge)
        response(M, E, Owner, model, responseHook, inspect, release, result)

# A replacement payload is chosen once, including explicit null/zero values.
# Hook failures never re-enter request retries. On response-hook failure, the
# acquired owner is retired before returning both primary and cleanup results.
def run(~Reason: Data, ~P: Data, ~M: Data, ~E: Data, ~Owner: Type, +model: M, payloadValue: P, payloadHook: Maybe<&2, T.PayloadCallback(P, M, E)>, responseHook: Maybe<&2, T.ResponseCallback(M, E)>, request: C.Callback<P, Result<&2, &1, Retry.RequestFailure<E>, Owner>>, effects: Retry.Effects<Reason>, options: Retry.ProviderRetryOptions<Reason>, inspect: Owner -> Owner & T.ProviderResponse, release: Owner -> IO(Result<&2, &2, E, Unit>)) -> IO(Result<&2, &1, Error<E>, Owner>):
  do IO<Result<&2, &1, Error<E>, Owner>>:
    value : Result<&2, &2, Error<E>, P> <- payload(P, M, E, payloadValue, model, payloadHook)
    prepared(~Reason, ~P, ~M, ~E, ~Owner, model, responseHook, request, effects, options, inspect, release, value)

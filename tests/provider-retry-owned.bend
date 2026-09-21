import Base
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/test/provider-retry.bend as Reference
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/test/utf8-runner.bend as Text

type Environment is Data:
  Environment{port: U32, counter: R.Ref<U32>, configuration: Reference.Config}

def attempted(fail: Bool, error: Retry.RequestFailure<String>, socket: Socket) -> IO(Result<&2, &1, Retry.RequestFailure<String>, Socket>):
  match fail:
    case True{}:
      do IO<Result<&2, &1, Retry.RequestFailure<String>, Socket>>:
        Socket.close(socket)
        IO.print("attempt-close")
        return Fail{error}
    case False{}:
      do IO<Result<&2, &1, Retry.RequestFailure<String>, Socket>>:
        IO.print("acquired")
        return Done{socket}

def requestBody(environment: Environment, unused: Unit) -> IO(Result<&2, &1, Retry.RequestFailure<String>, Socket>):
  match environment:
    case Environment{port, counter, Reference.Config{failures, _, error, _, _, _}}:
      do IO<Result<&2, &1, Retry.RequestFailure<String>, Socket>>:
        count : U32 <- R.modify(U32, U32, counter, value => Reference.next(value))
        IO.print("request")
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        attempted(U32.is_lt(count, failures), error, socket)

def sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (socket, Done{_}):
      do IO<Unit>:
        Socket.close(socket)
        IO.print("done ok")
    case (socket, Fail{_}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "successful retry owner was not writable")

def finished(value: Result<&2, &1, Retry.RetryFailure<String>, Socket>) -> IO(Unit):
  match value:
    case Fail{cause}: Reference.show(Fail{cause})
    case Done{socket}:
      do IO<Unit>:
        pair : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(socket, "owned")
        sent(pair)

def run(port: U32, +configuration: Reference.Config) -> IO(Unit):
  match configuration:
    case Reference.Config{_, retries, _, cap, aborted, abortSleep}:
      do IO<Unit>:
        +counter : R.Ref<U32> <- R.new(U32, 0)
        +controller : A.AbortController<String> <- A.new(String)
        Reference.preAbort(aborted, controller)
        +request : C.Callback<Unit, Result<&2, &1, Retry.RequestFailure<String>, Socket>> <- C.create(~Environment, ~Unit, ~Result<&2, &1, Retry.RequestFailure<String>, Socket>, ~requestBody, Environment{port, counter, configuration})
        +random : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Reference.randomBody, Unit{})
        +date : C.Callback<String, F.F64> <- C.create(~Unit, ~String, ~F.F64, ~Reference.dateBody, Unit{})
        +now : C.Callback<Unit, F.F64> <- C.create(~Unit, ~Unit, ~F.F64, ~Reference.nowBody, Unit{})
        +sleep : C.Callback<Retry.SleepInput<String>, Result<&2, &2, Retry.SleepError, Unit>> <- C.create(~Bool, ~Retry.SleepInput<String>, ~Result<&2, &2, Retry.SleepError, Unit>, ~Reference.sleepBody, abortSleep)
        result : Result<&2, &1, Retry.RetryFailure<String>, Socket> <- Retry.retryProviderRequestOwned(String, String, Socket, request, Retry.Effects{random, date, now, sleep}, Retry.ProviderRetryOptions{retries, cap, Some{A.signal(String, controller)}})
        finished(result)
        C.dispose(Unit, Result<&2, &1, Retry.RequestFailure<String>, Socket>, request)
        C.dispose(Unit, F.F64, random)
        C.dispose(String, F.F64, date)
        C.dispose(Unit, F.F64, now)
        C.dispose(Retry.SleepInput<String>, Result<&2, &2, Retry.SleepError, Unit>, sleep)
        count : U32 <- R.dispose(U32, counter)
        A.dispose(String, controller)
        return Unit{}

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case port <> mode <> Nil{}: run(Text.decimal(port, 0), Reference.config(Text.decimal(mode, 0)))
    case _: IO.die(Unit, 1, "expected port and mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

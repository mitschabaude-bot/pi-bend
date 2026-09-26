import Base
import ../src/api/google-generative-ai-client.bend as Client
import ../src/utils/provider-retry.bend as Retry
import ./anthropic-harness.bend as A
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/ref.bend as Ref

# pi-mono f07218c4d packages/ai/test/google-shared-retry.test.ts. An SDK
# ApiError carries a status but no headers; the fake request fails with such
# errors before succeeding. upstream advances fake timers over the first
# backoff (at most 500 ms); natively the backoff sleeps in real time.
type Script is Data:
  Script{calls: Nat, failures: Nat, status: U32}

def googleApiError(+status: U32) -> Retry.RequestFailure<U32>:
  Retry.Provider{Retry.ProviderError{status, "got status: " ++ U32.show(status), Some{F.fromU32(status)}, None{}, None{}, None{}}}

def step(script: Script) -> Script & Result<&2, &1, Retry.RequestFailure<U32>, String>:
  match script:
    case Script{calls, 0n, status}: (Script{1n + calls, 0n, status}, Done{"ok"})
    case Script{calls, 1n+left, +status}: (Script{1n + calls, left, status}, Fail{googleApiError(status)})

def request(script: Ref.Ref<Script>, unused: Unit) -> IO(Result<&2, &1, Retry.RequestFailure<U32>, String>):
  Ref.modify(Script, Result<&2, &1, Retry.RequestFailure<U32>, String>, script, step)

def callsOf(script: Script) -> Nat:
  match script:
    case Script{calls, _, _}: calls

def resolved(result: Result<&2, &2, Retry.OptionsError, Retry.ProviderRetryOptions<Unit>>) -> Retry.ProviderRetryOptions<Unit>:
  match result:
    case Done{value}: value
    case Fail{_}: Retry.ProviderRetryOptions{None{}, None{}, None{}}

def options(retries: Maybe<&2, F64>) -> Retry.ProviderRetryOptions<Unit>: resolved(Retry.resolve(Unit, retries, None{}, None{}))

type Result_ is Data:
  Result_{value: Maybe<&2, String>, status: Maybe<&2, U32>, calls: Nat}

def outcome(result: Result<&2, &1, Client.GoogleRetryError<U32>, String>, calls: Nat) -> Result_:
  match result:
    case Done{value}: Result_{Some{value}, None{}, calls}
    case Fail{Client.RetryFailed{Retry.RequestFailed{Retry.Provider{Retry.ProviderError{status, _, _, _, _, _}}}}}: Result_{None{}, Some{status}, calls}
    case Fail{_}: Result_{None{}, None{}, calls}

def retried(failures: Nat, status: U32, retries: Maybe<&2, F64>) -> IO(Result_):
  do IO<Result_>:
    +script : Ref.Ref<Script> <- Ref.new(Script, Script{0n, failures, status})
    +call : C.Callback<Unit, Result<&2, &1, Retry.RequestFailure<U32>, String>> <- C.create(~Ref.Ref<Script>, ~Unit, ~Result<&2, &1, Retry.RequestFailure<U32>, String>, ~request, script)
    result : Result<&2, &1, Client.GoogleRetryError<U32>, String> <- Client.retryGoogleRequest(~Unit, ~U32, ~String, call, options(retries))
    C.dispose(Unit, Result<&2, &1, Retry.RequestFailure<U32>, String>, call)
    final : Script <- Ref.read(Script, script)
    return outcome(result, callsOf(final))

def sameStatus(a: Maybe<&2, U32>, b: Maybe<&2, U32>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{x} Some{y}: U32.is_eq(x, y)
    case _ _: False{}

def checked(value: Result_, +want: Maybe<&2, String>, +status: Maybe<&2, U32>, +calls: Nat, +name: String) -> IO(Unit):
  match value:
    case Result_{got, failed, +made}:
      do IO<Unit>:
        A.equalText(got, want, name ++ ": result")
        A.check(sameStatus(failed, status), name ++ ": rejected error")
        A.check(Nat.is_eq(made, calls), name ++ ": calls " ++ Nat.show(made))
        A.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    first : Result_ <- retried(1n, 429, Some{F.fromU32(1)})
    checked(first, Some{"ok"}, None{}, 2n, "retries a headers-less SDK error with a retryable status")
    second : Result_ <- retried(1n, 429, None{})
    checked(second, None{}, Some{429}, 1n, "does not retry when maxRetries is unset")
    third : Result_ <- retried(3n, 400, Some{F.fromU32(2)})
    checked(third, None{}, Some{400}, 1n, "does not retry a non-retryable status")

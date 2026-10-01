import Base
import ../../ai/src/types.bend as Ai
import ../../agent/src/agent.bend as Agent
import ../../agent/src/types.bend as AgentTypes
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/record.bend as Record
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/f64.bend as F
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/fetch.bend as Fetch
import ../src/utils/paths.bend as Paths
import ../src/core/agent-runtime.bend as Runtime
import ../src/core/agent-session.bend as Session
import ../src/core/sdk.bend as Sdk
import ../src/core/settings-manager.bend as Settings
import ../src/core/resource-loader.bend as Resources
import ../src/core/extensions/loader.bend as Loader
import ../src/core/extensions/runner.bend as Runner
import ../src/core/extensions/types.bend as Ext

# SDK Agent provider hooks are persistent; their invocation reads the current
# extension runner, including after a real resource/session reload. No HTTP.
# Build: BEND_TUS=64 BEND_CFLAGS='-DBEND_APP_ARGV -DBEND_DEFAULT_THREADS=1' sh scripts/build-incremental.sh packages/coding-agent/test/sdk-provider-events.bend build/sdk-provider-events-native

def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def increased(+count: Nat) -> Nat & Nat: (count + 1n, count + 1n)
def next(count: Nat) -> Nat & Nat: increased(count)

def text(value: Ai.JsonValue) -> String:
  match value:
    case Ai.JsonString{found}: found
    case _: "<not text>"

def changed(generation: Nat, call: Ext.HandlerCall<Ext.BeforeProviderRequestEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>):
  match call:
    case Ext.HandlerCall{Ext.BeforeProviderRequestEvent{payload}, _}:
      IO.pure(Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>, Done{Some{Ai.JsonString{text(payload) ++ ":g" ++ Nat.show(generation) ++ ":first"}}})

def unchanged(_: Unit, _: Ext.HandlerCall<Ext.BeforeProviderRequestEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>):
  IO.pure(Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>, Done{None{}})

def failedPayload(_: Unit, _: Ext.HandlerCall<Ext.BeforeProviderRequestEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>):
  IO.pure(Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>, Fail{"payload boom"})

def finishedPayload(_: Unit, call: Ext.HandlerCall<Ext.BeforeProviderRequestEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>):
  match call:
    case Ext.HandlerCall{Ext.BeforeProviderRequestEvent{payload}, _}:
      IO.pure(Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>, Done{Some{Ai.JsonString{text(payload) ++ ":last"}}})

def failedResponse(_: Unit, _: Ext.HandlerCall<Ext.AfterProviderResponseEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  IO.pure(Result<&2, &2, String, Maybe<&2, Unit>>, Fail{"response boom"})

def recordedResponse(slot: R.Ref<Maybe<&2, Ext.AfterProviderResponseEvent>>, call: Ext.HandlerCall<Ext.AfterProviderResponseEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  match call:
    case Ext.HandlerCall{event, _}:
      do IO<Result<&2, &2, String, Maybe<&2, Unit>>>:
        R.write(Maybe<&2, Ext.AfterProviderResponseEvent>, slot, Some{event})
        return Done{None{}}

def registrations(items: List<&2, Result<&2, &2, String, Loader.Unsubscribe>>) -> Result<&2, &2, String, Unit>:
  match items:
    case Nil{}: Done{Unit{}}
    case Fail{message} <> _: Fail{message}
    case Done{_} <> rest: registrations(rest)

type FactoryState is Data:
  FactoryState{calls: R.Ref<Nat>, response: R.Ref<Maybe<&2, Ext.AfterProviderResponseEvent>>}

def factoryWith(state: FactoryState, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match state:
    case FactoryState{calls, response}:
      do IO<Result<&2, &2, String, Unit>>:
        generation : Nat <- R.modify(Nat, Nat, calls, next)
        first : Ext.ExtensionHandler(Ext.BeforeProviderRequestEvent, Ai.JsonValue) <- C.create(~Nat, ~Ext.HandlerCall<Ext.BeforeProviderRequestEvent>, ~Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>, ~changed, generation)
        none : Ext.ExtensionHandler(Ext.BeforeProviderRequestEvent, Ai.JsonValue) <- C.create(~Unit, ~Ext.HandlerCall<Ext.BeforeProviderRequestEvent>, ~Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>, ~unchanged, Unit{})
        bad : Ext.ExtensionHandler(Ext.BeforeProviderRequestEvent, Ai.JsonValue) <- C.create(~Unit, ~Ext.HandlerCall<Ext.BeforeProviderRequestEvent>, ~Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>, ~failedPayload, Unit{})
        last : Ext.ExtensionHandler(Ext.BeforeProviderRequestEvent, Ai.JsonValue) <- C.create(~Unit, ~Ext.HandlerCall<Ext.BeforeProviderRequestEvent>, ~Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>, ~finishedPayload, Unit{})
        responseBad : Ext.ExtensionHandler(Ext.AfterProviderResponseEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.AfterProviderResponseEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~failedResponse, Unit{})
        responseGood : Ext.ExtensionHandler(Ext.AfterProviderResponseEvent, Unit) <- C.create(~R.Ref<Maybe<&2, Ext.AfterProviderResponseEvent>>, ~Ext.HandlerCall<Ext.AfterProviderResponseEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~recordedResponse, response)
        one : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnBeforeProviderRequest{first})
        two : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnBeforeProviderRequest{none})
        three : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnBeforeProviderRequest{bad})
        four : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnBeforeProviderRequest{last})
        five : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnAfterProviderResponse{responseBad})
        six : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnAfterProviderResponse{responseGood})
        return registrations([one, two, three, four, five, six])

def factory(state: FactoryState, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): factoryWith(state, api)

def recordError(slot: R.Ref<List<&2, Ext.ExtensionError>>, error: Ext.ExtensionError) -> IO(Unit):
  R.modify(List<&2, Ext.ExtensionError>, Unit, slot, current => (List.append(&2, Ext.ExtensionError, current, [error]), Unit{}))

def oneError(errors: List<&2, Ext.ExtensionError>, expected: String, message: String) -> Bool:
  match errors:
    case Ext.ExtensionError{_, event, failure, _} <> Nil{}: String.eq(event, expected) && String.contains(failure, message)
    case _: False{}

def responseSeen(found: Maybe<&2, Ext.AfterProviderResponseEvent>) -> Bool:
  match found:
    case Some{Ext.AfterProviderResponseEvent{status, headers}}:
      F.isEqual(F.compare(status, F.fromU32(207))) && String.eq(Maybe.default(&2, String, Record.get(String, headers, "x-response"), ""), "yes")
    case None{}: False{}

def requiredRunner(found: Maybe<&2, Runner.ExtensionRunner>) -> IO(Runner.ExtensionRunner):
  match found:
    case Some{runner}: IO.pure(Runner.ExtensionRunner, runner)
    case None{}: IO.die(Runner.ExtensionRunner, 1, "missing extension runner")

type Hooks is Data:
  Hooks{payload: Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, Runtime.Error()), response: Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, Runtime.Error()), model: Ai.Model<Ai.JsonValue>}

def requiredHooks(payload: Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, Runtime.Error())>, response: Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, Runtime.Error())>, model: Ai.Model<Ai.JsonValue>) -> IO(Hooks):
  match payload response:
    case Some{p} Some{r}: IO.pure(Hooks, Hooks{p, r, model})
    case _ _: IO.die(Hooks, 1, "SDK Agent provider hooks missing")

def hooks(+config: Runtime.LoopConfig()) -> IO(Hooks):
  match config:
    case AgentTypes.AgentLoopConfig{_, model, _, _, _, _, _, _, _, _, _, _, _}:
      do IO<Hooks>:
        +projected : Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Runtime.Error()> <- IO.pure(Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Runtime.Error()>, Runtime.project(config))
        payload : Maybe<&2, Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, Runtime.Error())> = Ai.onPayloadOption(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Runtime.Error(), projected)
        response : Maybe<&2, Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, Runtime.Error())> = Ai.onResponseOption(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Runtime.Error(), projected)
        requiredHooks(payload, response, model)

def requiredPayload(result: Result<&2, &2, Runtime.Error(), Maybe<&2, Ai.JsonValue>>) -> IO(Ai.JsonValue):
  match result:
    case Done{Some{value}}: IO.pure(Ai.JsonValue, value)
    case _: IO.die(Ai.JsonValue, 1, "payload hook did not return replacement")

def responseResult(result: Result<&2, &2, Runtime.Error(), Unit>) -> Bool:
  match result:
    case Done{_}: True{}
    case _: False{}

def invoked(+hooks: Hooks, generation: Nat, +errors: R.Ref<List<&2, Ext.ExtensionError>>, +responseSlot: R.Ref<Maybe<&2, Ext.AfterProviderResponseEvent>>) -> IO(Unit):
  match hooks:
    case Hooks{payload, response, +model}:
      do IO<Unit>:
        R.write(List<&2, Ext.ExtensionError>, errors, Nil{})
        changed : Result<&2, &2, Runtime.Error(), Maybe<&2, Ai.JsonValue>> <- C.call(Ai.PayloadInput<Ai.JsonValue, Ai.Model<Ai.JsonValue>>, Result<&2, &2, Runtime.Error(), Maybe<&2, Ai.JsonValue>>, payload, Ai.PayloadInput{Ai.JsonString{"original"}, model})
        value : Ai.JsonValue <- requiredPayload(changed)
        check(String.eq(text(value), "original:g" ++ Nat.show(generation) ++ ":first:last"), "payload handlers replace in order, retain None, and continue after failure")
        payloadErrors : List<&2, Ext.ExtensionError> <- R.read(List<&2, Ext.ExtensionError>, errors)
        check(oneError(payloadErrors, "before_provider_request", "payload boom"), "payload failure emits exactly one extension error")
        R.write(List<&2, Ext.ExtensionError>, errors, Nil{})
        R.write(Maybe<&2, Ext.AfterProviderResponseEvent>, responseSlot, None{})
        answer : Result<&2, &2, Runtime.Error(), Unit> <- C.call(Ai.ResponseInput<Ai.Model<Ai.JsonValue>>, Result<&2, &2, Runtime.Error(), Unit>, response, Ai.ResponseInput{Ai.ProviderResponse{F.fromU32(207), Record.set(String, Record.new(String), "x-response", "yes")}, model})
        observed : Maybe<&2, Ext.AfterProviderResponseEvent> <- R.read(Maybe<&2, Ext.AfterProviderResponseEvent>, responseSlot)
        check(responseResult(answer) && responseSeen(observed), "response handler keeps status and headers after an earlier handler fails")
        responseErrors : List<&2, Ext.ExtensionError> <- R.read(List<&2, Ext.ExtensionError>, errors)
        check(oneError(responseErrors, "after_provider_response", "response boom"), "response failure emits exactly one extension error")

def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, value): value

def checked(pair: Sdk.CreateAgentSessionResult & Session.AgentSession, +calls: R.Ref<Nat>, +errors: R.Ref<List<&2, Ext.ExtensionError>>, +response: R.Ref<Maybe<&2, Ext.AfterProviderResponseEvent>>, loader: Resources.DefaultResourceLoader) -> IO(Unit):
  match pair:
    case Tuple{owner, +live}:
      do IO<Unit>:
        config : Runtime.LoopConfig() <- Agent.getConfig(V.Value, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, Session.agentOf(live))
        +saved : Hooks <- hooks(config)
        +initial : Nat <- R.read(Nat, calls)
        found : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(live)
        +runner : Runner.ExtensionRunner <- requiredRunner(found)
        +listener : C.Callback<Ext.ExtensionError, Unit> <- C.create(~R.Ref<List<&2, Ext.ExtensionError>>, ~Ext.ExtensionError, ~Unit, ~recordError, errors)
        oldSubscription : Runner.ErrorSubscription <- Runner.onError(runner, listener)
        invoked(saved, initial, errors, response)
        Runner.offError(runner, oldSubscription)
        reloaded : Result<&2, &2, String, Unit> <- Session.reload(live, None{})
        check(Result.is_done(&2, &2, String, Unit, reloaded), "session reload creates a new extension generation")
        +nextGeneration : Nat <- R.read(Nat, calls)
        check(Nat.is_eq(nextGeneration, initial + 1n), "reusable factory runs once on reload")
        replacement : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(live)
        +newRunner : Runner.ExtensionRunner <- requiredRunner(replacement)
        newSubscription : Runner.ErrorSubscription <- Runner.onError(newRunner, listener)
        invoked(saved, nextGeneration, errors, response)
        Runner.offError(newRunner, newSubscription)
        C.dispose(Ext.ExtensionError, Unit, listener)
        Sdk.dispose(owner)
        Resources.disposeDefaultResourceLoader(loader)
        IO.print("ok SDK provider hooks follow the reloaded runner and dispose")

def finished(result: Sdk.Outcome(), calls: R.Ref<Nat>, errors: R.Ref<List<&2, Ext.ExtensionError>>, response: R.Ref<Maybe<&2, Ext.AfterProviderResponseEvent>>, loader: Resources.DefaultResourceLoader) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{owner}: checked(Sdk.sessionOf(owner), calls, errors, response, loader)

def run(+directory: String) -> IO(Unit):
  do IO<Unit>:
    +calls : R.Ref<Nat> <- R.new(Nat, 0n)
    +errors : R.Ref<List<&2, Ext.ExtensionError>> <- R.new(List<&2, Ext.ExtensionError>, Nil{})
    +response : R.Ref<Maybe<&2, Ext.AfterProviderResponseEvent>> <- R.new(Maybe<&2, Ext.AfterProviderResponseEvent>, None{})
    factoryHandle : Ext.ExtensionFactory() <- C.create(~FactoryState, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~factory, FactoryState{calls, response})
    pair : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(directory, directory, Settings.options())
    +settings : Settings.SettingsManager = settingsOf(pair)
    +loader : Resources.DefaultResourceLoader <- Resources.createDefaultResourceLoader(Paths.Environment{directory, directory, Runtime.urlContext()}, Resources.defaultResourceLoaderOptions(directory, directory, settings), [Ext.InlineExtension{"events", factoryHandle, False{}}])
    Resources.reload(Resources.loaderOf(loader), Resources.ResourceLoaderReloadOptions{None{}})
    created : Sdk.Outcome() <- Sdk.createAgentSession(Sdk.CreateAgentSessionOptions{Some{directory}, Some{directory}, None{}, None{}, None{}, Nil{}, None{}, None{}, None{}, Some{Resources.loaderOf(loader)}, None{}, Some{settings}, Nil{}, None{}})
    finished(created, calls, errors, response, loader)
    oldCalls : Nat <- R.dispose(Nat, calls)
    oldErrors : List<&2, Ext.ExtensionError> <- R.dispose(List<&2, Ext.ExtensionError>, errors)
    oldResponse : Maybe<&2, Ext.AfterProviderResponseEvent> <- R.dispose(Maybe<&2, Ext.AfterProviderResponseEvent>, response)
    return Unit{}

def runArgs(args: List<String>) -> IO(Unit):
  match args:
    case directory <> Nil{}: run(directory)
    case _: IO.die(Unit, 1, "expected isolated directory")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    runArgs(args)

import Base
import ../src/core/openai-completions-provider.bend as Completions
import ../src/core/tools/index.bend as Tools
import ../../ai/test/google-generative-ai-client.bend as TestClient
import ../../ai/src/types.bend as Ai
import ../../agent/src/types.bend as Agent
import ../../ai/src/utils/event-stream.bend as Events
import ../../runtime/src/callback.bend as C
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R

def modelOf(value: Ai.Model<Ai.JsonValue>) -> Ai.Model<Ai.JsonValue>:
  match value:
    case Ai.Model{_, _, _, _, url, _, mapping, inputs, limits, cost, cache, window, _, sampling, headers, _}:
      Ai.Model{"test-model", "Test Model", Ai.OpenAICompletionsApi{}, "openai", url, False{}, mapping, inputs, limits, cost, cache, window, F.fromU32(4096), sampling, headers, None{}}

def model(base: String) -> Ai.Model<Ai.JsonValue>: modelOf(TestClient.model(base))

def reasoningOf(selected: Ai.Model<Ai.JsonValue>) -> Ai.Model<Ai.JsonValue>:
  match selected:
    case Ai.Model{id, name, api, provider, url, _, mapping, inputs, limits, cost, cache, window, maximum, sampling, headers, compat}:
      Ai.Model{id, name, api, provider, url, True{}, mapping, inputs, limits, cost, cache, window, maximum, sampling, headers, compat}

def reasoningModel(base: String) -> Ai.Model<Ai.JsonValue>: reasoningOf(model(base))

def providerOf(selected: Ai.Model<Ai.JsonValue>, named: String) -> Ai.Model<Ai.JsonValue>:
  match selected:
    case Ai.Model{id, name, api, _, url, reasoning, mapping, input, limits, cost, cache, window, maximum, sampling, headers, compat}:
      Ai.Model{id, name, api, named, url, reasoning, mapping, input, limits, cost, cache, window, maximum, sampling, headers, compat}

def providerModel(base: String, named: String) -> Ai.Model<Ai.JsonValue>:
  providerOf(reasoningModel(base), named)

def imageOf(selected: Ai.Model<Ai.JsonValue>) -> Ai.Model<Ai.JsonValue>:
  match selected:
    case Ai.Model{id, name, api, provider, url, reasoning, mapping, _, limits, cost, cache, window, maximum, sampling, headers, compat}:
      Ai.Model{id, name, api, provider, url, reasoning, mapping, Ai.InputText{} <> Ai.InputImage{} <> Nil{}, limits, cost, cache, window, maximum, sampling, headers, compat}

def imageModel(base: String) -> Ai.Model<Ai.JsonValue>: imageOf(model(base))

def samplingOf(selected: Ai.Model<Ai.JsonValue>) -> Ai.Model<Ai.JsonValue>:
  match selected:
    case Ai.Model{id, name, api, provider, url, reasoning, mapping, input, limits, cost, cache, window, maximum, _, headers, compat}:
      +sampling = {R.Record{R.Property{"seed", Ai.JsonNumber{F.fromU32(7)}} <> R.Property{"temperature", Ai.JsonNumber{F.fromU32(1)}} <> R.Property{"top_p", Ai.JsonNumber{F.fromU32(0)}} <> Nil{}} : R.Record<Ai.JsonValue>}
      Ai.Model{id, name, api, provider, url, reasoning, mapping, input, limits, cost, cache, window, maximum, Some{sampling}, headers, compat}

def samplingModel(base: String) -> Ai.Model<Ai.JsonValue>: samplingOf(model(base))

def withCompat(value: Ai.Model<Ai.JsonValue>, compat: Ai.OpenAICompletionsCompat) -> Ai.Model<Ai.JsonValue>:
  match value:
    case Ai.Model{id, name, _, provider, url, reasoning, mapping, inputs, limits, cost, cache, window, maximum, sampling, headers, _}:
      Ai.Model{id, name, Ai.OpenAICompletionsApi{}, provider, url, reasoning, mapping, inputs, limits, cost, cache, window, maximum, sampling, headers, Some{compat}}

def overrideModel(base: String) -> Ai.Model<Ai.JsonValue>:
  withCompat(model(base), Ai.OpenAICompletionsCompat{Some{False{}}, None{}, None{}, Some{False{}}, None{}, Some{Ai.MaxTokens{}}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}})

# The stream fold has no fallback for providers without finish_reason yet.
def unsupportedModel(base: String) -> Ai.Model<Ai.JsonValue>:
  withCompat(model(base), Ai.OpenAICompletionsCompat{None{}, None{}, None{}, None{}, Some{False{}}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}})

def context() -> Completions.Context():
  Ai.TranscriptContext{Ai.User{Ai.UserMessage{Ai.UserText{"ping"}, F.fromU32(1)}} <> Nil{}}

def schema() -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"value", V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}} <> Nil{}}}} <> Nil{}}}

def system() -> Ai.SystemMessage<V.Value>:
  Ai.SystemMessage{Ai.SystemText{"Use the lookup tool."}, None{}, Some{Ai.Tool{"lookup", "Look up a value", schema(), None{}} <> Nil{}}, None{}, F.fromU32(1)}

def toolContext() -> Completions.Context():
  Ai.TranscriptContext{Ai.System{system()} <> Ai.User{Ai.UserMessage{Ai.UserText{"lookup 42"}, F.fromU32(2)}} <> Nil{}}

def continued(first: Ai.AssistantMessage<V.Value, Unit>) -> Completions.Context():
  Ai.TranscriptContext{Ai.System{system()} <> Ai.User{Ai.UserMessage{Ai.UserText{"lookup 42"}, F.fromU32(2)}} <> Ai.Assistant{first} <> Ai.ToolResult{Ai.ToolResultMessage{"call-1", "lookup", Ai.TextImageText{Ai.TextContent{"found 42", None{}}} <> Nil{}, None{}, None{}, False{}, F.fromU32(3)}} <> Nil{}}

def continuedImage(first: Ai.AssistantMessage<V.Value, Unit>) -> Completions.Context():
  Ai.TranscriptContext{Ai.System{system()} <> Ai.User{Ai.UserMessage{Ai.UserText{"lookup 42"}, F.fromU32(2)}} <> Ai.Assistant{first} <> Ai.ToolResult{Ai.ToolResultMessage{"call-1", "lookup", Ai.TextImageText{Ai.TextContent{"found 42", None{}}} <> Ai.TextImageImage{Ai.ImageContent{"ZmFrZQ==", "image/png"}} <> Nil{}, None{}, None{}, False{}, F.fromU32(3)}} <> Nil{}}

def options() -> Completions.Options():
  Ai.withApiKey(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Completions.Error(), Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Completions.Error()), Some{"test-completions-key"})

def retriedOptions(value: Completions.Options()) -> Completions.Options():
  match value:
    case Ai.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, _, delay, temperature, sampling, maximum, transport, cache, session, websocket, metadata, choice, reasoning, deferred, budgets}:
      Ai.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, Some{F.fromU32(1)}, delay, temperature, sampling, maximum, transport, cache, session, websocket, metadata, choice, reasoning, deferred, budgets}

def retryOptions() -> Completions.Options(): retriedOptions(options())

def reasoningOptions(value: Completions.Options()) -> Completions.Options():
  match value:
    case Ai.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, maximum, transport, cache, session, websocket, metadata, choice, _, deferred, budgets}:
      Ai.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, maximum, transport, cache, session, websocket, metadata, choice, Some{Ai.Low{}}, deferred, budgets}

def samplingOptions(value: Completions.Options()) -> Completions.Options():
  match value:
    case Ai.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, _, _, maximum, transport, cache, session, websocket, metadata, choice, reasoning, deferred, budgets}:
      +sampling = {R.Record{R.Property{"temperature", Ai.JsonNumber{F.fromU32(3)}} <> R.Property{"top_p", Ai.JsonNumber{F.fromU32(1)}} <> R.Property{"presence_penalty", Ai.JsonNumber{F.fromU32(1)}} <> Nil{}} : R.Record<Ai.JsonValue>}
      Ai.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, Some{F.fromU32(2)}, Some{sampling}, maximum, transport, cache, session, websocket, metadata, choice, reasoning, deferred, budgets}

def configuredHeaders(value: Completions.Options()) -> Completions.Options():
  match value:
    case Ai.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, _, timeout, retries, delay, temperature, sampling, maximum, transport, cache, session, websocket, metadata, choice, reasoning, deferred, budgets}:
      +headers = {R.Record{R.Property{"User-Agent", Ai.PresentValue{"custom-agent"}} <> R.Property{"X-Completions-Test", Ai.PresentValue{"option"}} <> Nil{}} : Ai.ProviderHeaders()}
      Ai.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, Some{headers}, timeout, retries, delay, temperature, sampling, maximum, transport, cache, session, websocket, metadata, choice, reasoning, deferred, budgets}

def headerOptions() -> Completions.Options(): configuredHeaders(options())

def eventName(event: Ai.AssistantMessageEvent<V.Value, Unit>) -> String:
  match event:
    case Ai.Start{_}: "start"
    case Ai.TextStart{_, _}: "text_start"
    case Ai.TextDelta{_, _, _}: "text_delta"
    case Ai.TextEnd{_, _, _}: "text_end"
    case Ai.ThinkingStart{_, _}: "thinking_start"
    case Ai.ThinkingDelta{_, _, _}: "thinking_delta"
    case Ai.ThinkingEnd{_, _, _}: "thinking_end"
    case Ai.ToolcallStart{_, _}: "toolcall_start"
    case Ai.ToolcallDelta{_, _, _}: "toolcall_delta"
    case Ai.ToolcallEnd{_, _, _}: "toolcall_end"
    case Ai.StreamDone{_, _}: "done"
    case Ai.StreamError{_, _}: "error"
    case _: "other"

@unsafe def drain(next: Events.Iteration<Ai.AssistantMessageEvent<V.Value, Unit>>, +cursor: Events.Iterator<Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>>) -> IO(Unit):
  match next:
    case Events.Yield{event}:
      do IO<Unit>:
        IO.print(eventName(event))
        following : Events.Iteration<Ai.AssistantMessageEvent<V.Value, Unit>> <- Events.nextValue(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, cursor)
        drain(following, cursor)
    case Events.End{}: Events.disposeIterator(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, cursor)

def opened(result: Completions.Output()) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  match result:
    case Fail{_}: IO.die(Ai.AssistantMessage<V.Value, Unit>, 1, "provider failed to open")
    case Done{Agent.StreamLease{+events, release}}:
      do IO<Ai.AssistantMessage<V.Value, Unit>>:
        +cursor : Events.Iterator<Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>> <- Events.iterator(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, events)
        first : Events.Iteration<Ai.AssistantMessageEvent<V.Value, Unit>> <- Events.nextValue(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, cursor)
        drain(first, cursor)
        message : Ai.AssistantMessage<V.Value, Unit> <- Events.resultValue(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, events)
        result : Result<&2, &2, Completions.Error(), Unit> <- release
        return message

def request(fetch: Fetch.Fetch(Unit), base: String, context: Completions.Context()) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  do IO<Ai.AssistantMessage<V.Value, Unit>>:
    result : Completions.Output() <- Completions.open(fetch, TestClient.urlContext(), model(base), context, Some{options()})
    opened(result)

def imageRequest(fetch: Fetch.Fetch(Unit), base: String, context: Completions.Context()) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  do IO<Ai.AssistantMessage<V.Value, Unit>>:
    result : Completions.Output() <- Completions.open(fetch, TestClient.urlContext(), imageModel(base), context, Some{options()})
    opened(result)

def retryRequest(fetch: Fetch.Fetch(Unit), base: String) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  do IO<Ai.AssistantMessage<V.Value, Unit>>:
    result : Completions.Output() <- Completions.open(fetch, TestClient.urlContext(), model(base), context(), Some{retryOptions()})
    opened(result)

def reasoningRequest(fetch: Fetch.Fetch(Unit), base: String) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  do IO<Ai.AssistantMessage<V.Value, Unit>>:
    result : Completions.Output() <- Completions.open(fetch, TestClient.urlContext(), reasoningModel(base), context(), Some{reasoningOptions(options())})
    opened(result)

def samplingRequest(fetch: Fetch.Fetch(Unit), base: String) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  do IO<Ai.AssistantMessage<V.Value, Unit>>:
    result : Completions.Output() <- Completions.open(fetch, TestClient.urlContext(), samplingModel(base), context(), Some{samplingOptions(options())})
    opened(result)

def providerOptions(enabled: Bool) -> Completions.Options():
  Bool.pick(Completions.Options(), enabled, reasoningOptions(options()), options())

def providerRequest(fetch: Fetch.Fetch(Unit), base: String, named: String, enabled: Bool) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  do IO<Ai.AssistantMessage<V.Value, Unit>>:
    result : Completions.Output() <- Completions.open(fetch, TestClient.urlContext(), providerModel(base, named), context(), Some{providerOptions(enabled)})
    opened(result)

def headerRequest(fetch: Fetch.Fetch(Unit), base: String) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  do IO<Ai.AssistantMessage<V.Value, Unit>>:
    result : Completions.Output() <- Completions.open(fetch, TestClient.urlContext(), model(base), context(), Some{headerOptions()})
    opened(result)

def selectedModel(+base: String, unsupported: Bool) -> Ai.Model<Ai.JsonValue>:
  Bool.pick(Ai.Model<Ai.JsonValue>, unsupported, unsupportedModel(base), overrideModel(base))

def compatRequest(fetch: Fetch.Fetch(Unit), base: String, unsupported: Bool) -> IO(Ai.AssistantMessage<V.Value, Unit>):
  do IO<Ai.AssistantMessage<V.Value, Unit>>:
    result : Completions.Output() <- Completions.open(fetch, TestClient.urlContext(), selectedModel(base, unsupported), context(), Some{options()})
    opened(result)

def scenario(+fetch: Fetch.Fetch(Unit), +base: String, mode: String) -> IO(Unit):
  match mode:
    case "sampling":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- samplingRequest(fetch, base)
        return Unit{}
    case "deepseek":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- providerRequest(fetch, base, "deepseek", True{})
        return Unit{}
    case "reasoning_off":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- providerRequest(fetch, base, "openai", False{})
        return Unit{}
    case "openrouter":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- providerRequest(fetch, base, "openrouter", True{})
        return Unit{}
    case "openrouter_off":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- providerRequest(fetch, base, "openrouter", False{})
        return Unit{}
    case "together":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- providerRequest(fetch, base, "together", True{})
        return Unit{}
    case "together_off":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- providerRequest(fetch, base, "together", False{})
        return Unit{}
    case "tool_image":
      do IO<Unit>:
        first : Ai.AssistantMessage<V.Value, Unit> <- imageRequest(fetch, base, toolContext())
        second : Ai.AssistantMessage<V.Value, Unit> <- imageRequest(fetch, base, continuedImage(first))
        return Unit{}
    case "reasoning":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- reasoningRequest(fetch, base)
        return Unit{}
    case "unsupported":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- compatRequest(fetch, base, True{})
        return Unit{}
    case "compat":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- compatRequest(fetch, base, False{})
        return Unit{}
    case "headers":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- headerRequest(fetch, base)
        return Unit{}
    case "retry":
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- retryRequest(fetch, base)
        return Unit{}
    case "tool":
      do IO<Unit>:
        first : Ai.AssistantMessage<V.Value, Unit> <- request(fetch, base, toolContext())
        second : Ai.AssistantMessage<V.Value, Unit> <- request(fetch, base, continued(first))
        return Unit{}
    case _:
      do IO<Unit>:
        message : Ai.AssistantMessage<V.Value, Unit> <- request(fetch, base, context())
        return Unit{}

def borrowed(base: String, mode: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (runtime, +fetch):
      do IO<Unit>:
        scenario(fetch, base, mode)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(runtime)

def initialized(base: String, mode: String, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}:
      do IO<Unit>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
        borrowed(base, mode, pair)

def run(base: String, mode: String) -> IO(Unit):
  do IO<Unit>:
    runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), TestClient.networkOptions())
    initialized(base, mode, runtime)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case base <> Nil{}: run(base, "basic")
    case base <> mode <> Nil{}: run(base, mode)
    case _: IO.die(Unit, 1, "base URL required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

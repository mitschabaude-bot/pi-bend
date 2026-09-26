import Base
import ../src/types.bend as T
import ../src/providers/anthropic.models.bend as Anthropic
import ../src/providers/openai.models.bend as OpenAI
import ../src/utils/transcript.bend as Transcript
import ./anthropic-harness.bend as H
import ./responses-payload.bend as RP
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/cache-retention.test.ts, the Anthropic
# Messages and OpenAI Responses cases (the Chat Completions cases are named
# request cases in tests/openai_completions_request_check.py). The payload is
# captured by onPayload. Where upstream sets process.env.PI_CACHE_RETENTION,
# the value is passed as the request's provider env, which
# getProviderEnvValue reads before the process environment.
def J() -> Data: T.JsonValue

def longEnv() -> Maybe<&2, T.ProviderEnv()>: Some{R.Record{R.Property{"PI_CACHE_RETENTION", "long"} <> Nil{}}}

def systemPrompt() -> String: "You are a helpful assistant."

# Anthropic Messages
# ------------------
def anthropicOptions(retention: Maybe<&2, T.CacheRetention>, env: Maybe<&2, T.ProviderEnv()>) -> H.Options():
  H.direct(T.StreamOptions{None{}, None{}, Some{"fake-key"}, None{}, env, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, retention, None{}, None{}, None{}}, None{}, None{})

def withAnthropicCompat(model: T.Model<J()>, compat: T.AnthropicMessagesCompat) -> T.Model<J()>:
  match model:
    case T.Model{id, name, api, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, _}:
      T.Model{id, name, T.AnthropicMessagesApi{}, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, Some{compat}}

def noLongRetention() -> T.AnthropicMessagesCompat:
  T.AnthropicMessagesCompat{None{}, Some{False{}}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def proxy() -> T.Model<J()>: H.withBase(Anthropic.model_claude_haiku_4_5(), "https://my-proxy.example.com/v1")

def anthropicPayload(+model: T.Model<J()>, options: H.Options()) -> IO(Maybe<&2, J()>):
  +context = H.contextWith(Some{systemPrompt()}, H.user("Hello", 1) <> Nil{}, None{})
  do IO<Maybe<&2, J()>>:
    outcome : H.Outcome <- H.run(model, context, options, H.Capture{})
    +payload : Maybe<&2, J()> <- IO.pure(Maybe<&2, J()>, H.payloadOf(outcome))
    H.check(Maybe.is_some(&2, J(), payload), "payload captured")
    return payload

def systemCache(payload: Maybe<&2, J()>) -> Maybe<&2, J()>: H.fieldOf(H.firstElement(H.fieldOf(payload, "system")), "cache_control")

def lastOf(values: List<&2, J()>) -> Maybe<&2, J()>: List.head(&2, J(), List.reverse(&2, J(), values))

def isArray(value: Maybe<&2, J()>) -> Bool:
  match value:
    case Some{T.JsonArray{_}}: True{}
    case _: False{}

def systemCacheIs(+name: String, +model: T.Model<J()>, options: H.Options(), +want: String) -> IO(Unit):
  do IO<Unit>:
    payload : Maybe<&2, J()> <- anthropicPayload(model, options)
    H.equalJson(systemCache(payload), want, name)
    H.pass(name)

def anthropicCases() -> IO(Unit):
  do IO<Unit>:
    systemCacheIs("should add ttl for non-api.anthropic.com baseUrl by default", proxy(), anthropicOptions(None{}, longEnv()), "{\"type\":\"ephemeral\",\"ttl\":\"1h\"}")
    systemCacheIs("should omit ttl when supportsLongCacheRetention is false", withAnthropicCompat(proxy(), noLongRetention()), anthropicOptions(Some{T.CacheLong{}}, None{}), "{\"type\":\"ephemeral\"}")
    +none : Maybe<&2, J()> <- anthropicPayload(Anthropic.model_claude_haiku_4_5(), anthropicOptions(Some{T.CacheNone{}}, None{}))
    H.absent(systemCache(none), "should omit cache_control when cacheRetention is none")
    H.pass("should omit cache_control when cacheRetention is none")
    +plain : Maybe<&2, J()> <- anthropicPayload(Anthropic.model_claude_haiku_4_5(), anthropicOptions(None{}, None{}))
    +last : Maybe<&2, J()> <- IO.pure(Maybe<&2, J()>, H.fieldOf(lastOf(H.elements(H.fieldOf(plain, "messages"))), "content"))
    H.check(isArray(last), "should add cache_control to string user messages: content is not an array")
    H.equalJson(H.fieldOf(lastOf(H.elements(last)), "cache_control"), "{\"type\":\"ephemeral\"}", "should add cache_control to string user messages")
    H.pass("should add cache_control to string user messages")
    systemCacheIs("should set 1h cache TTL when cacheRetention is long", Anthropic.model_claude_haiku_4_5(), anthropicOptions(Some{T.CacheLong{}}, None{}), "{\"type\":\"ephemeral\",\"ttl\":\"1h\"}")

# OpenAI Responses
# ----------------
def context() -> RP.Context():
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{Some{systemPrompt()}, T.User{T.UserMessage{T.UserText{"Hello"}, H.zero()}} <> Nil{}, None{}})

def promptCacheOf(model: T.Model<J()>) -> Maybe<&2, T.ModelPromptCache>:
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, _, cache, _, _, _, _, _}: cache

def noWarming(+model: T.Model<J()>) -> IO(Unit):
  +name = "does not enable cache warming from the documented TTL alone for " ++ T.modelId(model)
  do IO<Unit>:
    H.check(Maybe.is_none(&2, T.ModelPromptCache, promptCacheOf(model)), name)
    H.pass(name)

def withResponsesCompat(model: T.Model<J()>, compat: T.OpenAIResponsesCompat) -> T.Model<J()>:
  match model:
    case T.Model{id, name, api, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, _}:
      T.Model{id, name, T.OpenAIResponsesApi{}, provider, base, reasoning, levels, input, limits, cost, cache, window, maximum, sampling, headers, Some{compat}}

def responsesPayload(+model: T.Model<J()>, retention: Maybe<&2, T.CacheRetention>, session: Maybe<&2, String>, env: Maybe<&2, T.ProviderEnv()>) -> IO(Maybe<&2, J()>):
  RP.streamPayload(model, context(), RP.options(retention, session, env))

def longField(+model: T.Model<J()>, retention: String, cacheOptions: String) -> IO(Unit):
  +name = "should use the supported long cache field for " ++ T.modelId(model)
  do IO<Unit>:
    +payload : Maybe<&2, J()> <- responsesPayload(model, Some{T.CacheLong{}}, Some{"session-2"}, None{})
    H.equalJson(H.fieldOf(payload, "prompt_cache_key"), "\"session-2\"", name ++ " key")
    H.equalJson(Some{Maybe.default(&2, J(), H.fieldOf(payload, "prompt_cache_retention"), T.JsonNull{})}, retention, name ++ " retention")
    H.equalJson(Some{Maybe.default(&2, J(), H.fieldOf(payload, "prompt_cache_options"), T.JsonNull{})}, cacheOptions, name ++ " options")
    H.pass(name)

def responsesCases() -> IO(Unit):
  do IO<Unit>:
    noWarming(OpenAI.model_gpt_5_6_luna())
    noWarming(OpenAI.model_gpt_5_6_sol())
    noWarming(OpenAI.model_gpt_5_6_terra())
    noWarming(OpenAI.model_gpt_6_astra())
    noWarming(OpenAI.model_gpt_6_luna())
    noWarming(OpenAI.model_gpt_6_sol())
    proxied : Maybe<&2, J()> <- responsesPayload(H.withBase(OpenAI.model_gpt_4o_mini(), "https://my-proxy.example.com/v1"), None{}, None{}, longEnv())
    H.equalJson(H.fieldOf(proxied, "prompt_cache_retention"), "\"24h\"", "should set prompt_cache_retention for non-api.openai.com baseUrl by default")
    H.pass("should set prompt_cache_retention for non-api.openai.com baseUrl by default")
    unsupported : Maybe<&2, J()> <- responsesPayload(withResponsesCompat(OpenAI.model_gpt_4o_mini(), T.OpenAIResponsesCompat{None{}, None{}, None{}, Some{False{}}, None{}, None{}, None{}, None{}, None{}, None{}}), Some{T.CacheLong{}}, Some{"session-compat-false"}, None{})
    H.absent(H.fieldOf(unsupported, "prompt_cache_retention"), "should omit prompt_cache_retention when supportsLongCacheRetention is false")
    H.pass("should omit prompt_cache_retention when supportsLongCacheRetention is false")
    +none : Maybe<&2, J()> <- responsesPayload(OpenAI.model_gpt_5_6_sol(), Some{T.CacheNone{}}, Some{"session-1"}, None{})
    H.absent(H.fieldOf(none, "prompt_cache_key"), "should omit prompt_cache_key and disable implicit writes when cacheRetention is none: key")
    H.absent(H.fieldOf(none, "prompt_cache_retention"), "should omit prompt_cache_key and disable implicit writes when cacheRetention is none: retention")
    H.equalJson(H.fieldOf(none, "prompt_cache_options"), "{\"mode\":\"explicit\"}", "should omit prompt_cache_key and disable implicit writes when cacheRetention is none")
    H.pass("should omit prompt_cache_key and disable implicit writes when cacheRetention is none")
    +rejecting : Maybe<&2, J()> <- responsesPayload(OpenAI.model_gpt_4o_mini(), Some{T.CacheNone{}}, Some{"session-1"}, None{})
    H.absent(H.fieldOf(rejecting, "prompt_cache_key"), "should omit prompt_cache_options for models that reject it: key")
    H.absent(H.fieldOf(rejecting, "prompt_cache_options"), "should omit prompt_cache_options for models that reject it")
    H.pass("should omit prompt_cache_options for models that reject it")
    longField(OpenAI.model_gpt_4o_mini(), "\"24h\"", "null")
    longField(OpenAI.model_gpt_6_astra(), "null", "{\"ttl\":\"30m\"}")
    longField(OpenAI.model_gpt_6_sol(), "null", "{\"ttl\":\"30m\"}")
    longField(OpenAI.model_gpt_6_luna(), "null", "{\"ttl\":\"30m\"}")

def run() -> IO(Unit):
  do IO<Unit>:
    anthropicCases()
    responsesCases()

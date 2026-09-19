import Base
import ../types.bend as T
import ../utils/provider-env.bend as Env
import ./openai-prompt-cache.bend as CacheKey
import ../../../runtime/src/record.bend as R

# Required<OpenAIResponsesCompat>: all upstream fields retain their names.
type ResolvedCompat is Data:
  ResolvedCompat{supportsDeveloperRole: Bool, supportsMidConvoSystemMessages: Bool, sessionAffinityFormat: T.SessionAffinityFormat, supportsLongCacheRetention: Bool, supportsStrictMode: Bool, supportsOpenAIGrammarTools: Bool, supportsAdditionalTools: Bool, supportsToolSearch: Bool, supportsExplicitPromptCacheMode: Bool, supportsMaxOutputTokens: Bool}

def boolDefault(value: Maybe<&2, Bool>, fallback: Bool) -> Bool:
  match value:
    case None{}: fallback
    case Some{flag}: flag

def detectSessionAffinityFormat(provider: String, baseUrl: String) -> T.SessionAffinityFormat:
  Bool.pick(T.SessionAffinityFormat, String.eq(provider, "openrouter") || String.contains(baseUrl, "openrouter.ai"), T.OpenRouterSession{}, T.OpenAISession{})

def affinityDefault(value: Maybe<&2, T.SessionAffinityFormat>, provider: String, baseUrl: String) -> T.SessionAffinityFormat:
  match value:
    case None{}: detectSessionAffinityFormat(provider, baseUrl)
    case Some{format}: format

def getCompat(provider: String, baseUrl: String, compat: Maybe<&2, T.OpenAIResponsesCompat>) -> ResolvedCompat:
  match compat:
    case None{}: ResolvedCompat{True{}, False{}, detectSessionAffinityFormat(provider, baseUrl), True{}, False{}, False{}, False{}, False{}, False{}, True{}}
    case Some{T.OpenAIResponsesCompat{developer, midConvo, affinity, longCache, strict, grammar, additional, search, explicitCache, maxOutput}}:
      ResolvedCompat{boolDefault(developer, True{}), boolDefault(midConvo, False{}), affinityDefault(affinity, provider, baseUrl), boolDefault(longCache, True{}), boolDefault(strict, False{}), boolDefault(grammar, False{}), boolDefault(additional, False{}), boolDefault(search, False{}), boolDefault(explicitCache, False{}), boolDefault(maxOutput, True{})}

# envValue is PI_CACHE_RETENTION after scoped/process environment resolution.
# Keeping environment acquisition outside this pure policy prevents hidden IO.
def environmentRetention(envValue: Maybe<&2, String>) -> T.CacheRetention:
  match envValue:
    case None{}: T.CacheShort{}
    case Some{text}: Bool.pick(T.CacheRetention, String.eq(text, "long"), T.CacheLong{}, T.CacheShort{})

def resolveCacheRetentionValue(retention: Maybe<&2, T.CacheRetention>, envValue: Maybe<&2, String>) -> T.CacheRetention:
  match retention:
    case None{}: environmentRetention(envValue)
    case Some{value}: value

type PromptCacheOptions is Data:
  ExplicitMode{}
  ThirtyMinuteTtl{}

def getPromptCacheRetention(compat: ResolvedCompat, retention: T.CacheRetention) -> Maybe<&2, String>:
  match compat retention:
    case ResolvedCompat{_, _, _, True{}, _, _, _, _, False{}, _} T.CacheLong{}: Some{"24h"}
    case _ _: None{}

def getPromptCacheOptions(compat: ResolvedCompat, retention: T.CacheRetention) -> Maybe<&2, PromptCacheOptions>:
  match compat retention:
    case ResolvedCompat{_, _, _, _, _, _, _, _, True{}, _} T.CacheNone{}: Some{ExplicitMode{}}
    case ResolvedCompat{_, _, _, True{}, _, _, _, _, True{}, _} T.CacheLong{}: Some{ThirtyMinuteTtl{}}
    case _ _: None{}

def cacheSessionId(retention: T.CacheRetention, sessionId: Maybe<&2, String>) -> Maybe<&2, String>:
  match retention:
    case T.CacheNone{}: None{}
    case _: sessionId

def promptCacheKey(retention: T.CacheRetention, sessionId: Maybe<&2, String>) -> Maybe<&2, String>:
  CacheKey.clampOpenAIPromptCacheKey(cacheSessionId(retention, sessionId))

# These are only the generated affinity defaults. The client merges explicit
# caller headers last, and the transport subsequently normalizes HTTP names.
def affinityHeaders(format: T.SessionAffinityFormat, sessionId: Maybe<&2, String>) -> R.Record<String>:
  match format sessionId:
    case _ None{}: R.new(String)
    case _ Some{SNil{}}: R.new(String)
    case T.OpenRouterSession{} Some{text}: R.Record{R.Property{"x-session-id", text} <> Nil{}}
    case T.OpenAINoSession{} Some{text}: R.Record{R.Property{"x-client-request-id", text} <> Nil{}}
    case T.OpenAISession{} Some{+text}: R.Record{R.Property{"session_id", text} <> R.Property{"x-client-request-id", text} <> Nil{}}

# Resolve the scoped/process value only when no explicit retention was supplied.
def resolveCacheRetention(retention: Maybe<&2, T.CacheRetention>, env: Maybe<&2, T.ProviderEnv()>) -> IO(T.CacheRetention):
  match retention:
    case Some{value}: IO.pure(T.CacheRetention, value)
    case None{}:
      do IO<T.CacheRetention>:
        value : Maybe<&2, String> <- Env.getProviderEnvValue("PI_CACHE_RETENTION", env)
        return environmentRetention(value)

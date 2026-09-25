import Base
import ../types.bend as T
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/string.bend as Text

# upstream providers/cloudflare-stream.ts. The endpoint constants of
# api/cloudflare.ts are the catalog base URLs; the placeholders materialize
# from the resolved provider env before dispatch. models.bend applies this to
# the APIs a provider's CloudflareStreams wrap (upstream cloudflareStreams).

def CLOUDFLARE_ACCOUNT_ID() -> String: "CLOUDFLARE_ACCOUNT_ID"
def CLOUDFLARE_GATEWAY_ID() -> String: "CLOUDFLARE_GATEWAY_ID"

# An unset variable leaves its placeholder in place.
def materialized(baseUrl: String, +name: String, value: Maybe<&2, String>) -> String:
  match value:
    case None{}: baseUrl
    case Some{text}: Text.replaceAll(baseUrl, "{" ++ name ++ "}", text)

def endpoint(baseUrl: String, +env: T.ProviderEnv()) -> String:
  materialized(materialized(baseUrl, CLOUDFLARE_ACCOUNT_ID(), R.get(String, env, CLOUDFLARE_ACCOUNT_ID())), CLOUDFLARE_GATEWAY_ID(), R.get(String, env, CLOUDFLARE_GATEWAY_ID()))

def withEndpoint(-SamplingValue: Data, model: T.Model<SamplingValue>, env: T.ProviderEnv()) -> T.Model<SamplingValue>:
  match model:
    case T.Model{id, name, api, provider, baseUrl, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}:
      T.Model{id, name, api, provider, endpoint(baseUrl, env), reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}

def resolveCloudflareModel(-SamplingValue: Data, model: T.Model<SamplingValue>, env: Maybe<&2, T.ProviderEnv()>) -> T.Model<SamplingValue>:
  match env:
    case None{}: model
    case Some{fields}: withEndpoint(SamplingValue, model, fields)

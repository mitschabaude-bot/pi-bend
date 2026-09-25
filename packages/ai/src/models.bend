import Base
import ./types.bend as T
import ./utils/model-api.bend as Api
import ./utils/thinking-levels.bend as Thinking
import ./utils/cost.bend as Cost
import ../../runtime/src/utf16.bend as U
import ./auth/types.bend as Auth
import ./providers/cloudflare-stream.bend as Cloudflare

# upstream Provider.api, reduced to what differs between providers: requests
# stream through the shared implementation of the model's api, and the
# Cloudflare providers first materialize endpoint placeholders for the APIs
# they wrap (upstream cloudflareStreams).
type ProviderStreams is Data:
  ApiStreams{}
  CloudflareStreams{apis: List<&2, T.ModelApi>}

# A model provider (upstream Provider): providers/<id>.bend construct the
# built-in ones and providers/all.bend lists them. Upstream's optional baseUrl
# is "" when absent. Not carried: headers (no built-in provider sets them),
# refreshModels and filterModels.
type Provider is Data:
  Provider{id: String, name: String, baseUrl: String, auth: Auth.ProviderAuth, models: List<&2, T.Model<T.JsonValue>>, streams: ProviderStreams}

def wraps(apis: List<&2, T.ModelApi>, +api: String) -> Bool:
  match apis:
    case Nil{}: False{}
    case wrapped <> rest: U.equal(Api.name(wrapped), api) || wraps(rest, api)

def streamedWith(-SamplingValue: Data, wrapped: Bool, model: T.Model<SamplingValue>, env: Maybe<&2, T.ProviderEnv()>) -> T.Model<SamplingValue>:
  match wrapped:
    case True{}: Cloudflare.resolveCloudflareModel(SamplingValue, model, env)
    case False{}: model

# The model a provider's stream dispatches for a request with the resolved
# provider env.
def streamModel(-SamplingValue: Data, streams: ProviderStreams, +model: T.Model<SamplingValue>, env: Maybe<&2, T.ProviderEnv()>) -> T.Model<SamplingValue>:
  match streams:
    case ApiStreams{}: model
    case CloudflareStreams{apis}: streamedWith(SamplingValue, wraps(apis, Api.name(Api.modelApi(SamplingValue, model))), model, env)

def usedBy(models: List<&2, T.Model<T.JsonValue>>, +api: String) -> Bool:
  match models:
    case Nil{}: False{}
    case model <> rest: U.equal(Api.name(Api.modelApi(T.JsonValue, model)), api) || usedBy(rest, api)

def usedApis(apis: List<&2, T.ModelApi>, +models: List<&2, T.Model<T.JsonValue>>) -> List<&2, T.ModelApi>:
  match apis:
    case Nil{}: Nil{}
    case +api <> rest:
      +tail = usedApis(rest, models)
      Bool.pick(List<&2, T.ModelApi>, usedBy(models, Api.name(api)), api <> tail, tail)

# upstream composeProvider: a models.json overlay streams through its base
# provider only for APIs the base provider's models use.
def inheritedStreams(base: Maybe<&2, Provider>) -> ProviderStreams:
  match base:
    case None{}: ApiStreams{}
    case Some{Provider{_, _, _, _, _, ApiStreams{}}}: ApiStreams{}
    case Some{Provider{_, _, _, _, models, CloudflareStreams{apis}}}: CloudflareStreams{usedApis(apis, models)}

# Leaf utilities from models.ts. The Models registry and runtime
# specialization remain pending; hasApi currently returns a boolean predicate.
def hasApi(-SamplingValue: Data, model: T.Model<SamplingValue>, api: String) -> Bool:
  U.equal(Api.name(Api.modelApi(SamplingValue, model)), api)

def getSupportedThinkingLevels(-SamplingValue: Data, model: T.Model<SamplingValue>) -> List<&2, T.ModelThinkingLevel>:
  match model:
    case T.Model{_, _, _, _, _, reasoning, mapping, _, _, _, _, _, _, _, _, _}: Thinking.available(reasoning, mapping)

def clampThinkingLevel(-SamplingValue: Data, model: T.Model<SamplingValue>, level: T.ModelThinkingLevel) -> T.ModelThinkingLevel:
  Thinking.closest(getSupportedThinkingLevels(SamplingValue, model), Thinking.rank(level), T.Off{})

def modelsAreEqual(-SamplingValue: Data, a: Maybe<&2, T.Nullable<T.Model<SamplingValue>>>, b: Maybe<&2, T.Nullable<T.Model<SamplingValue>>>) -> Bool:
  match a b:
    case Some{T.PresentValue{T.Model{idA, _, _, providerA, _, _, _, _, _, _, _, _, _, _, _, _}}} Some{T.PresentValue{T.Model{idB, _, _, providerB, _, _, _, _, _, _, _, _, _, _, _, _}}}: U.equal(idA, idB) && U.equal(providerA, providerB)
    case _ _: False{}

def calculateCost(-SamplingValue: Data, model: T.Model<SamplingValue>, usage: T.Usage) -> T.UsageCost:
  Cost.calculate(SamplingValue, model, usage)

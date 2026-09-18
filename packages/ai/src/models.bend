import Base
import ./types.bend as T
import ./utils/model-api.bend as Api
import ./utils/thinking-levels.bend as Thinking
import ./utils/cost.bend as Cost
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/utf16.bend as U

# Leaf utilities from models.ts. Registry/providers and runtime specialization
# remain pending; hasApi currently returns a boolean predicate.
def hasApi(-SamplingValue: Data, model: T.Model<SamplingValue>, api: String) -> Bool:
  U.equal(Api.name(Api.modelApi(SamplingValue, model)), api)

def getSupportedThinkingLevels(-SamplingValue: Data, model: T.Model<SamplingValue>) -> List<&2, T.ModelThinkingLevel>:
  match model:
    case T.Model{_, _, _, _, _, reasoning, mapping, _, _, _, _, _, _, _}: Thinking.available(reasoning, mapping)

def clampThinkingLevel(-SamplingValue: Data, model: T.Model<SamplingValue>, level: T.ModelThinkingLevel) -> T.ModelThinkingLevel:
  Thinking.closest(getSupportedThinkingLevels(SamplingValue, model), Thinking.rank(level), T.Off{})

def modelsAreEqual(-SamplingValue: Data, a: Maybe<&2, T.Nullable<T.Model<SamplingValue>>>, b: Maybe<&2, T.Nullable<T.Model<SamplingValue>>>) -> Bool:
  match a b:
    case Some{T.PresentValue{T.Model{idA, _, _, providerA, _, _, _, _, _, _, _, _, _, _}}} Some{T.PresentValue{T.Model{idB, _, _, providerB, _, _, _, _, _, _, _, _, _, _}}}: U.equal(idA, idB) && U.equal(providerA, providerB)
    case _ _: False{}

def calculateCost(-SamplingValue: Data, model: T.Model<SamplingValue>, usage: T.Usage) -> IO(Ref.Ref<T.UsageCost>):
  Cost.calculate(SamplingValue, model, usage)

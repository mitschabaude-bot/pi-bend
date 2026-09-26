import Base
import ./types.bend as T
import ./image-models.generated.bend as Generated
import ../../runtime/src/record.bend as R

# upstream image-models.ts: lookups over the generated image catalog
# (IMAGE_MODELS), keyed by provider and then by model id.

def Model() -> Data: T.ImagesModel<T.JsonValue>

def modelId(model: Model()) -> String:
  match model:
    case T.ImagesModel{id, _, _, _, _, _, _, _, _, _, _, _, _}: id

def findModel(models: List<&2, Model()>, +id: String) -> Maybe<&2, Model()>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Unit -> Maybe<&2, Model()>, String.eq(modelId(model), id), _ => Some{model}, _ => findModel(rest, id))(Unit{})

def providerModels(value: Maybe<&2, List<&2, Model()>>) -> List<&2, Model()>:
  match value:
    case Some{models}: models
    case None{}: Nil{}

# upstream getImageModel; an unknown provider or id has no model.
def getImageModel(provider: String, id: String) -> Maybe<&2, Model()>:
  findModel(providerModels(R.get(List<&2, Model()>, Generated.IMAGE_MODELS(), provider)), id)

def propertyNames(entries: List<&2, R.Property<List<&2, Model()>>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, _} <> rest: name <> propertyNames(rest)

def recordNames(catalog: R.Record<List<&2, Model()>>) -> List<&2, String>:
  match catalog:
    case R.Record{entries}: propertyNames(entries)

def getImageProviders() -> List<&2, String>: recordNames(Generated.IMAGE_MODELS())

def getImageModels(provider: String) -> List<&2, Model()>:
  providerModels(R.get(List<&2, Model()>, Generated.IMAGE_MODELS(), provider))

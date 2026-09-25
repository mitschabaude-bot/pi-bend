import Base
import ../../core/model-runtime.bend as Models

# upstream model-search.ts: fuzzy search texts for models. An empty name is
# upstream's absent name.
type ModelSearchItem is Data: ModelSearchItem{id: String,provider: String,name: String}
def searchItem(+model: Models.Model()) -> ModelSearchItem: ModelSearchItem{Models.modelId(model),Models.modelProvider(model),Models.modelName(model)}
def named(+name: String) -> String: Bool.pick(String,String.is_empty(name),""," " ++ name)
def getModelSearchText(item: ModelSearchItem) -> String:
  match item:
    case ModelSearchItem{+id,+provider,name}: id ++ " " ++ provider ++ " " ++ provider ++ "/" ++ id ++ " " ++ provider ++ " " ++ id ++ named(name)
# The /model selector ranks exact provider-prefixed queries before proxy
# providers' ids (openrouter/openai/gpt-5), so the bare id does not lead.
def getModelSelectorSearchText(item: ModelSearchItem) -> String:
  match item:
    case ModelSearchItem{+id,+provider,name}: provider ++ " " ++ provider ++ "/" ++ id ++ " " ++ provider ++ " " ++ id ++ named(name)
def modelSelectorText(model: Models.Model()) -> String: getModelSelectorSearchText(searchItem(model))

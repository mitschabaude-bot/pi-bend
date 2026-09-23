import Base
import ../src/providers/google.models.bend as Models
import ../src/types.bend as T
import ../src/utils/model-json.bend as ModelJson
import ../src/utils/schema-json.bend as Schema
import ../src/utils/json.bend as Wire

def values(models: List<&2, T.Model<T.JsonValue>>) -> List<&2, T.JsonValue>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: Schema.toJson(ModelJson.model(model)) <> values(rest)

def main() -> IO(Unit):
  IO.print(Maybe.default(&2, String, Wire.stringify(T.JsonArray{values(Models.GOOGLE_MODELS())}), ""))

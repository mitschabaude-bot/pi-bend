import Base
import ../packages/ai/src/api/openai-codex-sessions.bend as Codex
import ../packages/ai/src/utils/json.bend as Wire
import ../packages/ai/src/utils/schema-json.bend as Schema
import ../packages/runtime/src/json.bend as JSON
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V

def continuationFields(body: Maybe<&2, V.Value>, id: Maybe<&2, V.Value>, items: Maybe<&2, V.Value>) -> Maybe<&2, Codex.CachedWebSocketContinuationState>:
  match body id items:
    case Some{V.ObjectValue{fields}} Some{V.Text{value}} Some{V.ArrayValue{values}}: Some{Codex.CachedWebSocketContinuationState{fields, value, values}}
    case _ _ _: None{}

def continuation(value: Maybe<&2, V.Value>) -> Maybe<&2, Codex.CachedWebSocketContinuationState>:
  match value:
    case Some{V.ObjectValue{+fields}}: continuationFields(R.get(V.Value, fields, "lastRequestBody"), R.get(V.Value, fields, "lastResponseId"), R.get(V.Value, fields, "lastResponseItems"))
    case _: None{}

def retainedFlag(value: Maybe<&2, Codex.CachedWebSocketContinuationState>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

def rendered(result: Codex.CachedWebSocketRequest) -> String:
  match result:
    case Codex.CachedWebSocketRequest{body, retained}:
      Maybe.default(&2, String, Wire.stringify(Schema.toJson(V.ObjectValue{R.Record{R.Property{"body", V.ObjectValue{body}} <> R.Property{"retained", V.Boolean{retainedFlag(retained)}} <> Nil{}}})), "error")

def prepared(body: Maybe<&2, V.Value>, retained: Maybe<&2, Codex.CachedWebSocketContinuationState>) -> IO(Unit):
  match body:
    case Some{V.ObjectValue{fields}}: IO.print(rendered(Codex.buildCachedWebSocketRequestBody(fields, retained)))
    case _: IO.print("invalid fixture")

def parsed(value: Result<&2, &2, JSON.ParseError, V.Value>) -> IO(Unit):
  match value:
    case Done{V.ObjectValue{+fields}}: prepared(R.get(V.Value, fields, "body"), continuation(R.get(V.Value, fields, "continuation")))
    case _: IO.print("invalid fixture")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        parsed(JSON.parse(head))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)

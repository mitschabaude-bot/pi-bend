import Base
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/model-api.bend as ModelApi
import ../../runtime/src/f64.bend as F
import ../src/core/agent-runtime.bend as Runtime

# upstream "is registered as a builtin api provider" (pi-messages.test.ts and
# the registrations the other api suites rely on): the agent runtime streams
# a model of each api through its native provider instead of rejecting it.

def model(api: Ai.ModelApi) -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"model", "Model", api, "provider", "http://127.0.0.1:1", False{}, None{}, [Ai.InputText{}], None{}, Ai.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(1000), F.fromU32(100), None{}, None{}, None{}}

def registered(name: String, result: Result<&2, &2, String, Maybe<&2, Ai.Model<Ai.JsonValue>>>) -> IO(Unit):
  match result:
    case Done{_}: IO.print("PASS " ++ name ++ " is registered as a builtin api provider")
    case Fail{message}: IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ message)

def check(+name: String) -> IO(Unit):
  +api = ModelApi.fromString(name)
  registered(name, Runtime.supportedApi(api, model(api)))

def main() -> IO(Unit):
  do IO<Unit>:
    check("pi-messages")
    check("mistral-conversations")
    check("bedrock-converse-stream")
    check("google-vertex")

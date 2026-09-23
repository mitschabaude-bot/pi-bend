import Base
import ../src/api/google-generative-ai.bend as Google
import ../src/api/google-generative-ai-stream.bend as Stream
import ../src/providers/google.models.bend as Models
import ../src/types.bend as T
import ../src/utils/json.bend as Wire
import ../../runtime/src/f64.bend as F
import ../../runtime/src/schema-value.bend as V

def model() -> T.Model<T.JsonValue>: Models.model_gemini_2_5_flash()

def assistant() -> T.AssistantMessage<V.Value, Unit>:
  T.AssistantMessage{T.AssistantThinking{T.ThinkingContent{"reasoning", Some{"c2ln"}, None{}}} <> T.AssistantText{T.TextContent{"", Some{"c2ln"}}} <> Nil{}, "google-generative-ai", "google", "gemini-2.5-flash", None{}, None{}, None{}, None{}, Stream.emptyUsage(), T.Stop{}, None{}, None{}, None{}, None{}, F.fromU32(2)}

def context() -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  T.TranscriptContext{T.User{T.UserMessage{T.UserText{"ping"}, F.fromU32(1)}} <> T.Assistant{assistant()} <> Nil{}}

def main() -> IO(Unit):
  IO.print(Maybe.default(&2, String, Wire.stringify(Google.buildParams(Unit, Unit, model(), context(), Google.Options{None{}, None{}, Google.NoThinking{}, None{}})), ""))

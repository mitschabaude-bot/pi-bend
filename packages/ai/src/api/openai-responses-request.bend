import Base
import ../types.bend as T
import ../utils/transcript.bend as Transcript
import ./openai-responses-shared.bend as Shared
import ./openai-responses-policy.bend as Policy
import ./openai-responses-params.bend as Params
import ./constrained-sampling.bend as Sampling
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R

type BuildError is Data:
  MessageConversion{error: Shared.MessageError}
  ToolConversion{error: Sampling.Error}

def OPENAI_TOOL_CALL_PROVIDERS() -> List<&2, String>:
  "openai" <> "openai-codex" <> "opencode" <> Nil{}

def toolOptions(compat: Policy.ResolvedCompat) -> Shared.ConvertResponsesToolsOptions:
  match compat:
    case Policy.ResolvedCompat{_, _, _, _, strict, grammar, _, _, _, _}: Shared.ConvertResponsesToolsOptions{None{}, Some{strict}, Some{grammar}, None{}}

def messageOptions(+compat: Policy.ResolvedCompat, grammar: R.Record<String>) -> Shared.ConvertResponsesMessagesOptions:
  match compat:
    case Policy.ResolvedCompat{_, midConvo, _, _, strict, grammarSupport, additional, search, _, _}:
      Shared.ConvertResponsesMessagesOptions{None{}, Some{grammar}, Some{midConvo}, Some{additional}, Some{search}, Some{Shared.ConvertResponsesToolsOptions{None{}, Some{strict}, Some{grammarSupport}, None{}}}}

def requestTools(-G: Data, -D: Data, context: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, compat: Policy.ResolvedCompat) -> Transcript.TranscriptTools<V.Value>:
  match context compat:
    case T.TranscriptContext{messages} Policy.ResolvedCompat{_, _, _, _, _, _, additional, search, _, _}: Transcript.resolveTranscriptTools(V.Value, R.Record<V.Value>, G, D, messages, additional || search)

def inputJson(items: List<&2, Shared.ResponseInputItem>) -> List<&2, T.JsonValue>:
  match items:
    case Nil{}: Nil{}
    case head <> rest: Shared.inputItemToJson(head) <> inputJson(rest)

def toolsJson(items: List<&2, Shared.OpenAITool>) -> List<&2, T.JsonValue>:
  match items:
    case Nil{}: Nil{}
    case head <> rest: Shared.toolToJson(head) <> toolsJson(rest)

def assembled(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, model: Params.RequestModel, input: List<&2, Shared.ResponseInputItem>, tools: Result<&2, &2, Sampling.Error, List<&2, Shared.OpenAITool>>, options: Params.RequestOptions<Choice>, compat: Policy.ResolvedCompat, retention: T.CacheRetention) -> Result<&2, &2, BuildError, T.JsonValue>:
  match tools:
    case Fail{error}: Fail{ToolConversion{error}}
    case Done{values}: Done{Params.buildConvertedParams(~Choice, ~encodeChoice, model, inputJson(input), toolsJson(values), options, compat, retention)}

def converted(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, model: Params.RequestModel, input: Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>>, tools: Transcript.TranscriptTools<V.Value>, options: Params.RequestOptions<Choice>, +compat: Policy.ResolvedCompat, retention: T.CacheRetention) -> Result<&2, &2, BuildError, T.JsonValue>:
  match input tools:
    case Fail{error} _: Fail{MessageConversion{error}}
    case Done{items} Transcript.TranscriptTools{values, _}: assembled(~Choice, ~encodeChoice, model, items, Shared.convertResponsesTools(values, Some{toolOptions(compat)}), options, compat, retention)

# The provider resolves compatibility, grammar declarations and cache retention
# before calling this builder, as its upstream stream entry point does. Fetch,
# hooks and retries remain the wrapper's responsibility.
def buildParams(~Choice: Data, ~encodeChoice: Choice -> T.JsonValue, ~G: Data, ~D: Data, ~J: Data, +model: T.Model<J>, +context: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, options: Params.RequestOptions<Choice>, +compat: Policy.ResolvedCompat, grammar: R.Record<String>, retention: T.CacheRetention) -> IO(Result<&2, &2, BuildError, T.JsonValue>):
  do IO<Result<&2, &2, BuildError, T.JsonValue>>:
    tools : Transcript.TranscriptTools<V.Value> = requestTools(G, D, context, compat)
    input : Result<&2, &2, Shared.MessageError, List<&2, Shared.ResponseInputItem>> <- Shared.convertResponsesMessages(~G, ~D, ~J, model, context, OPENAI_TOOL_CALL_PROVIDERS(), Some{messageOptions(compat, grammar)})
    return converted(~Choice, ~encodeChoice, Params.requestModel(J, model), input, tools, options, compat, retention)

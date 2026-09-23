import Base
import ../types.bend as T

def name(api: T.ModelApi) -> String:
  match api:
    case T.OpenAICompletionsApi{}: "openai-completions"
    case T.OpenAIResponsesApi{}: "openai-responses"
    case T.AzureOpenAIResponsesApi{}: "azure-openai-responses"
    case T.OpenAICodexResponsesApi{}: "openai-codex-responses"
    case T.AnthropicMessagesApi{}: "anthropic-messages"
    case T.BedrockConverseStreamApi{}: "bedrock-converse-stream"
    case T.MistralConversationsApi{}: "mistral-conversations"
    case T.GoogleGenerativeAiApi{}: "google-generative-ai"
    case T.GoogleVertexApi{}: "google-vertex"
    case T.PiMessagesApi{}: "pi-messages"
    case T.CustomModelApi{identifier}: identifier

# Known names select their precise compatibility type; all other names remain
# open custom API identifiers. Prefer this constructor for runtime string input.
def fromString(+identifier: String) -> T.ModelApi:
  Bool.pick(T.ModelApi, String.eq(identifier, "openai-completions"), T.OpenAICompletionsApi{},
  Bool.pick(T.ModelApi, String.eq(identifier, "openai-responses"), T.OpenAIResponsesApi{},
  Bool.pick(T.ModelApi, String.eq(identifier, "azure-openai-responses"), T.AzureOpenAIResponsesApi{},
  Bool.pick(T.ModelApi, String.eq(identifier, "openai-codex-responses"), T.OpenAICodexResponsesApi{},
  Bool.pick(T.ModelApi, String.eq(identifier, "anthropic-messages"), T.AnthropicMessagesApi{},
  Bool.pick(T.ModelApi, String.eq(identifier, "bedrock-converse-stream"), T.BedrockConverseStreamApi{},
  Bool.pick(T.ModelApi, String.eq(identifier, "mistral-conversations"), T.MistralConversationsApi{},
  Bool.pick(T.ModelApi, String.eq(identifier, "google-generative-ai"), T.GoogleGenerativeAiApi{},
  Bool.pick(T.ModelApi, String.eq(identifier, "google-vertex"), T.GoogleVertexApi{},
  Bool.pick(T.ModelApi, String.eq(identifier, "pi-messages"), T.PiMessagesApi{}, T.CustomModelApi{identifier}))))))))))

def modelApi(-SamplingValue: Data, model: T.Model<SamplingValue>) -> T.ModelApi:
  match model:
    case T.Model{_, _, api, _, _, _, _, _, _, _, _, _, _, _, _, _}: api

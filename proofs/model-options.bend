import Base
import ../laws/model-options.bend as Laws
import ../packages/ai/src/api/options.bend as Options
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses.bend as Responses
import ../packages/ai/src/api/openai-codex-responses.bend as Codex
import ../packages/ai/src/api/azure-openai-responses.bend as Azure
import ../packages/ai/src/api/anthropic-messages.bend as Anthropic
import ../packages/ai/src/api/google-generative-ai.bend as Google
import ../packages/ai/src/api/google-vertex.bend as Vertex
import ../packages/ai/src/api/openai-completions.bend as Completions
import ../packages/ai/src/api/mistral-conversations.bend as Mistral
import ../packages/ai/src/api/bedrock-converse-stream.bend as Bedrock
import ../packages/ai/src/api/pi-messages.bend as Pi

def Laws.successive_auth_updates_do_not_accumulate_changes(Error, options, first, last):
  match options first last:
    case Options.SimpleOptions{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.CommonOptions{_}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.ResponsesOptions{Responses.OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.CodexOptions{Codex.OpenAICodexResponsesOptions{_, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.AzureOptions{Azure.AzureOpenAIResponsesOptions{_, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.AnthropicOptions{Anthropic.AnthropicOptions{_, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.GoogleOptions{Google.GoogleOptions{_, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.CompletionsOptions{Completions.OpenAICompletionsOptions{_, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.MistralOptions{Mistral.MistralOptions{_, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.BedrockOptions{Bedrock.BedrockOptions{_, _, _, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.PiOptions{Pi.PiMessagesOptions{_, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.VertexOptions{Vertex.GoogleVertexOptions{Google.GoogleOptions{_, _, _}, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}

def Laws.common_fields_reach_the_provider_without_loss(Error, options, base):
  match options base:
    case Options.SimpleOptions{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.CommonOptions{_}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.ResponsesOptions{Responses.OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.CodexOptions{Codex.OpenAICodexResponsesOptions{_, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.AzureOptions{Azure.AzureOpenAIResponsesOptions{_, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.AnthropicOptions{Anthropic.AnthropicOptions{_, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.GoogleOptions{Google.GoogleOptions{_, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.CompletionsOptions{Completions.OpenAICompletionsOptions{_, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.MistralOptions{Mistral.MistralOptions{_, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.BedrockOptions{Bedrock.BedrockOptions{_, _, _, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.PiOptions{Pi.PiMessagesOptions{_, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.VertexOptions{Vertex.GoogleVertexOptions{Google.GoogleOptions{_, _, _}, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}

def Laws.replacing_common_fields_cannot_discard_provider_configuration(Error, options, replacement):
  match options replacement:
    case Options.SimpleOptions{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.CommonOptions{_}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.ResponsesOptions{Responses.OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.CodexOptions{Codex.OpenAICodexResponsesOptions{_, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.AzureOptions{Azure.AzureOpenAIResponsesOptions{_, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.AnthropicOptions{Anthropic.AnthropicOptions{_, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.GoogleOptions{Google.GoogleOptions{_, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.CompletionsOptions{Completions.OpenAICompletionsOptions{_, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.MistralOptions{Mistral.MistralOptions{_, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.BedrockOptions{Bedrock.BedrockOptions{_, _, _, _, _, _, _, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.PiOptions{Pi.PiMessagesOptions{_, _, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}
    case Options.RawOptions{Options.VertexOptions{Vertex.GoogleVertexOptions{Google.GoogleOptions{_, _, _}, _, _}}} T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}


import Base
import ./openai-responses.bend as Responses
import ./openai-codex-responses.bend as Codex
import ./azure-openai-responses.bend as Azure
import ./anthropic-messages.bend as Anthropic
import ./anthropic-messages-client.bend as AnthropicClient
import ./google-generative-ai.bend as Google
import ./google-vertex.bend as Vertex
import ./openai-completions.bend as Completions
import ./mistral-conversations.bend as Mistral
import ./bedrock-converse-stream.bend as Bedrock
import ./pi-messages.bend as Pi
import ../types.bend as T
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/fetch.bend as Fetch

# Canonical native API options. The error parameter belongs to injected request
# hooks; provider-specific options retain their typed fields through auth/routing.
def StreamOptions(-Error: Data) -> Data: T.SimpleStreamOptions<T.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error>
def BaseOptions(-Error: Data) -> Data: T.StreamOptions<T.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error>

type ApiStreamOptions<-Error: Data> is Data:
  CommonOptions{base: BaseOptions(Error)}
  ResponsesOptions{options: Responses.OpenAIResponsesOptions<Unit, Unit, Error>}
  CodexOptions{options: Codex.OpenAICodexResponsesOptions<Unit, Unit, Error>}
  AzureOptions{options: Azure.AzureOpenAIResponsesOptions<Unit, Unit, Error>}
  AnthropicOptions{options: AnthropicClient.Options(Unit, Unit, Error)}
  GoogleOptions{options: Google.GoogleOptions<Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error>}
  VertexOptions{options: Vertex.Options(Unit, Unit, Error)}
  CompletionsOptions{options: Completions.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error)}
  MistralOptions{options: Mistral.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error)}
  BedrockOptions{options: Bedrock.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error)}
  PiOptions{options: Pi.Options(Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error)}

type RequestOptions<-Error: Data> is Data:
  SimpleOptions{options: StreamOptions(Error)}
  RawOptions{options: ApiStreamOptions<Error>}

def emptyBase(-Error: Data) -> BaseOptions(Error): T.toStreamOptions(T.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error, T.emptySimpleStreamOptions(T.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error))

def rawBase(-Error: Data, options: ApiStreamOptions<Error>) -> BaseOptions(Error):
  match options:
    case CommonOptions{base}: base
    case ResponsesOptions{value}: Responses.toStreamOptions(Unit, Unit, Error, value)
    case CodexOptions{Codex.OpenAICodexResponsesOptions{base, _, _, _, _, _}}: base
    case AzureOptions{Azure.AzureOpenAIResponsesOptions{base, _, _, _, _, _, _, _}}: base
    case AnthropicOptions{Anthropic.AnthropicOptions{base, _, _, _, _, _, _, _}}: base
    case GoogleOptions{Google.GoogleOptions{base, _, _}}: base
    case VertexOptions{Vertex.GoogleVertexOptions{Google.GoogleOptions{base, _, _}, _, _}}: base
    case CompletionsOptions{Completions.OpenAICompletionsOptions{base, _, _, _}}: base
    case MistralOptions{Mistral.MistralOptions{base, _, _, _}}: base
    case BedrockOptions{Bedrock.BedrockOptions{base, _, _, _, _, _, _, _, _, _}}: base
    case PiOptions{Pi.PiMessagesOptions{base, _, _, _}}: base

def withRawBase(-Error: Data, options: ApiStreamOptions<Error>, base: BaseOptions(Error)) -> ApiStreamOptions<Error>:
  match options:
    case CommonOptions{_}: CommonOptions{base}
    case ResponsesOptions{value}: ResponsesOptions{Responses.fromStreamOptions(Unit, Unit, Error, base, Responses.settings(Unit, Unit, Error, value))}
    case CodexOptions{Codex.OpenAICodexResponsesOptions{_, effort, summary, tier, verbosity, choice}}: CodexOptions{Codex.OpenAICodexResponsesOptions{base, effort, summary, tier, verbosity, choice}}
    case AzureOptions{Azure.AzureOpenAIResponsesOptions{_, effort, choice, summary, version, resource, url, deployment}}: AzureOptions{Azure.AzureOpenAIResponsesOptions{base, effort, choice, summary, version, resource, url, deployment}}
    case AnthropicOptions{Anthropic.AnthropicOptions{_, thinking, budget, effort, display, interleaved, choice, client}}: AnthropicOptions{Anthropic.AnthropicOptions{base, thinking, budget, effort, display, interleaved, choice, client}}
    case GoogleOptions{Google.GoogleOptions{_, choice, thinking}}: GoogleOptions{Google.GoogleOptions{base, choice, thinking}}
    case VertexOptions{Vertex.GoogleVertexOptions{Google.GoogleOptions{_, choice, thinking}, project, location}}: VertexOptions{Vertex.GoogleVertexOptions{Google.GoogleOptions{base, choice, thinking}, project, location}}
    case CompletionsOptions{Completions.OpenAICompletionsOptions{_, choice, effort, budgets}}: CompletionsOptions{Completions.OpenAICompletionsOptions{base, choice, effort, budgets}}
    case MistralOptions{Mistral.MistralOptions{_, choice, mode, effort}}: MistralOptions{Mistral.MistralOptions{base, choice, mode, effort}}
    case BedrockOptions{Bedrock.BedrockOptions{_, region, profile, choice, effort, budgets, interleaved, display, metadata, bearer}}: BedrockOptions{Bedrock.BedrockOptions{base, region, profile, choice, effort, budgets, interleaved, display, metadata, bearer}}
    case PiOptions{Pi.PiMessagesOptions{_, effort, choice, debug}}: PiOptions{Pi.PiMessagesOptions{base, effort, choice, debug}}

# Built-in raw options have API-specific defaults, independent of simple
# reasoning conversion. A typed option record for another API is rejected.
def optionsForApi(-Error: Data, api: T.ModelApi, options: ApiStreamOptions<Error>) -> Result<&2, &2, String, ApiStreamOptions<Error>>:
  match api options:
    case T.OpenAIResponsesApi{} CommonOptions{base}: Done{ResponsesOptions{Responses.fromStreamOptions(Unit, Unit, Error, base, Responses.ResponsesSettings{None{}, None{}, None{}, None{}})}}
    case T.OpenAICodexResponsesApi{} CommonOptions{base}: Done{CodexOptions{Codex.OpenAICodexResponsesOptions{base, None{}, None{}, None{}, None{}, None{}}}}
    case T.AzureOpenAIResponsesApi{} CommonOptions{base}: Done{AzureOptions{Azure.AzureOpenAIResponsesOptions{base, None{}, None{}, None{}, None{}, None{}, None{}, None{}}}}
    case T.AnthropicMessagesApi{} CommonOptions{base}: Done{AnthropicOptions{Anthropic.AnthropicOptions{base, None{}, None{}, None{}, None{}, None{}, None{}, None{}}}}
    case T.GoogleGenerativeAiApi{} CommonOptions{base}: Done{GoogleOptions{Google.GoogleOptions{base, None{}, None{}}}}
    case T.GoogleVertexApi{} CommonOptions{base}: Done{VertexOptions{Vertex.GoogleVertexOptions{Google.GoogleOptions{base, None{}, None{}}, None{}, None{}}}}
    case T.OpenAICompletionsApi{} CommonOptions{base}: Done{CompletionsOptions{Completions.OpenAICompletionsOptions{base, None{}, None{}, None{}}}}
    case T.MistralConversationsApi{} CommonOptions{base}: Done{MistralOptions{Mistral.MistralOptions{base, None{}, None{}, None{}}}}
    case T.BedrockConverseStreamApi{} CommonOptions{base}: Done{BedrockOptions{Bedrock.BedrockOptions{base, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}}}
    case T.PiMessagesApi{} CommonOptions{base}: Done{PiOptions{Pi.PiMessagesOptions{base, None{}, None{}, None{}}}}
    case T.OpenAIResponsesApi{} ResponsesOptions{value}: Done{ResponsesOptions{value}}
    case T.OpenAICodexResponsesApi{} CodexOptions{value}: Done{CodexOptions{value}}
    case T.AzureOpenAIResponsesApi{} AzureOptions{value}: Done{AzureOptions{value}}
    case T.AnthropicMessagesApi{} AnthropicOptions{value}: Done{AnthropicOptions{value}}
    case T.GoogleGenerativeAiApi{} GoogleOptions{value}: Done{GoogleOptions{value}}
    case T.GoogleVertexApi{} VertexOptions{value}: Done{VertexOptions{value}}
    case T.OpenAICompletionsApi{} CompletionsOptions{value}: Done{CompletionsOptions{value}}
    case T.MistralConversationsApi{} MistralOptions{value}: Done{MistralOptions{value}}
    case T.BedrockConverseStreamApi{} BedrockOptions{value}: Done{BedrockOptions{value}}
    case T.PiMessagesApi{} PiOptions{value}: Done{PiOptions{value}}
    case T.CustomModelApi{_} CommonOptions{base}: Done{CommonOptions{base}}
    case _ _: Fail{"Raw stream options do not match the model API"}

def requestBase(-Error: Data, options: RequestOptions<Error>) -> BaseOptions(Error):
  match options:
    case SimpleOptions{value}: T.toStreamOptions(T.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error, value)
    case RawOptions{value}: rawBase(Error, value)

def withRequestBase(-Error: Data, options: RequestOptions<Error>, base: BaseOptions(Error)) -> RequestOptions<Error>:
  match options base:
    case RawOptions{value} base: RawOptions{withRawBase(Error, value, base)}
    case SimpleOptions{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, choice, reasoning, deferred, budgets}} T.StreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, tokens, transport, retention, session, connect, metadata}:
      SimpleOptions{T.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, tokens, transport, retention, session, connect, metadata, choice, reasoning, deferred, budgets}}

# Simple-only consumers explicitly select the simple variant; no raw options
# are projected through the simple reasoning conversion.
def simpleOptions(-Error: Data, options: Maybe<&2, RequestOptions<Error>>) -> Maybe<&2, StreamOptions(Error)>:
  match options:
    case Some{SimpleOptions{value}}: Some{value}
    case _: None{}

import Base
import ../packages/ai/src/api/openai-completions.bend as Completions

# Chat Completions compatibility detection (upstream detectCompat).

# The behaviors a model must opt into through compat, and the two it keeps
# unless compat turns them off.
type OptInFeatures is Data:
  OptInFeatures{requiresToolResultName: Bool, requiresAssistantAfterToolResult: Bool, requiresThinkingAsText: Bool, zaiToolStream: Bool, supportsThinkingTokenBudget: Bool, supportsOpenAIGrammarTools: Bool, supportsMidConvoSystemMessages: Bool, supportsMidConvoToolAdditions: Bool, supportsStrictMode: Bool, vllmPriority: Maybe<&2, F64>, supportsUsageInStreaming: Bool, supportsFinishReason: Bool}

def optInFeatures(+compat: Completions.Compat()) -> OptInFeatures:
  OptInFeatures{Completions.requiresToolResultName(compat), Completions.requiresAssistantAfterToolResult(compat), Completions.requiresThinkingAsText(compat), Completions.zaiToolStream(compat), Completions.supportsThinkingTokenBudget(compat), Completions.supportsOpenAIGrammarTools(compat), Completions.supportsMidConvoSystemMessages(compat), Completions.supportsMidConvoToolAdditions(compat), Completions.supportsStrictMode(compat), Completions.vllmPriority(compat), Completions.supportsUsageInStreaming(compat), Completions.supportsFinishReason(compat)}

# Detection is conservative: whatever the provider, base URL and model id,
# it never enables a behavior that must be opted into explicitly (strict or
# grammar tools, tool streaming, mid-conversation updates, provider-specific
# message rewrites or vLLM priority), and it keeps usage streaming and the
# finish_reason requirement.

law detection_never_enables_opt_in_features:
  for provider: String
  for baseUrl: String
  for id: String
  {optInFeatures(Completions.detectFor(provider, baseUrl, id)) == OptInFeatures{False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, None{}, True{}, True{}} : OptInFeatures}

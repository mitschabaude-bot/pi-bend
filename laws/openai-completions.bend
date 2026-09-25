import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-completions.bend as Completions
import ../packages/runtime/src/record.bend as R

# Chat Completions compatibility resolution (upstream getCompat/detectCompat).
# getCompat overrides detection field by field with model.compat (`??`): an
# empty compat object keeps every detected value, a fully explicit one
# decides every field regardless of detection.

def emptyCompat() -> T.OpenAICompletionsCompat:
  T.OpenAICompletionsCompat{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

law empty_compat_keeps_detection:
  for detected: Completions.Compat()
  {Completions.overrideCompat(T.OpenAICompletionsApi{}, Some{emptyCompat()}, detected) == detected : Completions.Compat()}

law explicit_compat_decides_every_field:
  for v0: Bool
  for v1: Bool
  for v2: Bool
  for v3: Bool
  for v4: Bool
  for v5: T.MaxTokensField
  for v6: Bool
  for v7: Bool
  for v8: Bool
  for v9: Bool
  for v10: T.ThinkingFormat
  for v11: R.Record<T.ChatTemplateKwargValue>
  for v12: R.Record<T.ChatTemplateKwargValue>
  for v13: T.OpenRouterRouting
  for v14: T.VercelGatewayRouting
  for v15: Bool
  for v16: T.ThinkingTokenBudgetField
  for v17: Bool
  for v18: Bool
  for v19: Bool
  for v20: Bool
  for v21: Bool
  for v22: T.CacheControlFormat
  for v23: Bool
  for v24: T.SessionAffinityFormat
  for v25: Bool
  for v26: F64
  for detected: Completions.Compat()
  {Completions.overrideCompat(T.OpenAICompletionsApi{}, Some{T.OpenAICompletionsCompat{Some{v0}, Some{v1}, Some{v2}, Some{v3}, Some{v4}, Some{v5}, Some{v6}, Some{v7}, Some{v8}, Some{v9}, Some{v10}, Some{v11}, Some{v12}, Some{v13}, Some{v14}, Some{v15}, Some{v16}, Some{v17}, Some{v18}, Some{v19}, Some{v20}, Some{v21}, Some{v22}, Some{v23}, Some{v24}, Some{v25}, Some{v26}}}, detected) == Completions.ResolvedOpenAICompletionsCompat{v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15, Some{v16}, v17, v18, v19, v20, v21, Some{v22}, v23, v24, v25, Some{v26}} : Completions.Compat()}

# Detection is conservative: whatever the provider, base URL and model id,
# it never enables a behavior that must be opted into explicitly (strict or
# grammar tools, tool streaming, mid-conversation updates, provider-specific
# message rewrites or vLLM priority), and it keeps usage streaming and the
# finish_reason requirement.

law detection_never_enables_opt_in_features:
  for provider: String
  for baseUrl: String
  for id: String
  {Completions.optInFeatures(Completions.detectFor(provider, baseUrl, id)) == Completions.OptInFeatures{False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, None{}, True{}, True{}} : Completions.OptInFeatures}

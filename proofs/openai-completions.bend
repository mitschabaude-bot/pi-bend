import Base
import ../laws/openai-completions.bend as Laws
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-completions.bend as Completions

def Laws.empty_compat_keeps_detection(detected):
  match detected:
    case Completions.ResolvedOpenAICompletionsCompat{d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, d14, d15, d16, d17, d18, d19, d20, d21, d22, d23, d24, d25, d26}: {==}

def Laws.explicit_compat_decides_every_field(v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15, v16, v17, v18, v19, v20, v21, v22, v23, v24, v25, v26, detected):
  match detected:
    case Completions.ResolvedOpenAICompletionsCompat{d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, d14, d15, d16, d17, d18, d19, d20, d21, d22, d23, d24, d25, d26}: {==}

def Laws.detection_never_enables_opt_in_features(provider, baseUrl, id): {==}

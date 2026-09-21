import Base
import ../packages/ai/src/api/openai-responses-preparation-error.bend as Format
import ../packages/ai/src/api/openai-responses-prepare.bend as Preparation
import ../packages/ai/src/api/openai-responses-request.bend as Request
import ../packages/ai/src/api/openai-responses-shared.bend as Shared
import ../packages/ai/src/api/openai-responses-assistant.bend as Assistant
import ../packages/ai/src/api/openai-responses-auth.bend as Auth
import ../packages/ai/src/api/constrained-sampling.bend as Sampling

# A tool's diagnostic is stable regardless of whether conversion fails during
# grammar discovery, top-level tools, transcript tools or assistant replay.
law grammar_diagnostic_is_stage_independent:
  for cause: Sampling.Error
  {Format.format(Preparation.GrammarFailure{cause}) == Format.format(Preparation.PayloadFailure{Request.ToolConversion{cause}}) : String}

law transcript_tool_diagnostic_is_stage_independent:
  for cause: Sampling.Error
  {Format.format(Preparation.PayloadFailure{Request.MessageConversion{Shared.ToolConversion{cause}}}) == Sampling.errorMessage(cause) : String}

law replay_grammar_diagnostic_is_stage_independent:
  for cause: Sampling.Error
  {Format.format(Preparation.PayloadFailure{Request.MessageConversion{Shared.AssistantConversion{Assistant.InvalidGrammarInput{cause}}}}) == Sampling.errorMessage(cause) : String}

law credentials_keep_provider_diagnostic:
  for cause: Auth.CredentialError
  {Format.format(Preparation.CredentialFailure{cause}) == Auth.errorMessage(cause) : String}

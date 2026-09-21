import Base
import ../packages/ai/src/api/openai-responses-prepare.bend as P
import ../laws/openai-responses-prepare.bend as Laws

def Laws.failed_payload_preserves_cause(apiKey, baseUrl, headers, compat, fields, retention, cause): {==}
def Laws.successful_preparation_preserves_all_fields(apiKey, baseUrl, headers, compat, fields, retention, payload): {==}
def Laws.credential_failure_has_no_effects(model, context, body, configuration, userAgent, headers, retention, env, cause):
  match configuration:
    case P.ModelSettings{_, _, _, _}: {==}
def Laws.grammar_failure_has_no_effects(model, context, body, configuration, userAgent, headers, apiKey, retention, cause):
  match configuration:
    case P.ModelSettings{_, _, _, _}: {==}

def Laws.responses_model_preserves_configuration(provider, baseUrl, headers, compat): {==}
def Laws.custom_api_is_rejected(identifier, provider, baseUrl, headers, compat): {==}

def Laws.omitted_string_preserves_object(fields, key): {==}
def Laws.explicit_null_replaces_field(fields, key): {==}
def Laws.explicit_string_replaces_field(fields, key, value): {==}

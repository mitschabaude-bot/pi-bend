import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses.bend as P
import ../laws/openai-responses.bend as Laws

def Laws.cancellation_precedes_stop_validation(Reason, E, reason, api, detail): {==}
def Laws.pending_stop_is_missing(Reason, E, api, detail): {==}
def Laws.failure_keeps_cause_under_cancellation(G, provider, output, aborted, cause): {==}
def Laws.failure_preserves_message_fields(G, content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp, aborted, detail): {==}
def Laws.disposal_failure_never_replaces_processing_outcome(Reason, G, E, output, error, cause): {==}
def Laws.supplied_signal_is_never_disposed(Reason, signal): {==}
def Laws.cancelled_request_never_opens_transport(config, hooks, model, options, custom, hook, output, events, parent, retry, request): {==}
def Laws.rejected_request_never_opens_transport(config, hooks, model, options, custom, hook, output, events, parent, retry, cause): {==}
def Laws.acquisition_failure_skips_hooks(config, hooks, model, options, hook, output, events, cause): {==}

def Laws.responses_options_extend_stream_options(Reason, Telemetry, E, base, settings):
  match base settings:
    case T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} P.ResponsesSettings{_, _, _, _}: {==}

def Laws.responses_options_retain_settings(Reason, Telemetry, E, base, settings):
  match base settings:
    case T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} P.ResponsesSettings{_, _, _, _}: {==}

def Laws.responses_options_split_and_rejoin(Reason, Telemetry, E, options):
  match options:
    case P.OpenAIResponsesOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}

def Laws.disabled_caching_drops_session_affinity(sessionId): {==}
def Laws.explicit_retention_overrides_environment(value, env): {==}

def Laws.long_retention_header_requires_compat(developer, midConvo, affinity, strict, grammar, additional, search, explicit, maxOutput, retention):
  match explicit retention:
    case True{} T.CacheNone{}: {==}
    case True{} T.CacheShort{}: {==}
    case True{} T.CacheLong{}: {==}
    case False{} T.CacheNone{}: {==}
    case False{} T.CacheShort{}: {==}
    case False{} T.CacheLong{}: {==}

def Laws.explicit_cache_mode_supersedes_retention_header(developer, midConvo, affinity, longCache, strict, grammar, additional, search, maxOutput, retention):
  match longCache retention:
    case True{} T.CacheNone{}: {==}
    case True{} T.CacheShort{}: {==}
    case True{} T.CacheLong{}: {==}
    case False{} T.CacheNone{}: {==}
    case False{} T.CacheShort{}: {==}
    case False{} T.CacheLong{}: {==}

def Laws.absent_service_tier_keeps_usage(model, usage):
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}

def Laws.default_service_tier_keeps_usage(model, usage):
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}

def Laws.auto_service_tier_keeps_usage(model, usage):
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: {==}

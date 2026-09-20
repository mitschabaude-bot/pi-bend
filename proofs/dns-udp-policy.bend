import Base
import ../laws/dns-udp-policy.bend as Laws

def Laws.server_failure_retries(empty, truncated, ignore): {==}
def Laws.not_implemented_retries(empty, truncated, ignore): {==}
def Laws.refusal_retries(empty, truncated, ignore): {==}
def Laws.unhelpful_success_retries(truncated, ignore): {==}
def Laws.other_status_not_empty_failure(code, empty, truncated, ignore): {==}
def Laws.truncation_uses_tcp(code, empty): {==}
def Laws.ignore_truncation_accepts(code, empty, truncated):
  match truncated:
    case False{}: {==}
    case True{}: {==}
def Laws.useful_success_matches_other(code, truncated, ignore): {==}

def Laws.invalid_extension_stops_policy(header, ignore, error): {==}

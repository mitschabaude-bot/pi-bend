import Base
import ../laws/dns-transport.bend as Laws

# Dns transport choice

def Laws.forced_tcp(bytes): {==}
def Laws.empty_fits(budget):
  match budget:
    case Zero{}: {==}
    case Succ{_}: {==}
def Laws.exact_budget(prefix, suffix):
  match prefix suffix:
    case Nil{} Nil{}: {==}
    case Nil{} _ <> _: {==}
    case _ <> rest tail: Laws.exact_budget(rest, tail)
def Laws.invalid_encoding_stops_selection(forced, error): {==}


# Dns udp policy

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

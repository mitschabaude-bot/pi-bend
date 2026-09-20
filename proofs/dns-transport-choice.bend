import Base
import ../laws/dns-transport-choice.bend as Laws

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

import Base
import ../laws/dns-search-run.bend as Laws

def Laws.halt_is_terminal(Failure, Value, origin, cursor, history, failure): {==}
def Laws.answer_is_terminal(Failure, Value, origin, cursor, history, value): {==}
def Laws.initial_failure_precedence(initial, noData, serverFailure, last): {==}

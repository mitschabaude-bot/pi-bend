import Base
import ../laws/numeric-scope.bend as Laws

def Laws.failed_input_needs_no_lookup(E, error): {==}
def Laws.ipv4_needs_no_lookup(E, address): {==}
def Laws.unscoped_ipv6_needs_no_lookup(E, address): {==}
def Laws.scoped_ipv6_retains_request(E, address, zone): {==}
def Laws.failed_scope_is_terminal(E, address, error): {==}
def Laws.successful_scope_retained(E, address, index): {==}

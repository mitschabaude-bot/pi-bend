import Base
import ../laws/http-body-source.bend as Laws

def Laws.bytes_are_not_decoded_or_changed(T, E, map, bytes): {==}
def Laws.eof_is_not_an_empty_chunk(T, E, map): {==}
def Laws.read_failure_uses_the_mapping(T, E, map, error): {==}
def Laws.close_failure_uses_the_mapping(T, E, map, error): {==}
def Laws.closed_owner_release_has_no_transport_io(T, State, E, map, close, fields): {==}

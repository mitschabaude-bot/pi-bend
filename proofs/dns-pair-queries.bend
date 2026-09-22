import Base
import ../laws/dns-pair-queries.bend as Laws
import ../packages/runtime/src/dns-message.bend as Pair
import ../packages/runtime/src/dns-message.bend as Request
import ../packages/runtime/src/dns-message.bend as Edns

def Laws.shared_query_intent(options, id4, id6, name): {==}
def Laws.first_encoding_failure(queries, error, second):
  match second:
    case Fail{other}: {==}
    case Done{bytes}: {==}
def Laws.second_encoding_failure(queries, bytes, error): {==}

def Laws.valid_queries_retained(ipv4, ipv6, first, second, encoded4, encoded6):
  %Equal.sym(Result<&2, &2, Edns.EdnsError, List<&2, U32>>, Request.encodeQuery(ipv4), Done{first}, encoded4) : {Pair.checked(Pair.Queries{ipv4, ipv6}, _, Request.encodeQuery(ipv6)) == Done{Pair.Queries{ipv4, ipv6}} : Result<&2, &2, Pair.PairQueriesError, Pair.Queries>}
  %Equal.sym(Result<&2, &2, Edns.EdnsError, List<&2, U32>>, Request.encodeQuery(ipv6), Done{second}, encoded6) : {Pair.checked(Pair.Queries{ipv4, ipv6}, Done{first}, _) == Done{Pair.Queries{ipv4, ipv6}} : Result<&2, &2, Pair.PairQueriesError, Pair.Queries>}
  {==}

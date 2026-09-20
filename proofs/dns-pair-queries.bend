import Base
import ../laws/dns-pair-queries.bend as Laws
import ../packages/runtime/src/dns-pair-queries.bend as Pair
import ../packages/runtime/src/dns-query.bend as Request
import ../packages/runtime/src/dns-edns.bend as Edns

def Laws.shared_query_intent(options, id4, id6, name): {==}
def Laws.first_encoding_failure(queries, error, second):
  match second:
    case Fail{other}: {==}
    case Done{bytes}: {==}
def Laws.second_encoding_failure(queries, bytes, error): {==}

def Laws.valid_queries_retained(ipv4, ipv6, first, second, encoded4, encoded6):
  %Equal.sym(Result<&2, &2, Edns.Error, List<&2, U32>>, Request.encode(ipv4), Done{first}, encoded4) : {Pair.checked(Pair.Queries{ipv4, ipv6}, _, Request.encode(ipv6)) == Done{Pair.Queries{ipv4, ipv6}} : Result<&2, &2, Pair.Error, Pair.Queries>}
  %Equal.sym(Result<&2, &2, Edns.Error, List<&2, U32>>, Request.encode(ipv6), Done{second}, encoded6) : {Pair.checked(Pair.Queries{ipv4, ipv6}, Done{first}, _) == Done{Pair.Queries{ipv4, ipv6}} : Result<&2, &2, Pair.Error, Pair.Queries>}
  {==}

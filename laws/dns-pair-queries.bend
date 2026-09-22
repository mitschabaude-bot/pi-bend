import Base
import ../packages/runtime/src/dns-message.bend as Pair
import ../packages/runtime/src/dns-message.bend as Request
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/dns-message.bend as Edns

law shared_query_intent:
  for +options: Request.QueryOptions
  for +id4: U32
  for +id6: U32
  for +name: Name.Name
  {Pair.create(options, id4, id6, name) == Pair.Queries{Request.createQuery(options, id4, Message.Question{name, 1, 1}), Request.createQuery(options, id6, Message.Question{name, 28, 1})} : Pair.Queries}

law first_encoding_failure:
  for queries: Pair.Queries
  for +error: Edns.EdnsError
  for second: Result<&2, &2, Edns.EdnsError, List<&2, U32>>
  {Pair.checked(queries, Fail{error}, second) == Fail{Pair.Encoding{Pair.IPv4{}, error}} : Result<&2, &2, Pair.PairQueriesError, Pair.Queries>}

law second_encoding_failure:
  for queries: Pair.Queries
  for bytes: List<&2, U32>
  for +error: Edns.EdnsError
  {Pair.checked(queries, Done{bytes}, Fail{error}) == Fail{Pair.Encoding{Pair.IPv6{}, error}} : Result<&2, &2, Pair.PairQueriesError, Pair.Queries>}

law valid_queries_retained:
  for +ipv4: Request.Request
  for +ipv6: Request.Request
  for +first: List<&2, U32>
  for +second: List<&2, U32>
  for encoded4: {Request.encodeQuery(ipv4) == Done{first} : Result<&2, &2, Edns.EdnsError, List<&2, U32>>}
  for encoded6: {Request.encodeQuery(ipv6) == Done{second} : Result<&2, &2, Edns.EdnsError, List<&2, U32>>}
  {Pair.validate(Pair.Queries{ipv4, ipv6}) == Done{Pair.Queries{ipv4, ipv6}} : Result<&2, &2, Pair.PairQueriesError, Pair.Queries>}

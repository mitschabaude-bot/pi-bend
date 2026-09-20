import Base
import ./dns-query.bend as Query
import ./dns-edns.bend as Edns

type Mode is Data:
  UDP{}
  TCP{}

# Inspect at most budget+1 cells. A packet exactly at the budget still fits.
def oversized(budget: Nat, bytes: List<&2, U32>) -> Bool:
  match budget bytes:
    case _ Nil{}: False{}
    case Zero{} _ <> _: True{}
    case Succ{rest} _ <> tail: oversized(rest, tail)

def automatic(large: Bool) -> Mode:
  match large:
    case True{}: TCP{}
    case False{}: UDP{}

# Match the reference's initial 512-byte threshold, including EDNS bytes.
# Advertising a larger response size does not change the query-size cutoff.
def select(forced: Bool, bytes: List<&2, U32>) -> Mode:
  match forced:
    case True{}: TCP{}
    case False{}: automatic(oversized(512n, bytes))

def encoded(forced: Bool, result: Result<&2, &2, Edns.Error, List<&2, U32>>) -> Result<&2, &2, Edns.Error, Mode>:
  match result:
    case Fail{error}: Fail{error}
    case Done{bytes}: Done{select(forced, bytes)}

# Validate even forced-TCP requests before opening any transport.
def prepare(forced: Bool, request: Query.Request) -> Result<&2, &2, Edns.Error, Mode>:
  encoded(forced, Query.encode(request))

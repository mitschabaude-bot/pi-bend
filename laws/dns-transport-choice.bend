import Base
import ../packages/runtime/src/dns-transport.bend as Choice
import ../packages/runtime/src/dns-message.bend as Edns

def nonempty(values: List<&2, U32>) -> Bool:
  match values:
    case Nil{}: False{}
    case _ <> _: True{}

law forced_tcp:
  for bytes: List<&2, U32>
  {Choice.select(True{}, bytes) == Choice.TCP{} : Choice.Mode}

law empty_fits:
  for budget: Nat
  {Choice.oversized(budget, Nil{}) == False{} : Bool}

# For any prefix, a budget equal to its length permits exactly that prefix;
# every nonempty suffix exceeds it. This includes the 512/513 wire boundary.
law exact_budget:
  for +prefix: List<&2, U32>
  for +suffix: List<&2, U32>
  {Choice.oversized(List.length(&2, U32, prefix), List.append(&2, U32, prefix, suffix)) == nonempty(suffix) : Bool}

law invalid_encoding_stops_selection:
  for forced: Bool
  for +error: Edns.EdnsError
  {Choice.encodedTransportChoice(forced, Fail{error}) == Fail{error} : Result<&2, &2, Edns.EdnsError, Choice.Mode>}

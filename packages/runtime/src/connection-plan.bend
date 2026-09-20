import Base
import ./connection-addresses.bend as Candidates
import ./connection-order.bend as Order
import ./connection-driver.bend as Driver
import ./abortable-connect.bend as Connect

type Report<-Resolution: Data, -Reason: Data, -Value: Type> is Type:
  Unresolved{resolution: Resolution}
  Attempted{resolution: Resolution, connection: Driver.Report<Reason, Value>}

# Preserve the full resolution in both branches. No-address resolution never
# calls the connector. A connection failure retains its complete attempt log.
def executeWith(-Context: Data, -Resolution: Data, -Reason: Data, -Value: Type, connect: Context -> List<&2, Connect.Address> -> IO(Driver.Report<Reason, Value>), context: Context, preference: Order.Preference, plan: Candidates.Plan<Resolution>) -> IO(Report<Resolution, Reason, Value>):
  match plan:
    case Candidates.NoAddresses{resolution}: IO.pure(Report<Resolution, Reason, Value>, Unresolved{resolution})
    case Candidates.Addresses{resolution, candidates}:
      do IO<Report<Resolution, Reason, Value>>:
        connection : Driver.Report<Reason, Value> <- connect(context, Order.prepare(preference, candidates))
        return Attempted{resolution, connection}


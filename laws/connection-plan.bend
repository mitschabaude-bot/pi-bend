import Base
import ../packages/runtime/src/connection-plan.bend as HTTP
import ../packages/runtime/src/connection-driver.bend as Driver
import ../packages/runtime/src/connection-addresses.bend as Candidates
import ../packages/runtime/src/connection-order.bend as Order
import ../packages/runtime/src/abortable-connect.bend as Connect

# Equality of IO programs for arbitrary connectors: an unavailable resolution
# returns immediately, with its complete report, and cannot invoke a connector.
law unavailable_does_not_connect:
  for -Context: Data
  for -Resolution: Data
  for -Reason: Data
  for -Value: Type
  for connect: Context -> List<&2, Connect.Address> -> IO(Driver.Report<Reason, Value>)
  for context: Context
  for preference: Order.Preference
  for +resolution: Resolution
  {HTTP.executeWith(Context, Resolution, Reason, Value, connect, context, preference, Candidates.NoAddresses{resolution}) == IO.pure(HTTP.Report<Resolution, Reason, Value>, HTTP.Unresolved{resolution}) : IO(HTTP.Report<Resolution, Reason, Value>)}

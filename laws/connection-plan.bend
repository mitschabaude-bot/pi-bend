import Base
import ../packages/runtime/src/connection-driver.bend as HTTP
import ../packages/runtime/src/connection-driver.bend as Driver
import ../packages/runtime/src/connection-driver.bend as Candidates
import ../packages/runtime/src/connection-driver.bend as Order
import ../packages/runtime/src/socket.bend as Connect

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
  {HTTP.executeWith(Context, Resolution, Reason, Value, connect, context, preference, Candidates.NoAddresses{resolution}) == IO.pure(HTTP.PlanReport<Resolution, Reason, Value>, HTTP.Unresolved{resolution}) : IO(HTTP.PlanReport<Resolution, Reason, Value>)}

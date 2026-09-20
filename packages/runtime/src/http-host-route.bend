import Base
import ./url-host.bend as Host
import ./abortable-connect.bend as Connect

type Plan is Data:
  Numeric{address: Connect.Address}
  Lookup{name: String}
  Invalid{}

type Error is Data:
  InvalidHost{}

type Resolution<-Report: Data> is Data:
  NumericAddress{address: Connect.Address}
  Named{report: Report}

# Consume the normalized URL host without serializing or reparsing it. URL
# IPv6 literals have no interface zone. Empty/opaque hosts are invalid for HTTP.
def plan(host: Host.Host) -> Plan:
  match host:
    case Host.IPv4{address}: Numeric{Connect.V4{address}}
    case Host.IPv6{address}: Numeric{Connect.V6{address, 0}}
    case Host.Domain{SNil{}}: Invalid{}
    case Host.Domain{name}: Lookup{name}
    case _: Invalid{}

def execute(~Context: Data, ~Report: Data, ~lookup: Context -> String -> IO(Report), context: Context, plan: Plan) -> IO(Result<&2, &2, Error, Resolution<Report>>):
  match plan:
    case Invalid{}: IO.pure(Result<&2, &2, Error, Resolution<Report>>, Fail{InvalidHost{}})
    case Numeric{address}: IO.pure(Result<&2, &2, Error, Resolution<Report>>, Done{NumericAddress{address}})
    case Lookup{name}:
      do IO<Result<&2, &2, Error, Resolution<Report>>>:
        report : Report <- lookup(context, name)
        return Done{Named{report}}

def resolveWith(~Context: Data, ~Report: Data, ~lookup: Context -> String -> IO(Report), context: Context, host: Host.Host) -> IO(Result<&2, &2, Error, Resolution<Report>>):
  execute(~Context, ~Report, ~lookup, context, plan(host))

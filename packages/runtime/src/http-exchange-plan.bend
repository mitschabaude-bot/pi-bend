import Base
import ./http-url.bend as URL
import ./url-host.bend as Host

type Error is Data:
  TLSRequired{}
  InvalidReadSize{}

type Plan<-Request: Data> is Data:
  Rejected{error: Error}
  Start{host: Host.Host, port: U32, request: Request, maximum: U32}

# This cleartext adapter must never send HTTP bytes on a TLS endpoint. Request
# preparation has already supplied its authority/target; dialing uses host/port.
def prepare(-Request: Data, endpoint: URL.Endpoint, request: Request, maximum: U32) -> Plan<Request>:
  match endpoint maximum:
    case URL.Endpoint{URL.TLS{}, _, _, _, _} _: Rejected{TLSRequired{}}
    case URL.Endpoint{URL.Plaintext{}, _, _, _, _} 0: Rejected{InvalidReadSize{}}
    case URL.Endpoint{URL.Plaintext{}, host, port, _, _} size: Start{host, port, request, size}

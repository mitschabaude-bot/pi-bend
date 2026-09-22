import Base
import ../packages/runtime/src/http-message.bend as Plan
import ../packages/runtime/src/http-message.bend as URL
import ../packages/runtime/src/url-host.bend as Host

law tls_cannot_start_cleartext:
  for -R: Data
  for host: Host.Host
  for port: U32
  for authority: String
  for target: String
  for request: R
  for maximum: U32
  {Plan.prepareExchangePlan(R, URL.Endpoint{URL.TLS{}, host, port, authority, target}, request, maximum) == Plan.Rejected{Plan.TLSRequired{}} : Plan.Plan<R>}

law zero_read_size_cannot_start:
  for -R: Data
  for host: Host.Host
  for port: U32
  for authority: String
  for target: String
  for request: R
  {Plan.prepareExchangePlan(R, URL.Endpoint{URL.Plaintext{}, host, port, authority, target}, request, 0) == Plan.Rejected{Plan.InvalidReadSize{}} : Plan.Plan<R>}

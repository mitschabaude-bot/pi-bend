import Base
import ../../../runtime/src/http-exchange.bend as HTTP
import ../../../runtime/src/http-message.bend as Message
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/dns-resolver.bend as DNS
import ../../../runtime/src/connection-driver.bend as Connect

# upstream core/http-dispatcher.ts: the connection options of the coding
# agent's fetch runtime. The proxy half of configureHttpDispatcher and
# applyHttpProxySettings are packages/runtime/src/http-proxy.bend
# (Proxy.fromEnvironmentWith, given to Fetch.createWithProxy by
# agent-runtime's transport). The idle timeouts are request options here
# (agent-runtime requestDefaults), not dispatcher options.

# Node's 250 ms default can end valid connection attempts on high-latency
# routes: an attempt that is not the last candidate address gets two seconds
# before the next address is tried (undici connect.autoSelectFamilyAttemptTimeout).
def DEFAULT_AUTO_SELECT_FAMILY_ATTEMPT_TIMEOUT_MS() -> U32: 2000

def httpOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, DEFAULT_AUTO_SELECT_FAMILY_ATTEMPT_TIMEOUT_MS(), 16384, Response.Limits{8192n, 65536n, 100n, 8n, Message.Limits{8192n, 8192n, 65536n, 100n}}}

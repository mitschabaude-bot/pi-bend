import Base
import ../src/types.bend as T
import ../src/utils/node-http-proxy.bend as Proxy
import ./anthropic-messages-client.bend as TestClient
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/url.bend as URL

# `node-http-proxy <target> [scoped env JSON]`: resolveHttpProxyUrlForTarget
# under the process environment tests/node_http_proxy_check.py sets. Prints
# "none", "url <href>" or "error <message>".

def textFields(fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<String>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{name, V.Text{value}} <> rest: R.Property{name, value} <> textFields(rest)
    case _ <> rest: textFields(rest)

def scopedEnv(parsed: Result<&2, &2, Decode.ParseError, V.Value>) -> Maybe<&2, T.ProviderEnv()>:
  match parsed:
    case Done{V.ObjectValue{R.Record{fields}}}: Some{R.Record{textFields(fields)}}
    case _: None{}

def shown(result: Result<&2, &2, String, Maybe<&2, URL.URL>>) -> String:
  match result:
    case Fail{message}: "error " ++ message
    case Done{None{}}: "none"
    case Done{Some{url}}: "url " ++ URL.href(url)

def resolved(target: String, env: Maybe<&2, T.ProviderEnv()>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Maybe<&2, URL.URL>> <- Proxy.resolveHttpProxyUrlForTarget(TestClient.urlContext(), target, env)
    IO.print(shown(result))

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case target <> Nil{}: resolved(target, None{})
    case target <> env <> Nil{}: resolved(target, scopedEnv(Decode.parse(env)))
    case _: IO.die(Unit, 1, "usage: node-http-proxy <target> [scoped env JSON]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)

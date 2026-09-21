import Base
import ../packages/ai/src/api/openai-responses-envelope-error.bend as Format
import ../packages/ai/src/api/openai-responses-envelope.bend as Envelope
import ../packages/ai/src/api/openai-responses-url.bend as Address
import ../packages/ai/src/api/openai-request-headers.bend as Header
import ../packages/runtime/src/http-header.bend as HTTP
import ../packages/runtime/src/url-absolute.bend as URL
import ../packages/runtime/src/url-form-strict.bend as Query
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/json-string.bend as Quote
import ../packages/runtime/test/utf8-runner.bend as Number

def timeout(result: Result<&2, &2, Header.Error, F.F64>) -> IO(Unit):
  match result:
    case Done{_}: IO.print(Quote.quote("valid"))
    case Fail{cause}: IO.print(Quote.quote(Format.format(Envelope.HeaderFailure{cause})))

def show(error: Envelope.Error) -> IO(Unit): IO.print(Quote.quote(Format.format(error)))

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case "timeout" <> high <> low <> Nil{}: timeout(Header.validateTimeout(F.fromBits(Number.decimal(high, 0), Number.decimal(low, 0))))
    case "native" <> Nil{}:
      do IO<Unit>:
        show(Envelope.HeaderFailure{Header.MissingAuthentication{}})
        show(Envelope.HeaderFailure{Header.HeaderFailure{HTTP.InvalidName{}}})
        show(Envelope.HeaderFailure{Header.HeaderFailure{HTTP.InvalidValue{}}})
        show(Envelope.HeaderFailure{Header.HeaderFailure{HTTP.NonByteValue{}}})
        show(Envelope.URLFailure{Address.InvalidURL{URL.MissingScheme{}}})
        show(Envelope.URLFailure{Address.InvalidQuery{Query.InvalidName{0n}}})
        show(Envelope.URLFailure{Address.InvalidQuery{Query.InvalidValue{9n}}})
        show(Envelope.NonFinitePayload{})
        show(Envelope.PayloadEncodingFailure{})
    case _: IO.die(Unit, 1, "expected timeout high low or native")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)

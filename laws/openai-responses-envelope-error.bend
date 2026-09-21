import Base
import ../packages/ai/src/api/openai-responses-envelope-error.bend as Format
import ../packages/ai/src/api/openai-responses-envelope.bend as Envelope
import ../packages/ai/src/api/openai-responses-url.bend as Address
import ../packages/ai/src/api/openai-request-headers.bend as Header
import ../packages/runtime/src/http-header.bend as HTTP
import ../packages/runtime/src/url-form-strict.bend as Query

law header_diagnostic_survives_envelope_wrapping:
  for cause: Header.Error
  {Format.format(Envelope.HeaderFailure{cause}) == Format.header(cause) : String}

law header_field_diagnostic_survives_both_boundaries:
  for cause: HTTP.HeaderError
  {Format.format(Envelope.HeaderFailure{Header.HeaderFailure{cause}}) == Format.field(cause) : String}

law query_position_survives_both_boundaries:
  for cause: Query.Error
  {Format.format(Envelope.URLFailure{Address.InvalidQuery{cause}}) == Format.query(cause) : String}

import Base
import ../types.bend as T
import ./headers.bend as Headers
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response-metadata.bend as Metadata
import ../../../runtime/src/f64.bend as F

# Borrow only immutable response metadata for onResponse; the affine body is
# returned intact and remains unread until the provider starts consumption.
def inspect(-State: Type, response: Response.Response<State>) -> Response.Response<State> & T.ProviderResponse:
  match response:
    case Response.Response{+metadata, body}:
      (Response.Response{metadata, body}, T.ProviderResponse{F.fromU32(Metadata.status(metadata)), Headers.headersToRecord(Metadata.headers(metadata))})

import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/provider-response-view.bend as View
import ../packages/ai/src/utils/headers.bend as Headers
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/src/http-response-metadata.bend as Metadata
import ../packages/runtime/src/f64.bend as F

law metadata_projection_retains_owned_response:
  for -State: Type
  for metadata: Metadata.Metadata
  for body: Response.Body<State>
  {View.inspect(State, Response.Response{metadata, body}) == (Response.Response{metadata, body}, T.ProviderResponse{F.fromU32(Metadata.status(metadata)), Headers.headersToRecord(Metadata.headers(metadata))}) : Response.Response<State> & T.ProviderResponse}

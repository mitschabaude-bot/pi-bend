import Base
import ./provider-request.bend as Request
import ./provider-retry-error.bend as Retry

# Hooks retain their own diagnostic. A response-hook cleanup failure remains
# in the typed cause tree and cannot replace the primary user-facing failure.
def render(-E: Data, error: Request.Error<E>, renderOriginal: E -> Retry.RenderedError) -> Result<&2, &2, Retry.FormattingError, Retry.RenderedError>:
  match error:
    case Request.PayloadFailure{cause}: Done{renderOriginal(cause)}
    case Request.ResponseFailure{cause, _}: Done{renderOriginal(cause)}
    case Request.RequestFailure{cause}: Retry.render(E, cause, renderOriginal)

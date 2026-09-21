import Base
import ../packages/ai/src/utils/provider-request.bend as Request
import ../packages/ai/src/utils/provider-request-error.bend as Format
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/src/utils/provider-retry-error.bend as RetryFormat

law response_cleanup_cannot_replace_primary_diagnostic:
  for -E: Data
  for cause: E
  for cleanup: Result<&2, &2, E, Unit>
  for render: E -> RetryFormat.RenderedError
  {Format.render(E, Request.ResponseFailure{cause, cleanup}, render) == Done{render(cause)} : Result<&2, &2, RetryFormat.FormattingError, RetryFormat.RenderedError>}

law hook_diagnostics_do_not_depend_on_stage:
  for -E: Data
  for cause: E
  for render: E -> RetryFormat.RenderedError
  {Format.render(E, Request.PayloadFailure{cause}, render) == Format.render(E, Request.ResponseFailure{cause, Done{Unit{}}}, render) : Result<&2, &2, RetryFormat.FormattingError, RetryFormat.RenderedError>}

law retry_keeps_its_diagnostic_policy:
  for -E: Data
  for cause: Retry.RetryFailure<E>
  for render: E -> RetryFormat.RenderedError
  {Format.render(E, Request.RequestFailure{cause}, render) == RetryFormat.render(E, cause, render) : Result<&2, &2, RetryFormat.FormattingError, RetryFormat.RenderedError>}

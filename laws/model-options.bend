import Base
import ../packages/ai/src/api/options.bend as Options

# Auth/routing may replace the common HTTP fields. Repeated replacements must
# leave all API-specific controls (effort, tool choice, budgets, deployment,
# etc.) untouched, for every request configuration and injected hook error.
law successive_auth_updates_do_not_accumulate_changes:
  for -Error: Data
  for options: Options.RequestOptions<Error>
  for first: Options.BaseOptions(Error)
  for last: Options.BaseOptions(Error)
  {Options.withRequestBase(Error, Options.withRequestBase(Error, options, first), last) == Options.withRequestBase(Error, options, last) : Options.RequestOptions<Error>}

law common_fields_reach_the_provider_without_loss:
  for -Error: Data
  for options: Options.RequestOptions<Error>
  for base: Options.BaseOptions(Error)
  {Options.requestBase(Error, Options.withRequestBase(Error, options, base)) == base : Options.BaseOptions(Error)}


law replacing_common_fields_cannot_discard_provider_configuration:
  for -Error: Data
  for +options: Options.RequestOptions<Error>
  for replacement: Options.BaseOptions(Error)
  {Options.withRequestBase(Error, Options.withRequestBase(Error, options, replacement), Options.requestBase(Error, options)) == options : Options.RequestOptions<Error>}

import Base
import ../packages/ai/src/api/openai-responses-initialization-error.bend as D
import ../packages/ai/src/api/openai-responses-cleartext-system-runtime.bend as System
import ../packages/ai/src/api/openai-responses-cleartext-runtime.bend as Runtime
import ../packages/runtime/src/resolver-diagnostic.bend as Resolver
import ../packages/runtime/src/resolver-system-config.bend as Config
import ../packages/runtime/src/utf8-strict.bend as UTF8
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/random-seed.bend as Seed

law resolver_failure_retains_os_cause:
  for code: U32
  for message: String
  {D.resolverEntropy(Index.SourceFailure{code, message}) == "Could not obtain resolver entropy (code " ++ Nat.show(U32.to_nat(code)) ++ "): " ++ message : String}

law retry_failure_retains_os_cause:
  for code: U32
  for message: String
  {D.retryEntropy(Seed.SourceFailure{code, message}) == "Could not obtain retry entropy (code " ++ Nat.show(U32.to_nat(code)) ++ "): " ++ message : String}

law short_seed_retains_actual_count:
  for bytes: Nat
  {D.retryEntropy(Seed.ShortSeed{bytes}) == "Retry entropy source returned " ++ Nat.show(bytes) ++ " bytes; expected 8" : String}

law configuration_diagnostics_preserved:
  for cause: Config.Error<UTF8.Error>
  {D.messages(System.ConfigurationFailure{cause}) == Resolver.messages(cause) : List<&2, String>}

law runtime_diagnostic_preserved:
  for cause: Runtime.Error
  {D.messages(System.InitializationFailure{cause}) == D.runtime(cause) <> Nil{} : List<&2, String>}

law single_diagnostic_displayed_unchanged:
  for message: String
  {D.display(message <> Nil{}) == message : String}

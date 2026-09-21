import Base
import ../packages/ai/src/utils/provider-hook-map.bend as Hooks
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/callback.bend as C

law successful_hook_output_is_unchanged:
  for -Source: Data
  for -Target: Data
  for -Value: Data
  for embed: Source -> Target
  for output: Value
  {Hooks.result(Source, Target, Value, embed, Done{output}) == Done{output} : Result<&2, &2, Target, Value>}

law hook_failure_uses_supplied_embedding:
  for -Source: Data
  for -Target: Data
  for -Value: Data
  for embed: Source -> Target
  for cause: Source
  {Hooks.result(Source, Target, Value, embed, Fail{cause}) == Fail{embed(cause)} : Result<&2, &2, Target, Value>}

law borrowing_preserves_hook_owner:
  for -Value: Data
  for -Model: Data
  for -E: Data
  for hooks: Hooks.Hooks<Value, Model, E>
  {Hooks.borrow(Value, Model, E, Hooks.Owner{hooks}) == (Hooks.Owner{hooks}, hooks) : Hooks.Owner<Value, Model, E> & Hooks.Hooks<Value, Model, E>}

law absent_callback_retirement_has_no_effects:
  for -Input: Data
  for -Value: Data
  for -E: Data
  {Hooks.retireOptional(Input, Value, E, None{}) == IO.pure(Unit, Unit{}) : IO(Unit)}

law absent_hooks_retirement_has_no_effects:
  for -Value: Data
  for -Model: Data
  for -E: Data
  {Hooks.dispose(Value, Model, E, Hooks.Owner{Hooks.Hooks{None{}, None{}}}) == IO.pure(Unit, Unit{}) : IO(Unit)}

law present_adapter_retirement_disposes_callback:
  for -Input: Data
  for -Value: Data
  for -E: Data
  for callback: C.Callback<Input, Result<&2, &2, E, Value>>
  {Hooks.retireOptional(Input, Value, E, Some{callback}) == C.dispose(Input, Result<&2, &2, E, Value>, callback) : IO(Unit)}

law both_adapters_retire_in_order:
  for -Value: Data
  for -Model: Data
  for -E: Data
  for payload: Maybe<&2, T.PayloadCallback(Value, Model, E)>
  for response: Maybe<&2, T.ResponseCallback(Model, E)>
  {Hooks.dispose(Value, Model, E, Hooks.Owner{Hooks.Hooks{payload, response}}) == IO.bind(Unit, Unit, Hooks.retireOptional(T.PayloadInput<Value, Model>, Maybe<&2, Value>, E, payload), ignored => Hooks.retireOptional(T.ResponseInput<Model>, Unit, E, response)) : IO(Unit)}

import Base
import ../laws/provider-hook-map.bend as Laws

def Laws.successful_hook_output_is_unchanged(Source, Target, Value, embed, output): {==}
def Laws.hook_failure_uses_supplied_embedding(Source, Target, Value, embed, cause): {==}
def Laws.borrowing_preserves_hook_owner(Value, Model, E, hooks): {==}
def Laws.absent_callback_retirement_has_no_effects(Input, Value, E): {==}
def Laws.absent_hooks_retirement_has_no_effects(Value, Model, E): {==}
def Laws.present_adapter_retirement_disposes_callback(Input, Value, E, callback): {==}
def Laws.both_adapters_retire_in_order(Value, Model, E, payload, response): {==}

import Base
import ../../src/core/extensions/types.bend as Ext
import ../../src/core/extensions/context.bend as Ctx
import ../../src/core/extensions/loader.bend as Loader
import ../../src/core/compaction/compaction.bend as Compaction
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/ref.bend as R
import ../../../runtime/src/text.bend as Text

# pi v0.87.1 examples/extensions/trigger-compact.ts: compact once the
# context crosses 100k tokens at a turn end, and on /trigger-compact.

def compactThresholdTokens() -> F64: U32.to_f64(100000)

def notifyIfUI(+ctx: Ctx.ExtensionContext, +message: String, +kind: Ctx.NotifyType) -> IO(Unit):
  do IO<Unit>:
    shown : Bool <- Ctx.hasUI(ctx)
    Bool.pick(Unit -> IO(Unit), shown, _ => Ctx.notify(ctx, message, kind), _ => IO.pure(Unit, Unit{}))(Unit{})

def completed(ctx: Ctx.ExtensionContext, result: Compaction.CompactionResult) -> IO(Unit): notifyIfUI(ctx, "Compaction completed", Ctx.InfoNotice{})

def failed(ctx: Ctx.ExtensionContext, message: String) -> IO(Unit): notifyIfUI(ctx, "Compaction failed: " ++ message, Ctx.ErrorNotice{})

def triggerCompaction(+ctx: Ctx.ExtensionContext, customInstructions: Maybe<&2, String>) -> IO(Unit):
  do IO<Unit>:
    notifyIfUI(ctx, "Compaction started", Ctx.InfoNotice{})
    onComplete : C.Callback<Compaction.CompactionResult, Unit> <- C.create(~Ctx.ExtensionContext, ~Compaction.CompactionResult, ~Unit, ~completed, ctx)
    onError : C.Callback<String, Unit> <- C.create(~Ctx.ExtensionContext, ~String, ~Unit, ~failed, ctx)
    Ctx.compact(ctx, Ctx.CompactOptions{customInstructions, Some{onComplete}, Some{onError}})

def tokensOf(usage: Maybe<&2, Ctx.ContextUsage>) -> Maybe<&2, F64>:
  match usage:
    case Some{Ctx.ContextUsage{tokens, _, _}}: tokens
    case None{}: None{}

# Only a turn that moves the context from at most the threshold to above it
# compacts; unknown usage leaves the previous reading in place.
def crossed(previous: Maybe<&2, F64>, +current: F64) -> Bool:
  match previous:
    case None{}: False{}
    case Some{+tokens}: F64.is_le(tokens, compactThresholdTokens()) && F64.is_gt(current, compactThresholdTokens())

def observed(+previous: R.Ref<Maybe<&2, F64>>, +ctx: Ctx.ExtensionContext, tokens: Maybe<&2, F64>) -> IO(Unit):
  match tokens:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+current}:
      do IO<Unit>:
        before : Maybe<&2, F64> <- R.read(Maybe<&2, F64>, previous)
        R.write(Maybe<&2, F64>, previous, Some{current})
        Bool.pick(Unit -> IO(Unit), crossed(before, current), _ => triggerCompaction(ctx, None{}), _ => IO.pure(Unit, Unit{}))(Unit{})

def onTurnEnd(previous: R.Ref<Maybe<&2, F64>>, call: Ext.HandlerCall<Ext.TurnEndEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ext.BoundaryResult>>):
  match call:
    case Ext.HandlerCall{_, +ctx}:
      do IO<Result<&2, &2, String, Maybe<&2, Ext.BoundaryResult>>>:
        usage : Maybe<&2, Ctx.ContextUsage> <- Ctx.getContextUsage(ctx)
        observed(previous, ctx, tokensOf(usage))
        return Done{None{}}

def instructionsOf(+args: String) -> Maybe<&2, String>:
  +trimmed = Text.trim(args)
  Bool.pick(Maybe<&2, String>, String.is_empty(trimmed), None{}, Some{trimmed})

def onCommand(unit: Unit, call: Ext.CommandCall) -> IO(Result<&2, &2, String, Unit>):
  match call:
    case Ext.CommandCall{args, ctx}:
      do IO<Result<&2, &2, String, Unit>>:
        triggerCompaction(Ctx.commandContext(ctx), instructionsOf(args))
        return Done{Unit{}}

def both(first: Result<&2, &2, String, Loader.Unsubscribe>, second: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, Unit>:
  match first:
    case Fail{error}: Fail{error}
    case Done{_}: second

def subscribe(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    previous : R.Ref<Maybe<&2, F64>> <- R.new(Maybe<&2, F64>, None{})
    handler : Ext.ExtensionHandler(Ext.TurnEndEvent, Ext.BoundaryResult) <- C.create(~R.Ref<Maybe<&2, F64>>, ~Ext.HandlerCall<Ext.TurnEndEvent>, ~Result<&2, &2, String, Maybe<&2, Ext.BoundaryResult>>, ~onTurnEnd, previous)
    subscribed : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnTurnEnd{handler})
    command : Ext.CommandHandler() <- C.create(~Unit, ~Ext.CommandCall, ~Result<&2, &2, String, Unit>, ~onCommand, Unit{})
    registered : Result<&2, &2, String, Unit> <- Loader.registerCommand(api, "trigger-compact", Ext.CommandOptions{Some{"Trigger compaction immediately"}, None{}, command})
    return both(subscribed, registered)

def triggerCompact(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): subscribe(api)

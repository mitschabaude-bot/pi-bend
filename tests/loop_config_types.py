"""Compare the loop configuration's fields with upstream and check typed callback boundaries.

Upstream's AgentLoopConfig extends SimpleStreamOptions; the port nests those
inherited fields as one `options` record. The comparison flattens that record
so every upstream field, with its optionality, must still be present.
"""
from pathlib import Path
import re
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
agent = (ROOT.parent / 'pi-mono/packages/agent/src/types.ts').read_text()
ai = (ROOT.parent / 'pi-mono/packages/ai/src/types.ts').read_text()
native_agent = (ROOT / 'packages/agent/src/types.bend').read_text()
native_ai = (ROOT / 'packages/ai/src/types.bend').read_text()

def upstream_fields(source, name):
    body = re.search(r'export interface ' + name + r'\b[^\n]*\{(.*?)\n}', source, re.S).group(1)
    return {field: bool(opt) for field, opt in re.findall(r'^\t(\w+)(\??):', body, re.M)}

def native_fields(source, name):
    record = re.search(r'^  ' + name + r'\{([^\n]*)\}', source, re.M).group(1)
    return {field: ty.startswith('Maybe<') for field, ty in re.findall(r'(\w+):\s*([^,}]+)', record)}

expected = {}
for name in ('ProviderRequestOptions', 'StreamOptions', 'SimpleStreamOptions'):
    expected.update(upstream_fields(ai, name))
inherited = list(expected)
expected.update(upstream_fields(agent, 'AgentLoopConfig'))
config = native_fields(native_agent, 'AgentLoopConfig')
assert list(config)[0] == 'options', config
options = native_fields(native_ai, 'SimpleStreamOptions')
actual = dict(options)
actual.update({field: optional for field, optional in config.items() if field != 'options'})
assert actual == expected, (expected, actual)
assert list(options) == inherited, (inherited, list(options))

params = 'Unit, String, Unit, String, Unit'
option_values = ', '.join('Some{headerMap}' if name == 'headers' else 'None{}' for name in inherited)
own = [name for name in config if name != 'options']
values = {name: 'None{}' for name in own}
values.update(model='model', convertToLlm='convert', beforeToolCall='Some{before}')
pattern = ['_'] + [{'model': 'model', 'convertToLlm': 'convert', 'beforeToolCall': 'Some{before}'}.get(name, '_') for name in own]
lines = ['import Base', 'import ../packages/agent/src/types.bend as T', 'import ../packages/ai/src/models.bend as Models', 'import ../packages/ai/src/types.bend as Ai', 'import ../packages/ai/test/model-types.bend as Model', 'import ../packages/runtime/src/callback.bend as C', 'import ../packages/runtime/src/record.bend as Record', 'import ../packages/runtime/src/abort.bend as Abort', 'import ../packages/runtime/src/fetch.bend as Fetch', 'import ../packages/runtime/src/schema-value.bend as Schema',
'def Config() -> Data: T.AgentLoopConfig<' + params + '>',
'def Options() -> Data: Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String>',
'def Messages() -> Data: T.AgentMessageArray(Unit, String, Unit)',
'def ConvertOutput() -> Data: Result<&2, &2, String, List<&2, Ai.Message<Schema.Value, Schema.Value, Unit, String>>>',
'def BeforeInput() -> Data: T.ToolHookInput<T.BeforeToolCallContext<Unit, String, Unit, String>>',
'def BeforeOutput() -> Data: Result<&2, &2, String, T.BeforeToolCallUpdate<T.AgentContext<Unit, String, Unit, String>>>',
'def forbiddenConvert(unused: Unit, input: Messages()) -> IO(ConvertOutput()): IO.die(ConvertOutput(), 1, "configuration projection invoked converter")',
'def forbiddenBefore(unused: Unit, input: BeforeInput()) -> IO(BeforeOutput()): IO.die(BeforeOutput(), 1, "configuration projection invoked hook")',
'def verify(ok: Bool) -> IO(Unit): Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, "configuration field identity changed"))',
'def identity(config: Config(), expectedModel: Ai.Model<Ai.JsonValue>, expectedConvert: C.Callback<Messages(), ConvertOutput()>, expectedBefore: C.Callback<BeforeInput(), BeforeOutput()>) -> IO(Unit):', '  match config:',
'    case T.AgentLoopConfig{' + ', '.join(pattern) + '}: verify(Models.modelsAreEqual(Ai.JsonValue, Some{Ai.PresentValue{model}}, Some{Ai.PresentValue{expectedModel}}) && C.same(Messages(), ConvertOutput(), convert, expectedConvert) && C.same(BeforeInput(), BeforeOutput(), before, expectedBefore))',
'    case _: IO.die(Unit, 1, "before hook omitted")',
'def headers(options: Options(), expected: Ai.ProviderHeaders()) -> IO(Unit):', '  match options:',
'    case Ai.SimpleStreamOptions{' + ', '.join('Some{actual}' if name == 'headers' else '_' for name in inherited) + '}: verify(Nat.is_eq(List.length(&2, Record.Property<Ai.Nullable<String>>, Record.entries(Ai.Nullable<String>, actual)), List.length(&2, Record.Property<Ai.Nullable<String>>, Record.entries(Ai.Nullable<String>, expected))))',
'    case _: IO.die(Unit, 1, "inherited headers omitted")',
'def main() -> IO(Unit):', '  do IO<Unit>:',
'    +model : Ai.Model<Ai.JsonValue> <- IO.pure(Ai.Model<Ai.JsonValue>, Model.model(Ai.CustomModelApi{"custom"}, None{}))',
'    +headerMap : Ai.ProviderHeaders() <- IO.pure(Record.Record<Ai.Nullable<String>>, Record.Record{Nil{}})',
'    +convert : C.Callback<Messages(), ConvertOutput()> <- C.create(~Unit, ~Messages(), ~ConvertOutput(), ~forbiddenConvert, Unit{})',
'    +before : C.Callback<BeforeInput(), BeforeOutput()> <- C.create(~Unit, ~BeforeInput(), ~BeforeOutput(), ~forbiddenBefore, Unit{})',
'    +config : Config() = T.AgentLoopConfig{Ai.SimpleStreamOptions{' + option_values + '}, ' + ', '.join(values[name] for name in own) + '}',
'    identity(config, model, convert, before)',
'    headers(T.toSimpleStreamOptions(' + params + ', config), headerMap)',
'    C.dispose(Messages(), ConvertOutput(), convert)', '    C.dispose(BeforeInput(), BeforeOutput(), before)',
'    IO.print("PASS inherited loop configuration and model values, callback handles and header contents")']
path = BUILD / 'loop-config-types.bend'
path.write_text('\n'.join(lines) + '\n')
subprocess.run(['sh', 'scripts/build-pure.sh', str(path), 'build/test-loop-config-types'], cwd=ROOT, check=True)
for threads in ('1', '4'):
    subprocess.run(['build/test-loop-config-types', '--threads', threads], cwd=ROOT, check=True, timeout=30)
print(f'PASS {len(expected)} loop configuration fields with upstream optionality, nested stream options and typed callback identities')

"""Compare full AgentLoopConfig inheritance and check typed callback boundaries."""
import os
from pathlib import Path
import re
import subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
agent=(ROOT.parent/'pi-mono/packages/agent/src/types.ts').read_text()
ai=(ROOT.parent/'pi-mono/packages/ai/src/types.ts').read_text()
native=(ROOT/'packages/agent/src/types.bend').read_text()
def fields(source,name):
    body=re.search(r'export interface '+name+r'\b[^\n]*\{(.*?)\n}',source,re.S).group(1)
    return {name:bool(opt) for name,opt in re.findall(r'^\t(\w+)(\??):',body,re.M)}
expected={}
for name in ('ProviderRequestOptions','StreamOptions','SimpleStreamOptions'): expected.update(fields(ai,name))
inherited=list(expected)
expected.update(fields(agent,'AgentLoopConfig'))
record=re.search(r'^  AgentLoopConfig\{([^\n]*)\}',native,re.M).group(1)
actual={name:ty.startswith('Maybe<') for name,ty in re.findall(r'(\w+):\s*([^,}]+)',record)}
assert actual==expected,(expected,actual)
params='Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit'
stream_params='Unit, String, Unit, String, Unit, Ai.SimpleStreamOptions<Unit, Unit, Unit, Unit, String>'
values={name:'None{}' for name in actual}
values.update(model='model',convertToLlm='convert',beforeToolCall='Some{before}',headers='Some{headerMap}')
config_pattern=[{'model':'model','convertToLlm':'convert','beforeToolCall':'Some{before}'}.get(name,'_') for name in actual]
lines=['import Base','import ../packages/agent/src/types.bend as T','import ../packages/ai/src/models.bend as Models','import ../packages/ai/src/types.bend as Ai','import ../packages/ai/src/utils/event-stream.bend as E','import ../packages/ai/test/model-types.bend as Model','import ../packages/runtime/src/ref.bend as R','import ../packages/runtime/src/callback.bend as C','import ../packages/runtime/src/record.bend as Record',
'def Config() -> Data: T.AgentLoopConfig<'+params+'>',
'def Messages() -> Data: T.AgentMessageArray(Unit, String, Unit, String, String)',
'def LlmMessages() -> Data: List<&2, Ai.Message<Unit, String, Unit, String>>',
'def ConvertOutput() -> Data: Result<&2, &2, String, LlmMessages()>',
'def BeforeInput() -> Data: T.ToolHookInput<T.BeforeToolCallContext<Unit, String, Unit, String, String, U32, Unit, String>, Unit>',
'def BeforeOutput() -> Data: Result<&2, &2, String, T.BeforeToolCallUpdate<U32, T.AgentContext<Unit, String, Unit, String, String, U32, Unit, String>>>',
'def forbiddenConvert(unused: Unit, input: Messages()) -> IO(ConvertOutput()): IO.die(ConvertOutput(), 1, "configuration projection invoked converter")',
'def forbiddenBefore(unused: Unit, input: BeforeInput()) -> IO(BeforeOutput()): IO.die(BeforeOutput(), 1, "configuration projection invoked hook")',
'def verify(ok: Bool) -> IO(Unit): Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, "configuration field identity changed"))',
'def identity(config: Config(), expectedModel: Ai.Model<Unit>, expectedConvert: C.Callback<Messages(), ConvertOutput()>, expectedBefore: C.Callback<BeforeInput(), BeforeOutput()>) -> IO(Unit):','  match config:',
'    case T.AgentLoopConfig{'+', '.join(config_pattern)+'}: verify(Models.modelsAreEqual(Unit, Some{Ai.PresentValue{model}}, Some{Ai.PresentValue{expectedModel}}) && C.same(Messages(), ConvertOutput(), convert, expectedConvert) && C.same(BeforeInput(), BeforeOutput(), before, expectedBefore))',
'    case _: IO.die(Unit, 1, "before hook omitted")',
'def headers(options: Ai.SimpleStreamOptions<Unit, Unit, Unit, Unit, String>, expected: Ai.ProviderHeaders()) -> IO(Unit):','  match options:',
'    case Ai.SimpleStreamOptions{'+', '.join('Some{actual}' if name=='headers' else '_' for name in inherited)+'}: verify(Nat.is_eq(List.length(&2, Record.Property<Ai.Nullable<String>>, Record.entries(Ai.Nullable<String>, actual)), List.length(&2, Record.Property<Ai.Nullable<String>>, Record.entries(Ai.Nullable<String>, expected))))',
'    case _: IO.die(Unit, 1, "inherited headers omitted")',
'def main() -> IO(Unit):','  do IO<Unit>:',
'    +model : Ai.Model<Unit> <- IO.pure(Ai.Model<Unit>, Model.model(Ai.CustomModelApi{"custom"}, None{}))',
'    +headerMap : Ai.ProviderHeaders() <- IO.pure(Record.Record<Ai.Nullable<String>>, Record.Record{Nil{}})',
'    +convert : C.Callback<Messages(), ConvertOutput()> <- C.create(~Unit, ~Messages(), ~ConvertOutput(), ~forbiddenConvert, Unit{})',
'    +before : C.Callback<BeforeInput(), BeforeOutput()> <- C.create(~Unit, ~BeforeInput(), ~BeforeOutput(), ~forbiddenBefore, Unit{})',
'    +config : Config() = T.AgentLoopConfig{'+', '.join(values[name] for name in actual)+'}']
lines+=['    identity(config, model, convert, before)','    headers(T.toSimpleStreamOptions('+params+', config), headerMap)',
'    C.dispose(Messages(), ConvertOutput(), convert)','    C.dispose(BeforeInput(), BeforeOutput(), before)',
'    oldModel : Ai.Model<Unit> <- IO.pure(Ai.Model<Unit>, model)',
'    oldHeaders : Record.Record<Ai.Nullable<String>> <- IO.pure(Record.Record<Ai.Nullable<String>>, headerMap)',
'    IO.print("PASS inherited loop configuration and model values, callback handles and header contents")']
path=BUILD/'loop-config-types.bend'
path.write_text('\n'.join(lines)+'\n')
subprocess.run(['sh','scripts/build-pure.sh',str(path),'build/test-loop-config-types'],cwd=ROOT,check=True)
for threads in ('1','4'): subprocess.run(['build/test-loop-config-types','--threads',threads],cwd=ROOT,check=True,timeout=30)
bend=os.environ.get('BEND',str(Path.home()/'.bend/bin/bend'))
preamble='\n'.join(lines[:8])+'\n'
accepted=BUILD/'valid-loop-provider-result.bend'
accepted.write_text(preamble+f'''def Input() -> Data: T.StreamInput<{stream_params}>
def provider(value: C.Callback<Input(), Result<&2, &2, String, E.AssistantMessageEventStream(String, Unit)>>) -> T.StreamFn({stream_params}, String):
  value
def main() -> IO(Unit):
  IO.print("typed provider opening")
''')
subprocess.run([bend,str(accepted)],cwd=ROOT,check=True,timeout=30)
invalids=[('raw-context',f'''def bad(model: Ai.Model<Unit>, context: Ai.Context<Unit, String, Unit, String>) -> T.StreamInput<{stream_params}>:
  T.StreamInput{{model, context, None{{}}}}
''','TranscriptContext','Context'),('unreported-opening-error',f'''def Input() -> Data: T.StreamInput<{stream_params}>
def bad(value: C.Callback<Input(), E.AssistantMessageEventStream(String, Unit)>) -> T.StreamFn({stream_params}, String):
  value
''','Result','EventStream')]
invalids.append(('option-erasure', f"""def bad(value: T.StreamFn(Unit, String, Unit, String, Unit, T.AgentLoopConfig<{params}>, String)) -> T.StreamFn({stream_params}, String):
  value
""", 'SimpleStreamOptions', 'AgentLoopConfig'))
for name,body,required,observed in invalids:
    bad=BUILD/f'invalid-loop-{name}.bend'
    bad.write_text(preamble+body+'def main() -> IO(Unit):\n  IO.print("unreachable")\n')
    result=subprocess.run([bend,str(bad),'-o',str(bad)+'.c'],cwd=ROOT,text=True,capture_output=True,timeout=30)
    output=result.stdout+result.stderr
    (BUILD/f'invalid-loop-{name}.log').write_text(output)
    assert result.returncode != 0, 'invalid stream contract accepted'
    assert re.search(r'- expected : [^\n]*'+required,output),output
    assert re.search(r'- observed : [^\n]*'+observed,output),output
print(f'PASS {len(expected)} inherited loop fields, normalized stream input and typed provider-opening error contract and explicit option typing')

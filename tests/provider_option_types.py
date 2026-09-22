"""Check request-option inheritance and optionality against pinned TypeScript."""
from pathlib import Path
from bend_toolchain import BEND
import os
import re
import subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
source=(ROOT.parent/'pi-mono/packages/ai/src/types.ts').read_text()
native=(ROOT/'packages/ai/src/types.bend').read_text()
def fields(name):
    body=re.search(r'export interface '+name+r'\b[^\n]*\{(.*?)\n}',source,re.S).group(1)
    return {name:bool(opt) for name,opt in re.findall(r'^\t(\w+)(\??):',body,re.M)}
def bend(name):
    body=re.search(r'^  '+name+r'\{([^\n]*)\}',native,re.M).group(1)
    return {name:ty.startswith('Maybe<') for name,ty in re.findall(r'(\w+):\s*([^,}]+)',body)}
expected=fields('ProviderRequestOptions')
for name in ('ProviderRequestOptions','StreamOptions','SimpleStreamOptions'):
    expected.update(fields(name))
    assert expected==bend(name),(name,expected,bend(name))
assert fields('ProviderResponse')==bend('ProviderResponse')
params='Unit, Unit, Unit, Unit, String'
simple=list(bend('SimpleStreamOptions'))
values=['None{}' for _ in simple]
values[simple.index('deferred')]='Some{T.DeferredBoolean{False{}}}'
values[simple.index('reasoning')]='Some{T.Max{}}'
values[simple.index('headers')]='Some{headers}'
values[simple.index('onPayload')]='Some{adapter}'
values[simple.index('onResponse')]='Some{responseAdapter}'
lines=['import Base','import ../packages/ai/src/api/simple-options.bend as Options','import ../packages/ai/test/api/transform-images.bend as ModelFixture','import ../packages/ai/src/types.bend as T','import ../packages/runtime/src/record.bend as Record','import ../packages/runtime/src/ref.bend as R','import ../packages/runtime/src/callback.bend as C',
'def Input() -> Data: T.PayloadInput<Unit, T.Model<Unit>>',
'def Output() -> Data: Result<&2, &2, String, Maybe<&2, Unit>>',
'def forbidden(unused: Unit, input: Input()) -> IO(Output()):',
'  IO.die(Output(), 1, "options projection invoked payload callback")',
'def ResponseInput() -> Data: T.ResponseInput<T.Model<Unit>>',
'def ResponseOutput() -> Data: Result<&2, &2, String, Unit>',
'def forbiddenResponse(unused: Unit, input: ResponseInput()) -> IO(ResponseOutput()):',
'  IO.die(ResponseOutput(), 1, "options projection invoked response callback")',
'def verify(ok: Bool) -> IO(Unit):',
'  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, "option projection lost identity or nullable header values"))',
'def suppressed(value: Maybe<&2, T.Nullable<String>>) -> Bool:',
'  match value:',
'    case Some{T.NullValue{}}: True{}',
'    case _: False{}',
'def emptyHeader(value: Maybe<&2, T.Nullable<String>>) -> Bool:',
'  match value:',
'    case Some{T.PresentValue{text}}: String.eq(text, "")',
'    case _: False{}',
'def checkHeaders(+headers: Record.Record<T.Nullable<String>>) -> IO(Unit):',
'  verify(suppressed(Record.get(T.Nullable<String>, headers, "remove")) && emptyHeader(Record.get(T.Nullable<String>, headers, "empty")) && Maybe.is_none(&2, T.Nullable<String>, Record.get(T.Nullable<String>, headers, "missing")))',
'def check(options: T.ProviderRequestOptions<T.Model<Unit>, Unit, Unit, Unit, Unit, String>, expected: T.ProviderHeaders(), callback: T.PayloadCallback(Unit, T.Model<Unit>, String), responseCallback: T.ResponseCallback(T.Model<Unit>, String)) -> IO(Unit):','  match options:',
'    case T.ProviderRequestOptions{_, _, _, _, _, Some{actualCallback}, Some{actualResponse}, Some{+actual}, _, _, _}:',
'      do IO<Unit>:',
'        verify(C.same(Input(), Output(), callback, actualCallback) && C.same(ResponseInput(), ResponseOutput(), responseCallback, actualResponse))',
'        headers : Record.Record<T.Nullable<String>> <- IO.pure(Record.Record<T.Nullable<String>>, actual)',
'        checkHeaders(headers)',
'    case _: IO.die(Unit, 1, "headers omitted in projection")',
'def main() -> IO(Unit):','  do IO<Unit>:',
'    +adapter : T.PayloadCallback(Unit, T.Model<Unit>, String) <- C.create(~Unit, ~Input(), ~Output(), ~forbidden, Unit{})',
'    +responseAdapter : T.ResponseCallback(T.Model<Unit>, String) <- C.create(~Unit, ~ResponseInput(), ~ResponseOutput(), ~forbiddenResponse, Unit{})',
'    +headers : T.ProviderHeaders() <- IO.pure(Record.Record<T.Nullable<String>>, Record.Record{Record.Property{"remove", T.NullValue{}} <> Record.Property{"empty", T.PresentValue{""}} <> Nil{}})',
'    +options : T.SimpleStreamOptions<'+params+'> = T.SimpleStreamOptions{'+', '.join(values)+'}',
'    check(T.toProviderRequestOptions('+params+', T.toStreamOptions('+params+', options)), headers, adapter, responseAdapter)',
'    check(T.toProviderRequestOptions('+params+', Options.buildBaseOptions(~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~Unit, ~String, ModelFixture.model(False{}), T.TranscriptContext{Nil{}}, Some{options}, None{})), headers, adapter, responseAdapter)',
'    old : Record.Record<T.Nullable<String>> <- IO.pure(Record.Record<T.Nullable<String>>, headers)',
'    C.dispose(Input(), Output(), adapter)',
'    C.dispose(ResponseInput(), ResponseOutput(), responseAdapter)',
'    IO.print("PASS option inheritance, callback handles and header contents and null/empty/missing headers")']
path=BUILD/'provider-option-types.bend'
path.write_text('\n'.join(lines)+'\n')
subprocess.run(['sh','scripts/build-pure.sh',str(path),'build/test-provider-option-types'],cwd=ROOT,check=True)
for threads in ('1','4'): subprocess.run(['build/test-provider-option-types','--threads',threads],cwd=ROOT,check=True,timeout=30)
print('PASS three inherited option field sets and provider response field coverage')

bend_compiler=BEND
for index,(old,new,expected,observed) in enumerate([
    ('Some{T.Max{}}','Some{T.Off{}}','ThinkingLevel','ModelThinkingLevel'),
    ('Some{T.DeferredBoolean{False{}}}','Some{T.FifteenMinutes{}}','DeferredRequest','DeferredWindow'),
]):
    bad=BUILD/f'invalid-provider-option-{index}.bend'
    text='\n'.join(lines)+'\n'
    assert old in text
    bad.write_text(text.replace(old,new))
    result=subprocess.run([bend_compiler,str(bad),'-o',str(bad)+'.c'],cwd=ROOT,text=True,capture_output=True,timeout=30)
    output=result.stdout+result.stderr
    (BUILD/f'invalid-provider-option-{index}.log').write_text(output)
    assert result.returncode != 0, 'invalid closed option variant accepted'
    assert re.search(r'- expected : [^\n]*'+expected+r'\n',output),output
    assert re.search(r'- observed : [^\n]*'+observed+r'\n',output),output
print('PASS reasoning excludes off and deferred windows require their configuration wrapper')

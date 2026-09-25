"""Check the composed plain-schema path against actual validateToolArguments."""
from upstream_pin import check_sibling
check_sibling()
import json
from pathlib import Path
import subprocess
from schema_literals import value, string
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
dependency = BUILD / 'schema-reference/node_modules/typebox/package.json'
if not dependency.exists():
    subprocess.run(['npm', 'install', '--prefix', str(BUILD / 'schema-reference'), '--ignore-scripts', '--no-audit', '--no-fund', 'typebox@1.3.27'], check=True)
assert json.loads(dependency.read_text())['version'] == '1.3.27'
cases = []
def case(schema, instance, name):
    cases.append({'schema':schema, 'value':instance, 'name':name})

leaves = [{'type': t} for t in ['number', 'integer', 'boolean', 'string', 'null']]
leaves += [{'anyOf':[{'type':'number'}, {'type':'null'}]}, {'oneOf':[{'type':'number'}, {'type':'null'}]},
           {'type':['array', 'null'], 'items':{'type':'string'}},
           {'type':'integer', 'minimum':2}, {'type':'array', 'items':{'type':'integer'}, 'minItems':2}]
for i, leaf in enumerate(leaves):
    for v in [None, '42', '42.1', 'true', 'false', '1', '0', 'null', '', True, False, 0, 1, ['1','2']]:
        for required in [[], ['value']]:
            case({'type':'object', 'properties':{'value':leaf}, 'required':required},
                 {'value':v}, f'plain schema {i}, input {v}, required={required}')
case({'type':'object', 'properties':{'path':{'type':'string'}, 'offset':{'type':'number'},
      'nullable':{'anyOf':[{'type':'string'},{'type':'null'}]},
      'metadata':{'type':'object', 'properties':{'enabled':{'type':'boolean'}}}}, 'required':['path','metadata']},
     {'path':'file.txt','offset':None,'nullable':None,'metadata':{'enabled':None}},
     'treats null as omission for optional non-nullable properties')
case({'type':'object', 'properties':{'count':{'type':'number'}}, 'required':['count']}, {'count':'42'}, 'numeric conversion followed by final checking')
case({'type':'object', 'properties':{'x':{'type':'number'}}, 'required':['x']}, {}, 'missing required field')
case({'type':'object', 'additionalProperties':False}, {'unexpected':1}, 'additional property rejection')
case({'type':'object', 'properties':{'items':{'type':'array','items':{'type':'object','properties':{'n':{'type':'number'}}}}}},
     {'items':[{'n':'2'},{'n':None}]}, 'normalization and coercion compose through nested arrays')
expected = json.loads(subprocess.check_output(['node','tests/plain_validation_reference.mjs'], input=json.dumps(cases), text=True, cwd=ROOT))
assert expected[-5]['value'] == {'path':'file.txt','nullable':None,'metadata':{}}
assert expected[-1]['value'] == {'items':[{'n':2},{}]}
lines = ['import Base','import ../packages/ai/test/plain-validation.bend as T',
         'import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/f64.bend as F',
         'import ../packages/runtime/src/record.bend as R']
for i,(fixture,result) in enumerate(zip(cases,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):']
    args = f'{value(fixture["value"])}, {value(fixture["schema"])}'
    label = json.dumps(fixture['name'])
    if result['ok']:
        lines.append(f'  T.check({args}, {value(result["value"])}, {value(fixture["value"])}, {label})')
    else:
        assert result['message'].startswith('Validation failed for tool "echo":')
        lines.append(f'  T.reject({args}, {value(fixture["value"])}, {string(result["message"])}, {label})')
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(len(cases))]
lines += [f'    IO.print("PASS {len(cases)} composed plain-schema validation cases, including exact failure text, against upstream")']
source=BUILD/'plain-validation-check.bend'
source.write_text('\n'.join(lines)+'\n')
for source,name in [(source,'plain-validation-check'),('packages/ai/test/plain-validation.bend','plain-validation-errors'),('packages/ai/test/plain-validation-upstream.bend','plain-validation-upstream')]:
    output=BUILD/name
    subprocess.run(['sh','scripts/build-pure.sh',str(source),str(output)],cwd=ROOT,check=True)
    for threads in ['1','4']:
        subprocess.run([str(output),'--threads',threads],cwd=ROOT,check=True,timeout=120)

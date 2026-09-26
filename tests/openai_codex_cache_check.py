#!/usr/bin/env python3
"""Continuation/delta construction versus actual pinned private pi functions.

Object field order is intentionally ignored in Bend, as approved for structural
JSON equality. Malformed input fields cannot be reused as a cache baseline.
"""
import argparse
import copy
import json
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def cases():
    rng = random.Random(9183)
    values = [None, True, False, 0, -0.0, 7, '', '☃', {'nested': [1, 'x']}, [2, 3]]
    result = []
    for _ in range(220):
        before = [copy.deepcopy(rng.choice(values)) for _ in range(rng.randrange(6))]
        response = [copy.deepcopy(rng.choice(values)) for _ in range(rng.randrange(4))]
        delta = [copy.deepcopy(rng.choice(values)) for _ in range(rng.randrange(5))]
        previous = {'model':'gpt-5.1-codex', 'store':False, 'input':before, 'reasoning':{'effort':'medium'}}
        current = {**previous, 'input':before + response + delta}
        state = {'lastRequestBody':previous, 'lastResponseId':'resp_'+str(len(result)), 'lastResponseItems':response}
        result.append({'body':current, 'continuation':state})
        changed = copy.deepcopy(current)
        changed['reasoning']['effort'] = 'high'
        result.append({'body':changed, 'continuation':state})
        if current['input']:
            result.append({'body':{**current, 'input':current['input'][:-1]}, 'continuation':state})
            result.append({'body':{**current, 'input':[{'different':True}, *current['input'][1:]]}, 'continuation':state})
        result.append({'body':current, 'continuation':{**state, 'lastResponseId':''}})
        result.append({'body':{**current, 'previous_response_id':'ignored'}, 'continuation':state})
    result += [
        {'body':{'model':'x'}, 'continuation':None},
        {'body':{'model':'x'}, 'continuation':{'lastRequestBody':{'model':'x'}, 'lastResponseId':'empty', 'lastResponseItems':[]}},
    ]
    return result


def execute(command, values):
    outputs = []
    # Keep argv below the operating system's limit; no result artifacts.
    for start in range(0, len(values), 50):
        result = subprocess.run(command + [json.dumps(value,separators=(',',':')) for value in values[start:start+50]], cwd=ROOT, capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stderr[-1500:]
        outputs += [json.loads(line) for line in result.stdout.splitlines()]
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', default='build/openai-codex-cache')
    parser.add_argument('--backends', nargs='+', choices=['bun','native-1','native-4'], default=['bun'])
    args = parser.parse_args()
    values = cases()
    oracle = subprocess.run(['bun','tests/openai_codex_cache_reference.ts'], cwd=ROOT, input=json.dumps(values), text=True, capture_output=True, check=True)
    expected = json.loads(oracle.stdout)
    adaptations = [
        {'body':{'input':[{'b':2,'a':1},'next'],'model':'x'}, 'continuation':{'lastRequestBody':{'model':'x','input':[{'a':1,'b':2}]},'lastResponseId':'ordered','lastResponseItems':[]}},
        {'body':{'model':'x','input':'invalid'}, 'continuation':{'lastRequestBody':{'model':'x'},'lastResponseId':'invalid','lastResponseItems':[]}},
    ]
    for backend in args.backends:
        command = ['bun',args.prefix+'.js'] if backend == 'bun' else [args.prefix,'--threads',backend[-1]]
        got = execute(command, values)
        assert len(got) == len(expected)
        for index, (mine, want) in enumerate(zip(got, expected)):
            assert mine == want, (backend,index,values[index],mine,want)
        reordered, malformed = execute(command, adaptations)
        assert reordered == {'body':{'input':['next'],'model':'x','previous_response_id':'ordered'},'retained':True}, reordered
        assert malformed == {'body':adaptations[1]['body'],'retained':False}, malformed
        print(f'{backend}: {len(values)} prefix/configuration/invalidation cases MATCH; structural order and invalid input adaptations PASS')


if __name__ == '__main__':
    main()

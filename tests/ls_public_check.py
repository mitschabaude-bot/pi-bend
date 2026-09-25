"""Public ls behavior, native filesystem and injected operation lifecycle."""
from upstream_pin import UPSTREAM
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('backends', nargs='*', default=['bun', 'native-1', 'native-4'])
p.add_argument('--prefix', type=Path, default=ROOT / 'build/ls-public')
a = p.parse_args()
reference = UPSTREAM / 'packages/coding-agent/src/core/tools'
source = (reference / 'ls.ts').read_text()
body = source[source.index('export function createLsToolDefinition('):source.index('export function createLsTool(cwd')]
oracle = ROOT / 'build/ls-tool-oracle.ts'
oracle.write_text('import {readdir,stat,access} from "node:fs/promises";\n'
    'import * as nodePath from "node:path";\n'
    'import {resolveToCwd} from ' + json.dumps(str(reference/'path-utils.ts')) + ';\n'
    'import {truncateHead,DEFAULT_MAX_BYTES,formatSize} from ' + json.dumps(str(reference/'truncate.ts')) + ';\n'
    'const DEFAULT_LIMIT=500,lsSchema={},lsRenderers={},lsToolSystemPromptContribution={snippet:"List directory contents"};\n'
    'const defaultLsOperations={readdir,stat,exists:async p=>{try{await access(p);return true}catch{return false}}};\n'
    + body + '\nconst args=JSON.parse(process.argv[3]);\n'
    'try {console.log(JSON.stringify(await createLsToolDefinition(process.argv[2]).execute("test",args)))}\n'
    'catch(e){console.log(JSON.stringify({error:e.message}))}\n')


def expected(names, limit=500):
    # Input already ordered by the fixture's explicitly injected comparator.
    chosen = names[:limit]
    if not chosen:
        return {'text': '(empty directory)', 'details': 'none'}
    raw = '\n'.join(chosen)
    lines = raw.split('\n')
    kept, size = [], 0
    for line in lines:
        extra = len(line.encode()) + bool(kept)
        if size + extra > 51200:
            break
        kept.append(line)
        size += extra
    cut = len(kept) != len(lines)
    reached = len(names) > limit
    notices = []
    if reached:
        notices.append(f'{limit} entries limit reached. Use limit={2*limit} for more')
    if cut:
        notices.append('50.0KB limit reached')
    text = '\n'.join(kept) + ('\n\n[' + '. '.join(notices) + ']' if notices else '')
    truncation = f'True:{len(lines)}:{len(raw.encode())}:{len(kept)}:{size}:{not kept}:51200' if cut else 'none'
    return {'text': text, 'details': f'{limit if reached else "none"}|{truncation}' if notices else 'none'}


for backend in a.backends:
    command = ['bun', str(a.prefix)+'.js'] if backend == 'bun' else [str(a.prefix), '--threads', backend[-1]]
    checks = 0

    def run(mode='injected', cwd='/virtual', path='none', limit='none', entries=''):
        global checks
        result = subprocess.run(command+[mode,str(cwd),path,str(limit),entries], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0 and not result.stderr, (backend, mode, result.returncode, result.stdout, result.stderr)
        trace, value = [], {}
        for line in result.stdout.splitlines():
            key, text = line.split(':', 1)
            if key in ('exists', 'stat', 'readdir'):
                trace.append((key, base64.b64decode(text).decode()))
            elif key in ('error', 'text'):
                value[key] = base64.b64decode(text).decode()
            elif key == 'details':
                value[key] = text
            else:
                raise AssertionError(line)
        checks += 1
        return value, trace

    def same(names, limit='none'):
        output, trace = run(entries='\n'.join(names), limit=limit)
        selected = sorted(n for n in names if not n.startswith('!'))
        maximum = 500 if limit == 'none' else limit
        assert output == expected([n+'/' if n.startswith('d') else n for n in selected], maximum), (backend, names[:3], output.get("details"), expected([n+"/" if n.startswith("d") else n for n in selected], maximum).get("details"))
        return trace

    same(['z', 'a', 'dir', '.hidden-file', '.hidden-dir'])
    same([])
    same(['!gone', '!missing'])
    same(['!gone', 'a', 'b', 'dir'], 2)
    trace = same(['a', 'b'], 1)
    assert ('stat','/virtual/b') not in trace  # Do not stat the first omitted entry.
    same(['a', 'b'], 2)  # Exact boundary has no notice.
    same(['a', 'b'], 0)
    same([f'file-{i:04d}' for i in range(501)])
    same([f'file-{i:04d}' for i in range(500)])
    same([f'{i:04d}'+'é'*100 for i in range(350)], 300)  # Both caps, UTF-8 bytes.
    same(['x'*51200])
    same(['x'*51201])  # A first line larger than the byte cap is not split.
    same(['é'*25600])
    same(['é'*25601])
    # The explicit comparator, including stable ties, is independent of locale.
    trace = same(['z','A','a','é','É','雪','😀'])
    assert [p.rsplit('/',1)[-1] for op,p in trace[3:]] == sorted(['z','A','a','é','É','雪','😀'])

    for mode, message, count in [('missing','Path not found: /virtual',1), ('file','Not a directory: /virtual',2),
                                 ('exists-error','exists failed',1), ('stat-error','stat failed',2),
                                 ('readdir-error','Cannot read directory: denied',3)]:
        value, trace = run(mode, entries='a')
        assert value == {'error':message} and len(trace) == count, (backend,mode,value,trace)
    for mode, count in [('preabort',0),('abort-exists',1),('abort-stat',2),('abort-readdir',3),('abort-entry',4)]:
        value, trace = run(mode,entries='a\nb')
        assert value == {'error':'Operation aborted'} and len(trace) == count, (backend,mode,value,trace)
    for limit in ['bad','-1','1.5','nan','inf','281474976710656']:
        value, trace = run(limit=limit,entries='a')
        assert 'input is invalid' in value['error'] and trace == [], (backend,limit,value,trace)
    value, trace = run(cwd='/virtual',path='a/../',entries='x')
    assert value == expected(['x']) and trace[0] == ('exists','/virtual')
    value, trace = run(path='',entries='x')
    assert value == expected(['x'])

    value, trace = run('reuse',entries='a')
    assert value == expected(['a']) and trace[-1] == ('exists','/virtual')
    value, trace = run('preabort',limit='bad')
    assert value == {'error':'Operation aborted'} and trace == []

    with tempfile.TemporaryDirectory(prefix='bend-ls-public-') as folder:
        root = Path(folder)
        (root/'.hidden-file').write_text('hidden')
        (root/'.hidden-dir').mkdir()
        (root/'a-file').write_text('a')
        (root/'dir').mkdir()
        (root/'file-link').symlink_to('a-file')
        (root/'directory-link').symlink_to('dir')
        (root/'broken-link').symlink_to('missing')
        (root/'cycle-link').symlink_to('cycle-link')
        os.mkfifo(root/'fifo')
        names = ['.hidden-dir/','.hidden-file','a-file','dir/','directory-link/','fifo','file-link']
        for mode in ['native','context']:
            # Upstream named assertions: "should list dotfiles and directories";
            # "ls uses ctx.cwd when provided".
            value, trace = run(mode,cwd=root)
            assert value == expected(names) and trace == [], (backend,mode,value)
        for path, limit in [('none','none'),('','none'),('.','2'),('dir','none'),('missing','none'),('a-file','none')]:
            value, _ = run('native',root,path,limit)
            args = {} if path == 'none' else {'path':path}
            if limit != 'none': args['limit'] = int(limit)
            upstream = json.loads(subprocess.check_output(['bun',str(oracle),str(root),json.dumps(args)],text=True))
            if 'error' in upstream:
                assert value == upstream, (backend,path,value,upstream)
            else:
                assert value['text'] == upstream['content'][0]['text'], (backend,path,value,upstream)
                assert (value['details'] != 'none') == bool(upstream.get('details'))
        many = root/'many'
        many.mkdir()
        names = [f'{i:04d}-'+('é'*100) for i in range(350)]
        for name in names: (many/name).touch()
        value,_ = run('native',root,'many',300)
        assert value == expected(names,300), (backend,value)
        # Real metadata permissions; access can succeed while enumeration fails.
        denied = root/'denied'
        denied.mkdir()
        denied.chmod(0)
        try:
            value,_ = run('native',root,'denied')
            assert value['error'].startswith('Cannot read directory: Error 13:'), value
        finally:
            denied.chmod(0o700)
    print(f'{backend}: {checks} public ls scenarios passed (explicit scalar comparator; default locale policy pending)')
